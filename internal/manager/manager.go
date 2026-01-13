package manager

import (
	"bufio"
	"context"
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"multi-pb/internal/config"
	"multi-pb/internal/models"
)

// Manager handles PocketBase process lifecycle
type Manager struct {
	mu        sync.RWMutex
	store     *config.Store
	processes map[string]*Process
	caddyReload chan struct{}
}

// Process represents a running PocketBase instance
type Process struct {
	Tenant    *models.Tenant
	Cmd       *exec.Cmd
	StartedAt time.Time
	ctx       context.Context
	cancel    context.CancelFunc
}

// NewManager creates a new process manager
func NewManager(store *config.Store) *Manager {
	return &Manager{
		store:       store,
		processes:   make(map[string]*Process),
		caddyReload: make(chan struct{}, 10),
	}
}

// Start starts all registered tenants
func (m *Manager) Start() error {
	tenants := m.store.GetTenants()
	for _, t := range tenants {
		if err := m.StartTenant(t.ID); err != nil {
			log.Printf("Failed to start tenant %s: %v", t.ID, err)
		}
	}
	return nil
}

// Stop stops all running tenants
func (m *Manager) Stop() {
	m.mu.Lock()
	defer m.mu.Unlock()

	for id, proc := range m.processes {
		log.Printf("Stopping tenant %s", id)
		proc.cancel()
		if proc.Cmd.Process != nil {
			proc.Cmd.Process.Signal(syscall.SIGTERM)
		}
	}
}

// CreateTenant creates and starts a new tenant
func (m *Manager) CreateTenant(req models.CreateTenantRequest) (*models.CreateTenantResponse, error) {
	// Generate ID from subdomain
	id := sanitizeID(req.Subdomain)
	
	// Check if already exists
	if m.store.GetTenant(id) != nil {
		return nil, fmt.Errorf("tenant with subdomain '%s' already exists", req.Subdomain)
	}

	// Get next available port
	port := m.store.GetNextPort()

	// Create tenant data directory
	dataDir := filepath.Join(m.store.GetDataDir(), id)
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create data directory: %w", err)
	}

	tenant := &models.Tenant{
		ID:        id,
		Name:      req.Name,
		Subdomain: req.Subdomain,
		Port:      port,
		Status:    "stopped",
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
		DataDir:   dataDir,
	}

	// Save to store
	if err := m.store.AddTenant(tenant); err != nil {
		return nil, fmt.Errorf("failed to save tenant: %w", err)
	}

	// Start the tenant
	if err := m.StartTenant(id); err != nil {
		return nil, fmt.Errorf("failed to start tenant: %w", err)
	}

	// Trigger Caddy reload
	m.triggerCaddyReload()

	// Extract setup URL from log (PocketBase outputs it on first run)
	setupURL := m.extractSetupURL(id, tenant.Subdomain)

	return &models.CreateTenantResponse{
		Tenant:   tenant,
		SetupURL: setupURL,
	}, nil
}

