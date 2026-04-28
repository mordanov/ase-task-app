import axios from "axios";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:8000";

const api = axios.create({ baseURL: API_URL });

export function setAuthToken(token) {
  if (token) {
    api.defaults.headers.common["Authorization"] = `Bearer ${token}`;
  } else {
    delete api.defaults.headers.common["Authorization"];
  }
}

export const getMe = () => api.get("/api/me");
export const listUsers = () => api.get("/api/admin/users");
export const toggleUser = (keycloakId, isActive) =>
  api.patch(`/api/admin/users/${keycloakId}/toggle`, { is_active: isActive });
