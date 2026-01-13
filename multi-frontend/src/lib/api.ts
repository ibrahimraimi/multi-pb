// API client for Multi-PB

const API_BASE = '/api';

export interface Tenant {
	id: string;
	name: string;
	subdomain: string;
	port: number;
	status: string;
	created_at: string;
	updated_at: string;
}

export interface TenantStatus {
	id: string;
	status: string;
	uptime_seconds?: number;
	admin_url: string;
	public_url: string;
}

export interface APIResponse<T = unknown> {
	success: boolean;
	data?: T;
	error?: string;
}

export interface StatusResponse {
	setup_done: boolean;
	domain_name: string;
	tenant_count: number;
}

export interface TenantsResponse {
	tenants: Tenant[];
	statuses: TenantStatus[];
}

async function request<T>(
	endpoint: string,
	options: RequestInit = {}
): Promise<APIResponse<T>> {
	try {
		const res = await fetch(`${API_BASE}${endpoint}`, {
			headers: {
				'Content-Type': 'application/json',
				...options.headers
			},
			...options
		});
		return await res.json();
	} catch (error) {
		return { success: false, error: String(error) };
	}
}

export const api = {
	// Status
	async getStatus(): Promise<APIResponse<StatusResponse>> {
		return request<StatusResponse>('/status');
	},

	// Setup
	async setup(email: string, password: string): Promise<APIResponse<{ message: string }>> {
		return request('/setup', {
			method: 'POST',
			body: JSON.stringify({
				admin_email: email,
				admin_password: password
			})
		});
	},

	// Auth
	async login(email: string, password: string): Promise<APIResponse<{ token: string }>> {
		return request('/auth/login', {
			method: 'POST',
			body: JSON.stringify({ email, password })
		});
	},

	// Tenants
	async getTenants(): Promise<APIResponse<TenantsResponse>> {
		return request<TenantsResponse>('/tenants');
	},

	async createTenant(
		name: string,
		subdomain: string
	): Promise<APIResponse<Tenant>> {
		return request('/tenants', {
			method: 'POST',
			body: JSON.stringify({ name, subdomain })
		});
	},

	async getTenantStatus(id: string): Promise<APIResponse<TenantStatus>> {
		return request<TenantStatus>(`/tenants/${id}`);
	},

	async deleteTenant(id: string, deleteData = false): Promise<APIResponse<{ message: string }>> {
		return request(`/tenants/${id}?delete_data=${deleteData}`, {
			method: 'DELETE'
		});
	},

	async restartTenant(id: string): Promise<APIResponse<{ message: string }>> {
		return request(`/tenants/${id}/restart`, {
			method: 'POST'
		});
	},

	async startTenant(id: string): Promise<APIResponse<{ message: string }>> {
		return request(`/tenants/${id}/start`, {
			method: 'POST'
		});
	},

	async stopTenant(id: string): Promise<APIResponse<{ message: string }>> {
		return request(`/tenants/${id}/stop`, {
			method: 'POST'
		});
	}
};
