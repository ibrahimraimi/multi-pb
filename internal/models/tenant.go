package models

import "time"

// Tenant represents a PocketBase instance
type Tenant struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Subdomain string    `json:"subdomain"`
	Port      int       `json:"port"`
	Status    string    `json:"status"` // running, stopped, starting, error
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
	PID       int       `json:"-"` // Process ID, not exposed via API
	DataDir   string    `json:"-"` // Internal path
}

// TenantStatus represents the health status of a tenant
type TenantStatus struct {
	ID        string `json:"id"`
	Status    string `json:"status"`
	Uptime    int64  `json:"uptime_seconds,omitempty"`
	AdminURL  string `json:"admin_url"`
	PublicURL string `json:"public_url"`
}

// CreateTenantResponse is returned when creating a new tenant
type CreateTenantResponse struct {
	Tenant   *Tenant `json:"tenant"`
	SetupURL string  `json:"setup_url,omitempty"` // PocketBase first-time setup URL
}

// CreateTenantRequest is the request body for creating a tenant
type CreateTenantRequest struct {
	Name      string `json:"name"`
	Subdomain string `json:"subdomain"`
}

// Config represents the application configuration
type Config struct {
	DomainName  string `json:"domain_name"`
	HTTPPort    int    `json:"http_port"`
	HTTPSPort   int    `json:"https_port"`
	EnableHTTPS bool   `json:"enable_https"`
	ACMEEmail   string `json:"acme_email"`
	DataDir     string `json:"data_dir"`
	SetupDone   bool   `json:"setup_done"`
}

// SetupRequest is the request body for initial setup
type SetupRequest struct {
	AdminEmail    string `json:"admin_email"`
	AdminPassword string `json:"admin_password"`
	DomainName    string `json:"domain_name"`
}

// AdminUser represents the admin user
type AdminUser struct {
	Email        string `json:"email"`
	PasswordHash string `json:"-"`
}

// APIResponse is a generic API response
type APIResponse struct {
	Success bool        `json:"success"`
	Data    interface{} `json:"data,omitempty"`
	Error   string      `json:"error,omitempty"`
}