// StartTenant starts a specific tenant
func (m *Manager) StartTenant(id string) error {
	tenant := m.store.GetTenant(id)
	if tenant == nil {
		return fmt.Errorf("tenant not found: %s", id)
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// Check if already running
	if proc, exists := m.processes[id]; exists && proc.Cmd.Process != nil {
		return nil // Already running
	}

	// Ensure data directory exists
	dataDir := filepath.Join(m.store.GetDataDir(), id)
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return fmt.Errorf("failed to create data directory: %w", err)
	}

	// Check if PocketBase binary exists
	if _, err := os.Stat("/usr/local/bin/pocketbase"); os.IsNotExist(err) {
		return fmt.Errorf("pocketbase binary not found at /usr/local/bin/pocketbase")
	}

	ctx, cancel := context.WithCancel(context.Background())

	cmd := exec.CommandContext(ctx,
		"/usr/local/bin/pocketbase",
		"serve",
		fmt.Sprintf("--dir=%s", dataDir),
		fmt.Sprintf("--http=127.0.0.1:%d", tenant.Port),
	)

	// Set up logging - truncate on start to avoid confusion with old logs
	logFile := filepath.Join(m.store.GetDataDir(), ".multi-pb", "logs", fmt.Sprintf("%s.log", id))
	os.MkdirAll(filepath.Dir(logFile), 0755)
	
	// Truncate to clear old output from previous runs
	f, err := os.OpenFile(logFile, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err == nil {
		cmd.Stdout = f
		cmd.Stderr = f
		// Write startup marker
		fmt.Fprintf(f, "[multi-pb] Starting PocketBase for tenant %s on port %d at %s\n", id, tenant.Port, time.Now().Format(time.RFC3339))
		fmt.Fprintf(f, "[multi-pb] Command: %s %v\n", cmd.Path, cmd.Args[1:])
		f.Sync()
	} else {
		log.Printf("Warning: failed to open log file for tenant %s: %v", id, err)
	}

	if err := cmd.Start(); err != nil {
		cancel()
		if f != nil {
			f.Close()
		}
		return fmt.Errorf("failed to start PocketBase: %w", err)
	}

	// Verify process is actually running
	if cmd.Process == nil {
		cancel()
		if f != nil {
			f.Close()
		}
		return fmt.Errorf("pocketbase process failed to start")
	}

	// Give the process a moment to start and check if it's still alive
	time.Sleep(500 * time.Millisecond)
	
	// Check if process is still running by trying to signal it
	// Signal 0 doesn't actually send a signal, just checks if process exists
	if err := cmd.Process.Signal(syscall.Signal(0)); err != nil {
		// Process doesn't exist - it may have exited immediately
		// Wait a moment to see if we can get the exit status
		time.Sleep(200 * time.Millisecond)
		
		select {
		case <-ctx.Done():
			// Context was cancelled, process was stopped
			cancel()
			if f != nil {
				f.Close()
			}
			return fmt.Errorf("process was cancelled")
		default:
			// Process likely exited - close log and return error
			// The monitorProcess will handle reading the log
			if f != nil {
				f.Close()
			}
			// Try to read log for error details
			logLines := m.readLastLogLines(id, 10)
			cancel()
			if logLines != "" {
				return fmt.Errorf("pocketbase process failed to start or exited immediately: %v\nLast log:\n%s", err, logLines)
			}
			return fmt.Errorf("pocketbase process failed to start or exited immediately: %v", err)
		}
	}

	// Verify the port is actually listening (PocketBase is ready)
	// PocketBase can take a few seconds to initialize, especially on first run
	maxRetries := 30 // 30 * 200ms = 6 seconds max wait
	for i := 0; i < maxRetries; i++ {
		time.Sleep(200 * time.Millisecond)
		
		// First check if process is still alive
		if err := cmd.Process.Signal(syscall.Signal(0)); err != nil {
			// Process died - sync and close log file to capture any buffered output
			if f != nil {
				f.Sync()
				f.Close()
			}
			time.Sleep(200 * time.Millisecond) // Let log flush to disk
			logLines := m.readLastLogLines(id, 25)
			cancel()
			if logLines != "" {
				return fmt.Errorf("pocketbase process died during startup\nLog:\n%s", logLines)
			}
			return fmt.Errorf("pocketbase process died during startup")
		}
		
		conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", tenant.Port), 100*time.Millisecond)
		if err == nil {
			conn.Close()
			log.Printf("Tenant %s port %d is ready after %dms", id, tenant.Port, (i+1)*200)
			break // Port is listening, PocketBase is ready
		}
		if i == maxRetries-1 {
			// Port never became available - PocketBase might have failed
			if f != nil {
				f.Sync()
				f.Close()
			}
			time.Sleep(200 * time.Millisecond) // Let log flush to disk
			logLines := m.readLastLogLines(id, 25)
			cancel()
			if logLines != "" {
				return fmt.Errorf("pocketbase started but port %d is not listening after %d seconds\nLog:\n%s", tenant.Port, maxRetries*200/1000, logLines)
			}
			return fmt.Errorf("pocketbase started but port %d is not listening after %d seconds", tenant.Port, maxRetries*200/1000)
		}
	}

	m.processes[id] = &Process{
		Tenant:    tenant,
		Cmd:       cmd,
		StartedAt: time.Now(),
		ctx:       ctx,
		cancel:    cancel,
	}

	// Update tenant status
	tenant.Status = "running"
	tenant.PID = cmd.Process.Pid
	tenant.UpdatedAt = time.Now()
	m.store.UpdateTenant(tenant)

	// Monitor process in background
	go m.monitorProcess(id, cmd)

	log.Printf("Started tenant %s on port %d (PID: %d)", id, tenant.Port, cmd.Process.Pid)
	return nil
}

// StopTenant stops a specific tenant
func (m *Manager) StopTenant(id string) error {
	m.mu.Lock()
	proc, exists := m.processes[id]
	m.mu.Unlock()

	if !exists {
		return nil // Not running
	}

	proc.cancel()
	if proc.Cmd.Process != nil {
		proc.Cmd.Process.Signal(syscall.SIGTERM)
		
		// Wait a bit for graceful shutdown
		done := make(chan error)
		go func() {
			done <- proc.Cmd.Wait()
		}()

		select {
		case <-done:
		case <-time.After(5 * time.Second):
			proc.Cmd.Process.Kill()
		}
	}

	m.mu.Lock()
	delete(m.processes, id)
	m.mu.Unlock()

	// Update tenant status
	if tenant := m.store.GetTenant(id); tenant != nil {
		tenant.Status = "stopped"
		tenant.PID = 0
		tenant.UpdatedAt = time.Now()
		m.store.UpdateTenant(tenant)
	}

	log.Printf("Stopped tenant %s", id)
	return nil
}

// RestartTenant restarts a specific tenant
func (m *Manager) RestartTenant(id string) error {
	if err := m.StopTenant(id); err != nil {
		return err
	}
	time.Sleep(500 * time.Millisecond)
	return m.StartTenant(id)
}

// DeleteTenant stops and removes a tenant
func (m *Manager) DeleteTenant(id string, deleteData bool) error {
	// Stop the tenant first
	if err := m.StopTenant(id); err != nil {
		return err
	}

	// Remove from store
	if err := m.store.RemoveTenant(id); err != nil {
		return err
	}

	// Optionally delete data
	if deleteData {
		dataDir := filepath.Join(m.store.GetDataDir(), id)
		if err := os.RemoveAll(dataDir); err != nil {
			log.Printf("Warning: failed to delete data directory: %v", err)
		}
	}

	// Trigger Caddy reload
	m.triggerCaddyReload()

	log.Printf("Deleted tenant %s (data deleted: %v)", id, deleteData)
	return nil
}

// GetTenantStatus returns the status of a tenant
func (m *Manager) GetTenantStatus(id string) (*models.TenantStatus, error) {
	tenant := m.store.GetTenant(id)
	if tenant == nil {
		return nil, fmt.Errorf("tenant not found: %s", id)
	}

	cfg := m.store.GetConfig()
	
	status := &models.TenantStatus{
		ID:        id,
		Status:    tenant.Status,
		AdminURL:  fmt.Sprintf("https://%s.%s/_/", tenant.Subdomain, cfg.DomainName),
		PublicURL: fmt.Sprintf("https://%s.%s/", tenant.Subdomain, cfg.DomainName),
	}

	m.mu.RLock()
	if proc, exists := m.processes[id]; exists {
		status.Uptime = int64(time.Since(proc.StartedAt).Seconds())
	}
	m.mu.RUnlock()

	return status, nil
}

// GetAllStatuses returns status for all tenants
func (m *Manager) GetAllStatuses() []*models.TenantStatus {
	tenants := m.store.GetTenants()
	statuses := make([]*models.TenantStatus, 0, len(tenants))

	for _, t := range tenants {
		status, err := m.GetTenantStatus(t.ID)
		if err == nil {
			statuses = append(statuses, status)
		}
	}

	return statuses
}

// CaddyReloadChan returns the channel for Caddy reload signals
func (m *Manager) CaddyReloadChan() <-chan struct{} {
	return m.caddyReload
}

func (m *Manager) triggerCaddyReload() {
	select {
	case m.caddyReload <- struct{}{}:
	default:
	}
}

func (m *Manager) monitorProcess(id string, cmd *exec.Cmd) {
	err := cmd.Wait()
	
	m.mu.Lock()
	proc, exists := m.processes[id]
	if exists {
		delete(m.processes, id)
	}
	m.mu.Unlock()

	if tenant := m.store.GetTenant(id); tenant != nil {
		wasIntentionallyStopped := false
		if proc != nil && proc.ctx != nil {
			select {
			case <-proc.ctx.Done():
				wasIntentionallyStopped = true
			default:
			}
		}

		if err != nil && !wasIntentionallyStopped {
			tenant.Status = "error"
			// Try to read last few lines of log for better error info
			logLines := m.readLastLogLines(id, 10)
			if logLines != "" {
				log.Printf("Tenant %s exited with error: %v\nLast log lines:\n%s", id, err, logLines)
			} else {
				log.Printf("Tenant %s exited with error: %v", id, err)
			}
		} else if wasIntentionallyStopped {
			tenant.Status = "stopped"
			log.Printf("Tenant %s stopped", id)
		} else {
			tenant.Status = "stopped"
		}
		tenant.PID = 0
		tenant.UpdatedAt = time.Now()
		m.store.UpdateTenant(tenant)

		// Auto-restart if it crashed (not if it was intentionally stopped)
		if err != nil && !wasIntentionallyStopped {
			log.Printf("Tenant %s crashed, attempting restart...", id)
			time.Sleep(2 * time.Second)
			m.StartTenant(id)
		}
	}
}

func (m *Manager) readLastLogLines(id string, lines int) string {
	logFile := filepath.Join(m.store.GetDataDir(), ".multi-pb", "logs", fmt.Sprintf("%s.log", id))
	file, err := os.Open(logFile)
	if err != nil {
		return ""
	}
	defer file.Close()

	var result []string
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		result = append(result, scanner.Text())
		if len(result) > lines {
			result = result[1:]
		}
	}

	if len(result) == 0 {
		return ""
	}
	return strings.Join(result, "\n")
}

