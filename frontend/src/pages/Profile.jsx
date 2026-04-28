import React, { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useAuth } from "../hooks/useAuth";
import { getMe, setAuthToken } from "../api";

const styles = {
  container: { maxWidth: "600px", margin: "3rem auto", padding: "0 1.5rem" },
  card: {
    background: "#fff",
    borderRadius: "16px",
    padding: "2.5rem",
    boxShadow: "0 1px 3px rgba(0,0,0,0.08), 0 4px 16px rgba(0,0,0,0.06)",
    border: "1px solid #e2e8f0",
  },
  avatar: {
    width: "72px",
    height: "72px",
    borderRadius: "50%",
    background: "linear-gradient(135deg, #6366f1, #8b5cf6)",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    fontSize: "2rem",
    color: "#fff",
    fontWeight: "700",
    marginBottom: "1.5rem",
  },
  name: { fontSize: "1.5rem", fontWeight: "700", color: "#1e293b", marginBottom: "0.25rem" },
  email: { color: "#64748b", fontSize: "0.95rem", marginBottom: "1.5rem" },
  badge: {
    display: "inline-flex",
    alignItems: "center",
    gap: "0.35rem",
    background: "#dcfce7",
    color: "#166534",
    padding: "0.5rem 1rem",
    borderRadius: "999px",
    fontWeight: "600",
    fontSize: "0.9rem",
    marginBottom: "1.5rem",
  },
  divider: { borderTop: "1px solid #f1f5f9", margin: "1.5rem 0" },
  row: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    padding: "0.6rem 0",
  },
  label: { color: "#64748b", fontSize: "0.875rem" },
  value: { color: "#1e293b", fontSize: "0.875rem", fontWeight: "500" },
  rolePill: {
    background: "#e0e7ff",
    color: "#3730a3",
    padding: "0.2rem 0.6rem",
    borderRadius: "6px",
    fontSize: "0.8rem",
    fontWeight: "600",
  },
  error: {
    background: "#fef2f2",
    border: "1px solid #fecaca",
    color: "#dc2626",
    padding: "1rem",
    borderRadius: "8px",
    marginTop: "1rem",
  },
};

export default function Profile() {
  const { keycloak, initialized } = useAuth();
  const { t, i18n } = useTranslation();
  const [profile, setProfile] = useState(null);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!initialized || !keycloak.authenticated || !keycloak.token) return;

    let cancelled = false;

    setAuthToken(keycloak.token);
    setLoading(true);
    setError(null);

    getMe()
      .then((res) => { if (!cancelled) setProfile(res.data); })
      .catch((err) => {
        if (!cancelled) setError(err.response?.data?.detail || "Failed to load profile.");
      })
      .finally(() => { if (!cancelled) setLoading(false); });

    return () => { cancelled = true; };
  }, [initialized, keycloak.authenticated, keycloak.token]);

  if (loading) {
    return (
      <div style={styles.container}>
        <p style={{ color: "#64748b" }}>{t("profile.loading")}</p>
      </div>
    );
  }

  if (error) {
    return (
      <div style={styles.container}>
        <div style={styles.error}>{error}</div>
      </div>
    );
  }

  if (!profile) return null;

  const initials = [profile.first_name, profile.last_name]
    .filter(Boolean)
    .map((n) => n[0])
    .join("")
    .toUpperCase() || profile.email[0].toUpperCase();

  const locale = i18n.language === "ru" ? "ru-RU" : "en-US";

  return (
    <div style={styles.container}>
      <div style={styles.card}>
        <div style={styles.avatar}>{initials}</div>

        <div style={styles.name}>
          {profile.first_name} {profile.last_name}
        </div>
        <div style={styles.email}>{profile.email}</div>

        <div style={styles.badge}>
          <span>✓</span> {t("profile.authorised")}
        </div>

        <div style={styles.divider} />

        <div style={styles.row}>
          <span style={styles.label}>{t("profile.email")}</span>
          <span style={styles.value}>{profile.email}</span>
        </div>

        <div style={styles.row}>
          <span style={styles.label}>{t("profile.nickname")}</span>
          <span style={styles.value}>{profile.nickname || "—"}</span>
        </div>

        <div style={styles.row}>
          <span style={styles.label}>{t("profile.firstName")}</span>
          <span style={styles.value}>{profile.first_name || "—"}</span>
        </div>

        <div style={styles.row}>
          <span style={styles.label}>{t("profile.lastName")}</span>
          <span style={styles.value}>{profile.last_name || "—"}</span>
        </div>

        <div style={styles.row}>
          <span style={styles.label}>{t("profile.roles")}</span>
          <span style={{ display: "flex", gap: "0.4rem", flexWrap: "wrap" }}>
            {profile.roles
              .filter((r) => ["user", "admin"].includes(r))
              .map((r) => (
                <span key={r} style={styles.rolePill}>{r}</span>
              ))}
          </span>
        </div>

        <div style={styles.row}>
          <span style={styles.label}>{t("profile.lastLogin")}</span>
          <span style={styles.value}>
            {profile.last_login
              ? new Date(profile.last_login + "Z").toLocaleString(locale)
              : "—"}
          </span>
        </div>

        <div style={styles.row}>
          <span style={styles.label}>{t("profile.accountStatus")}</span>
          <span style={{ ...styles.value, color: profile.is_active ? "#16a34a" : "#dc2626" }}>
            {profile.is_active ? t("profile.active") : t("profile.disabled")}
          </span>
        </div>
      </div>
    </div>
  );
}
