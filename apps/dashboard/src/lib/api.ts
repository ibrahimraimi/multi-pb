import { writable, get } from "svelte/store";

const STORAGE_KEY = "multipb_admin_token";

function getStored(): string | null {
  if (typeof window === "undefined") return null;
  try {
    const t = localStorage.getItem(STORAGE_KEY);
    return t && t.length > 0 ? t : null;
  } catch {
    return null;
  }
}

export const adminToken = writable<string | null>(getStored());
export const needsAuthModal = writable(false);
export const authRequired = writable<boolean | null>(null); // null = checking, true = required, false = not required

export function setToken(value: string | null): void {
  if (typeof window === "undefined") return;
  if (value == null || (typeof value === "string" && value.trim() === "")) {
    localStorage.removeItem(STORAGE_KEY);
    adminToken.set(null);
  } else {
    const t = value.trim();
    localStorage.setItem(STORAGE_KEY, t);
    adminToken.set(t);
    needsAuthModal.set(false);
  }
}

export function clearToken(): void {
  setToken(null);
  needsAuthModal.set(true);
}

export const API_BASE = "/api";

export type ApiFetchInit = RequestInit & { skipAuth?: boolean };

export async function checkAuthRequired(): Promise<boolean> {
  try {
    // Check auth status endpoint (doesn't require auth)
    const statusRes = await fetch(`${API_BASE}/auth/status`);
    if (statusRes.ok) {
      const status = await statusRes.json();
      const required = status.authRequired === true;
      authRequired.set(required);
      
      if (required) {
        const token = get(adminToken);
        if (!token) {
          needsAuthModal.set(true);
        } else {
          // Validate stored token with a real API call
          const tokenRes = await fetch(`${API_BASE}/stats`, {
            headers: { Authorization: `Bearer ${token}` },
          });
          if (tokenRes.status === 401) {
            clearToken();
          }
        }
      }
      return required;
    }
    // Fallback: try stats endpoint
    const res = await fetch(`${API_BASE}/stats`);
    const required = res.status === 401;
    authRequired.set(required);
    if (required && !get(adminToken)) {
      needsAuthModal.set(true);
    }
    return required;
  } catch {
    // Network error - assume not required for now
    authRequired.set(false);
    return false;
  }
}

export async function apiFetch(path: string, init: ApiFetchInit = {}): Promise<Response> {
  const { skipAuth, ...rest } = init;
  const token = get(adminToken);
  const headers = new Headers(rest.headers);
  if (!skipAuth && token) {
    headers.set("Authorization", `Bearer ${token}`);
  }
  const res = await fetch(`${API_BASE}${path.startsWith("/") ? path : `/${path}`}`, {
    ...rest,
    headers,
  });
  if (res.status === 401) {
    clearToken();
  }
  return res;
}
