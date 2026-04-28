import { useEffect } from "react";
import { useKeycloak } from "@react-keycloak/web";

const AUTH_KEY = "kc_auth";

function readCache() {
  try {
    return JSON.parse(localStorage.getItem(AUTH_KEY));
  } catch {
    return null;
  }
}

export function useAuth() {
  const { keycloak, initialized } = useKeycloak();

  // After init, persist auth state + roles so the next page load renders correctly
  // before the silent SSO check finishes.
  useEffect(() => {
    if (!initialized) return;
    if (keycloak.authenticated) {
      localStorage.setItem(AUTH_KEY, JSON.stringify({
        roles: keycloak.realmAccess?.roles ?? [],
      }));
    } else {
      localStorage.removeItem(AUTH_KEY);
    }
  }, [initialized, keycloak.authenticated]);

  const cache = readCache();

  // Before Keycloak finishes, fall back to the cache to avoid flashing wrong state.
  const isAuthenticated = initialized ? !!keycloak.authenticated : !!cache;

  // hasRole also works from cache so isAdmin() renders correctly before init.
  const hasRole = (role) => {
    if (initialized) return keycloak.hasRealmRole(role);
    return cache?.roles?.includes(role) ?? false;
  };

  const isAdmin = () => hasRole("admin");
  const isUser  = () => hasRole("user");

  const login    = () => keycloak.login();
  const register = () => keycloak.register();
  const logout   = () => {
    localStorage.removeItem(AUTH_KEY);
    keycloak.logout({ redirectUri: window.location.origin });
  };

  return {
    keycloak,
    initialized,
    isAuthenticated,
    token: keycloak.token,
    login,
    register,
    logout,
    hasRole,
    isAdmin,
    isUser,
  };
}