func (m *Manager) extractSetupURL(id, subdomain string) string {
	cfg := m.store.GetConfig()
	logFile := filepath.Join(m.store.GetDataDir(), ".multi-pb", "logs", fmt.Sprintf("%s.log", id))
	
	// Wait a moment for PocketBase to write the setup URL
	time.Sleep(500 * time.Millisecond)
	
	file, err := os.Open(logFile)
	if err != nil {
		return ""
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		// Look for the PocketBase install URL
		// Format: http://127.0.0.1:8081/_/#/pbinstal/eyJhbGciOiJIUzI1NiIs...
		if idx := strings.Index(line, "/_/#/pbinstal/"); idx != -1 {
			// Extract the token part
			tokenStart := idx + len("/_/#/pbinstal/")
			token := line[tokenStart:]
			// Token ends at whitespace or end of line
			if spaceIdx := strings.IndexAny(token, " \t\n\r"); spaceIdx != -1 {
				token = token[:spaceIdx]
			}
			
			// Construct the public URL
			publicURL := fmt.Sprintf("http://%s.%s/_/#/pbinstal/%s", subdomain, cfg.DomainName, token)
			return publicURL
		}
	}
	
	return ""
}

func sanitizeID(s string) string {
	result := make([]byte, 0, len(s))
	for _, c := range []byte(s) {
		if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' {
			result = append(result, c)
		} else if c >= 'A' && c <= 'Z' {
			result = append(result, c+32) // lowercase
		} else if c == '_' || c == ' ' {
			result = append(result, '-')
		}
	}
	return string(result)
}
