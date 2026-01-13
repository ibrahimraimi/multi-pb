package config

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"

	"multi-pb/internal/models"
)

// Store manages persistent configuration
type Store struct {
	mu       sync.RWMutex
	config   models.Config
	admin    *models.AdminUser
	tenants  map[string]*models.Tenant
	dataDir  string
	configPath string
}

// NewStore creates a new config store
func NewStore(dataDir string) (*Store, error) {
	configDir := filepath.Join(dataDir, ".multi-pb")
	if err := os.MkdirAll(configDir, 0755); err != nil {
		return nil, err
	}

	s := &Store{
		dataDir:    dataDir,
		configPath: filepath.Join(configDir, "config.json"),
		tenants:    make(map[string]*models.Tenant),
		config: models.Config{
			DomainName:  getEnv("DOMAIN_NAME", "localhost.direct"),
			HTTPPort:    getEnvInt("HTTP_PORT", 8080),
			HTTPSPort:   getEnvInt("HTTPS_PORT", 8443),
			EnableHTTPS: getEnv("ENABLE_HTTPS", "false") == "true",
			ACMEEmail:   getEnv("ACME_EMAIL", "admin@example.com"),
			DataDir:     dataDir,
			SetupDone:   false,
		},
	}

	// Load existing config if present
	s.load()

	return s, nil
}

func (s *Store) load() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	data, err := os.ReadFile(s.configPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // No config yet, use defaults
		}
		return err
	}

	var stored struct {
		Config  models.Config             `json:"config"`
		Admin   *models.AdminUser         `json:"admin"`
		Tenants map[string]*models.Tenant `json:"tenants"`
	}

	if err := json.Unmarshal(data, &stored); err != nil {
		return err
	}

	// Merge with env vars (env takes precedence for some values)
	s.config.SetupDone = stored.Config.SetupDone
	s.admin = stored.Admin
	if stored.Tenants != nil {
		s.tenants = stored.Tenants
	}

	return nil
}

func (s *Store) save() error {
	stored := struct {
		Config  models.Config             `json:"config"`
		Admin   *models.AdminUser         `json:"admin"`
		Tenants map[string]*models.Tenant `json:"tenants"`
	}{
		Config:  s.config,
		Admin:   s.admin,
		Tenants: s.tenants,
	}

	data, err := json.MarshalIndent(stored, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(s.configPath, data, 0600)
}

// GetConfig returns the current config
func (s *Store) GetConfig() models.Config {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.config
}

// IsSetupDone returns whether initial setup is complete
func (s *Store) IsSetupDone() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.config.SetupDone
}

// CompleteSetup marks setup as done and saves admin user
func (s *Store) CompleteSetup(admin *models.AdminUser) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.config.SetupDone = true
	s.admin = admin

	return s.save()
}

// GetAdmin returns the admin user
func (s *Store) GetAdmin() *models.AdminUser {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.admin
}

// GetTenants returns all tenants
func (s *Store) GetTenants() []*models.Tenant {
	s.mu.RLock()
	defer s.mu.RUnlock()

	tenants := make([]*models.Tenant, 0, len(s.tenants))
	for _, t := range s.tenants {
		tenants = append(tenants, t)
	}
	return tenants
}

// GetTenant returns a tenant by ID
func (s *Store) GetTenant(id string) *models.Tenant {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.tenants[id]
}

// AddTenant adds a new tenant
func (s *Store) AddTenant(tenant *models.Tenant) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.tenants[tenant.ID] = tenant
	return s.save()
}

// UpdateTenant updates an existing tenant
func (s *Store) UpdateTenant(tenant *models.Tenant) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.tenants[tenant.ID] = tenant
	return s.save()
}

// RemoveTenant removes a tenant
func (s *Store) RemoveTenant(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	delete(s.tenants, id)
	return s.save()
}

// GetNextPort returns the next available port for a new tenant
func (s *Store) GetNextPort() int {
	s.mu.RLock()
	defer s.mu.RUnlock()

	maxPort := 8080 // Start after base port
	for _, t := range s.tenants {
		if t.Port > maxPort {
			maxPort = t.Port
		}
	}
	return maxPort + 1
}

// GetDataDir returns the data directory
func (s *Store) GetDataDir() string {
	return s.dataDir
}

// Helper functions
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		var i int
		if _, err := os.Stdin.Read([]byte{}); err == nil {
			return i
		}
	}
	return defaultValue
}
