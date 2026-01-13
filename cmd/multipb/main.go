package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"
	"text/template"
	"time"

	"multi-pb/internal/api"
	"multi-pb/internal/config"
	"multi-pb/internal/manager"
)

func main() {
	log.SetFlags(log.LstdFlags | log.Lshortfile)
	log.Println("Starting Multi-PB Management Platform")

	// Get configuration from environment
	dataDir := getEnv("DATA_DIR", "/mnt/data")
	httpPort := getEnv("HTTP_PORT", "8080")
	domainName := getEnv("DOMAIN_NAME", "localhost.direct")
	enableHTTPS := getEnv("ENABLE_HTTPS", "false") == "true"
	acmeEmail := getEnv("ACME_EMAIL", "admin@example.com")

	// Initialize config store
	store, err := config.NewStore(dataDir)
	if err != nil {
		log.Fatalf("Failed to initialize config store: %v", err)
	}

	// Initialize process manager
	mgr := manager.NewManager(store)

	// Start existing tenants
	if err := mgr.Start(); err != nil {
		log.Printf("Warning: failed to start some tenants: %v", err)
	}

	// Initialize API server
	apiServer := api.NewServer(store, mgr)

	// Start Caddy config manager
	go runCaddyManager(store, mgr, domainName, enableHTTPS, acmeEmail)

	// Start HTTP server for API
	server := &http.Server{
		Addr:    ":" + httpPort,
		Handler: apiServer,
	}

	// Graceful shutdown
	go func() {
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
		<-sigChan

		log.Println("Shutting down...")
		
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		mgr.Stop()
		server.Shutdown(ctx)
	}()

	log.Printf("API server listening on port %s", httpPort)
	log.Printf("Dashboard: http://localhost:%s", httpPort)
	
	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("HTTP server error: %v", err)
	}
}

func runCaddyManager(store *config.Store, mgr *manager.Manager, domainName string, enableHTTPS bool, acmeEmail string) {
	caddyConfigPath := "/etc/Caddyfile"
	
	// Generate initial Caddy config
	if err := generateCaddyConfig(store, caddyConfigPath, domainName, enableHTTPS, acmeEmail); err != nil {
		log.Printf("Failed to generate Caddy config: %v", err)
	}

	// Start Caddy
	caddyCmd := startCaddy(caddyConfigPath)
	defer func() {
		if caddyCmd != nil && caddyCmd.Process != nil {
			caddyCmd.Process.Kill()
		}
	}()

	// Watch for reload signals
	for range mgr.CaddyReloadChan() {
		log.Println("Regenerating Caddy configuration...")
		if err := generateCaddyConfig(store, caddyConfigPath, domainName, enableHTTPS, acmeEmail); err != nil {
			log.Printf("Failed to regenerate Caddy config: %v", err)
			continue
		}
		
		// Reload Caddy
		reloadCaddy()
	}
}

func startCaddy(configPath string) *exec.Cmd {
	cmd := exec.Command("caddy", "run", "--config", configPath, "--adapter", "caddyfile")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	
	if err := cmd.Start(); err != nil {
		log.Printf("Failed to start Caddy: %v", err)
		return nil
	}
	
	log.Println("Caddy started")
	return cmd
}

func reloadCaddy() {
	cmd := exec.Command("caddy", "reload", "--config", "/etc/Caddyfile", "--adapter", "caddyfile")
	if err := cmd.Run(); err != nil {
		log.Printf("Failed to reload Caddy: %v", err)
	} else {
		log.Println("Caddy configuration reloaded")
	}
}

const caddyTemplate = `{{if .EnableHTTPS}}{
    email {{.ACMEEmail}}
    storage file_system {
        root /data
    }
}
{{else}}{
    auto_https off
}
{{end}}
# Dashboard
{{if .EnableHTTPS}}https://{{else}}http://{{end}}dashboard.{{.DomainName}} {
    header {
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        -Server
    }
    reverse_proxy localhost:{{.APIPort}}
}

# Tenant instances
{{range .Tenants}}
{{if $.EnableHTTPS}}https://{{else}}http://{{end}}{{.Subdomain}}.{{$.DomainName}} {
    header {
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        -Server
    }
    reverse_proxy localhost:{{.Port}}
}
{{end}}
`

func generateCaddyConfig(store *config.Store, outputPath string, domainName string, enableHTTPS bool, acmeEmail string) error {
	tmpl, err := template.New("caddy").Parse(caddyTemplate)
	if err != nil {
		return fmt.Errorf("failed to parse template: %w", err)
	}

	// Ensure directory exists
	if err := os.MkdirAll(filepath.Dir(outputPath), 0755); err != nil {
		return fmt.Errorf("failed to create directory: %w", err)
	}

	f, err := os.Create(outputPath)
	if err != nil {
		return fmt.Errorf("failed to create file: %w", err)
	}
	defer f.Close()

	data := struct {
		DomainName  string
		EnableHTTPS bool
		ACMEEmail   string
		APIPort     string
		Tenants     []*struct {
			Subdomain string
			Port      int
		}
	}{
		DomainName:  domainName,
		EnableHTTPS: enableHTTPS,
		ACMEEmail:   acmeEmail,
		APIPort:     getEnv("HTTP_PORT", "8080"),
	}

	// Get tenants
	for _, t := range store.GetTenants() {
		data.Tenants = append(data.Tenants, &struct {
			Subdomain string
			Port      int
		}{
			Subdomain: t.Subdomain,
			Port:      t.Port,
		})
	}

	if err := tmpl.Execute(f, data); err != nil {
		return fmt.Errorf("failed to execute template: %w", err)
	}

	return nil
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
