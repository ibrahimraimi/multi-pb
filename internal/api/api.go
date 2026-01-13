package api

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"multi-pb/internal/config"
	"multi-pb/internal/manager"
	"multi-pb/internal/models"

	"golang.org/x/crypto/bcrypt"
)

var dashboardDir = getEnvOrDefault("DASHBOARD_DIR", "/app/dashboard")

func getEnvOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// Server is the HTTP API server
type Server struct {
	store   *config.Store
	manager *manager.Manager
	mux     *http.ServeMux
}

// NewServer creates a new API server
func NewServer(store *config.Store, mgr *manager.Manager) *Server {
	s := &Server{
		store:   store,
		manager: mgr,
		mux:     http.NewServeMux(),
	}
	s.setupRoutes()
	return s
}

func (s *Server) setupRoutes() {
	// API routes
	s.mux.HandleFunc("/api/health", s.handleHealth)
	s.mux.HandleFunc("/api/status", s.handleStatus)
	s.mux.HandleFunc("/api/setup", s.handleSetup)
	s.mux.HandleFunc("/api/auth/login", s.handleLogin)
	s.mux.HandleFunc("/api/tenants", s.handleTenants)
	s.mux.HandleFunc("/api/tenants/", s.handleTenant)
	
	// Serve static files (embedded dashboard)
	s.mux.HandleFunc("/", s.handleStatic)
}

// ServeHTTP implements http.Handler
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// CORS headers for API
	if strings.HasPrefix(r.URL.Path, "/api/") {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
	}
	
	s.mux.ServeHTTP(w, r)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	json.NewEncoder(w).Encode(models.APIResponse{
		Success: true,
		Data:    map[string]string{"status": "ok"},
	})
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	cfg := s.store.GetConfig()
	
	data := map[string]interface{}{
		"setup_done":  s.store.IsSetupDone(),
		"domain_name": cfg.DomainName,
		"tenant_count": len(s.store.GetTenants()),
	}
	
	json.NewEncoder(w).Encode(models.APIResponse{
		Success: true,
		Data:    data,
	})
}

func (s *Server) handleSetup(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		s.error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if s.store.IsSetupDone() {
		s.error(w, "Setup already completed", http.StatusBadRequest)
		return
	}

	var req models.SetupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Validate
	if req.AdminEmail == "" || req.AdminPassword == "" {
		s.error(w, "Email and password are required", http.StatusBadRequest)
		return
	}

	if len(req.AdminPassword) < 8 {
		s.error(w, "Password must be at least 8 characters", http.StatusBadRequest)
		return
	}

	// Hash password
	hash, err := bcrypt.GenerateFromPassword([]byte(req.AdminPassword), bcrypt.DefaultCost)
	if err != nil {
		s.error(w, "Failed to hash password", http.StatusInternalServerError)
		return
	}

	admin := &models.AdminUser{
		Email:        req.AdminEmail,
		PasswordHash: string(hash),
	}

	if err := s.store.CompleteSetup(admin); err != nil {
		s.error(w, "Failed to save configuration", http.StatusInternalServerError)
		return
	}

	log.Printf("Setup completed for admin: %s", req.AdminEmail)

	json.NewEncoder(w).Encode(models.APIResponse{
		Success: true,
		Data:    map[string]string{"message": "Setup completed"},
	})
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		s.error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	admin := s.store.GetAdmin()
	if admin == nil {
		s.error(w, "Setup not completed", http.StatusUnauthorized)
		return
	}

	if req.Email != admin.Email {
		s.error(w, "Invalid credentials", http.StatusUnauthorized)
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(admin.PasswordHash), []byte(req.Password)); err != nil {
		s.error(w, "Invalid credentials", http.StatusUnauthorized)
		return
	}

	// For simplicity, return a basic token (in production, use JWT)
	// This is a placeholder - the dashboard will use this
	token := "mpb_" + admin.Email // Simple token for now

	json.NewEncoder(w).Encode(models.APIResponse{
		Success: true,
		Data:    map[string]string{"token": token},
	})
}

func (s *Server) handleTenants(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case "GET":
		tenants := s.store.GetTenants()
		statuses := s.manager.GetAllStatuses()
		
		json.NewEncoder(w).Encode(models.APIResponse{
			Success: true,
			Data:    map[string]interface{}{
				"tenants":  tenants,
				"statuses": statuses,
			},
		})

	case "POST":
		var req models.CreateTenantRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			s.error(w, "Invalid request body", http.StatusBadRequest)
			return
		}

		if req.Subdomain == "" {
			s.error(w, "Subdomain is required", http.StatusBadRequest)
			return
		}

		if req.Name == "" {
			req.Name = req.Subdomain
		}

		response, err := s.manager.CreateTenant(req)
		if err != nil {
			s.error(w, err.Error(), http.StatusBadRequest)
			return
		}

		json.NewEncoder(w).Encode(models.APIResponse{
			Success: true,
			Data:    response,
		})

	default:
		s.error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

func (s *Server) handleTenant(w http.ResponseWriter, r *http.Request) {
	// Extract tenant ID from path: /api/tenants/{id} or /api/tenants/{id}/action
	path := strings.TrimPrefix(r.URL.Path, "/api/tenants/")
	parts := strings.Split(path, "/")
	id := parts[0]
	action := ""
	if len(parts) > 1 {
		action = parts[1]
	}

	if id == "" {
		s.error(w, "Tenant ID required", http.StatusBadRequest)
		return
	}

	switch {
	case action == "" && r.Method == "GET":
		status, err := s.manager.GetTenantStatus(id)
		if err != nil {
			s.error(w, err.Error(), http.StatusNotFound)
			return
		}
		json.NewEncoder(w).Encode(models.APIResponse{
			Success: true,
			Data:    status,
		})

	case action == "" && r.Method == "DELETE":
		deleteData := r.URL.Query().Get("delete_data") == "true"
		if err := s.manager.DeleteTenant(id, deleteData); err != nil {
			s.error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(models.APIResponse{
			Success: true,
			Data:    map[string]string{"message": "Tenant deleted"},
		})

	case action == "restart" && r.Method == "POST":
		if err := s.manager.RestartTenant(id); err != nil {
			s.error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(models.APIResponse{
			Success: true,
			Data:    map[string]string{"message": "Tenant restarted"},
		})

	case action == "start" && r.Method == "POST":
		if err := s.manager.StartTenant(id); err != nil {
			s.error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(models.APIResponse{
			Success: true,
			Data:    map[string]string{"message": "Tenant started"},
		})

	case action == "stop" && r.Method == "POST":
		if err := s.manager.StopTenant(id); err != nil {
			s.error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(models.APIResponse{
			Success: true,
			Data:    map[string]string{"message": "Tenant stopped"},
		})

	default:
		s.error(w, "Not found", http.StatusNotFound)
	}
}

func (s *Server) handleStatic(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path
	if path == "/" {
		path = "/index.html"
	}

	// Try to serve the file from dashboard directory
	filePath := filepath.Join(dashboardDir, path)
	if _, err := os.Stat(filePath); err != nil {
		// SPA fallback - serve index.html for unknown paths
		filePath = filepath.Join(dashboardDir, "index.html")
	}

	http.ServeFile(w, r, filePath)
}

func (s *Server) error(w http.ResponseWriter, message string, status int) {
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(models.APIResponse{
		Success: false,
		Error:   message,
	})
}
