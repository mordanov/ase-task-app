import React, { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useAuth } from "../hooks/useAuth";
import { listUsers, toggleUser, setAuthToken } from "../api";

const styles = {
  container: { maxWidth: "900px", margin: "3rem auto", padding: "0 1.5rem" },
  header: { marginBottom: "2rem" },
  title: { fontSize: "1.75rem", fontWeight: "700", color: "#1e293b", marginBottom: "0.35rem" },
  subtitle: { color: "#64748b", fontSize: "0.95rem" },
  table: {
    width: "100%",
    borderCollapse: "collapse",
    background: "#fff",
    borderRadius: "12px",
    overflow: "hidden",
    boxShadow: "0 1px 3px rgba(0,0,0,0.08)",
    border: "1px solid #e2e8f0",
  },
  th: {
    background: "#f8fafc",
    padding: "0.85rem 1.25rem",
    textAlign: "left",
    fontSize: "0.8rem",
    fontWeight: "600",
    color: "#64748b",
    textTransform: "uppercase",
    letterSpacing: "0.05em",
    borderBottom: "1px solid #e2e8f0",
  },
  td: {
    padding: "1rem 1.25rem",
    fontSize: "0.9rem",
    color: "#1e293b",
    borderBottom: "1px solid #f1f5f9",
    verticalAlign: "middle",
  },
  activeBadge: {
    background: "#dcfce7", color: "#166534",
    padding: "0.2rem 0.7rem", borderRadius: "999px",
    fontSize: "0.8rem", fontWeight: "600",
  },
  disabledBadge: {
    background: "#fee2e2", color: "#991b1b",
    padding: "0.2rem 0.7rem", borderRadius: "999px",
    fontSize: "0.8rem", fontWeight: "600",
  },
  enableBtn: {
    background: "#dcfce7", color: "#166534",
    border: "1px solid #bbf7d0", padding: "0.35rem 0.9rem",
    borderRadius: "6px", cursor: "pointer", fontSize: "0.8rem", fontWeight: "600",
  },
  disableBtn: {
    background: "#fee2e2", color: "#991b1b",
    border: "1px solid #fecaca", padding: "0.35rem 0.9rem",
    borderRadius: "6px", cursor: "pointer", fontSize: "0.8rem", fontWeight: "600",
  },
  empty: { textAlign: "center", padding: "3rem", color: "#94a3b8" },
  error: {
    background: "#fef2f2", border: "1px solid #fecaca",
    color: "#dc2626", padding: "1rem", borderRadius: "8px", marginBottom: "1.5rem",
  },
  avatarCell: {
    width: "36px", height: "36px", borderRadius: "50%",
    background: "#6366f1", color: "#fff",
    display: "inline-flex", alignItems: "center", justifyContent: "center",
    fontWeight: "700", fontSize: "0.85rem", marginRight: "0.75rem",
    flexShrink: 0,
  },
  nameCell: { display: "flex", alignItems: "center" },
};

export default function Admin() {
  const { keycloak, initialized } = useAuth();
  const { t } = useTranslation();
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [toggling, setToggling] = useState(null);

  const currentUserId = keycloak?.subject;

  useEffect(() => {
    if (!initialized || !keycloak.authenticated || !keycloak.token) return;

    let cancelled = false;

    setAuthToken(keycloak.token);
    setLoading(true);
    setError(null);

    listUsers()
      .then((res) => { if (!cancelled) setUsers(res.data); })
      .catch((err) => {
        if (!cancelled) setError(err.response?.data?.detail || "Failed to load users.");
      })
      .finally(() => { if (!cancelled) setLoading(false); });

    return () => { cancelled = true; };
  }, [initialized, keycloak.authenticated, keycloak.token]);

  async function handleToggle(user) {
    setToggling(user.keycloak_id);
    try {
      const res = await toggleUser(user.keycloak_id, !user.is_active);
      setUsers((prev) =>
        prev.map((u) => (u.keycloak_id === user.keycloak_id ? res.data : u))
      );
    } catch (err) {
      setError(err.response?.data?.detail || "Failed to update user.");
    } finally {
      setToggling(null);
    }
  }

  function getInitials(user) {
    return [user.first_name, user.last_name]
      .filter(Boolean)
      .map((n) => n[0])
      .join("")
      .toUpperCase() || user.email[0].toUpperCase();
  }

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <h1 style={styles.title}>{t("admin.title")}</h1>
        <p style={styles.subtitle}>{t("admin.subtitle")}</p>
      </div>

      {error && <div style={styles.error}>{error}</div>}

      {loading ? (
        <p style={{ color: "#64748b" }}>{t("admin.loading")}</p>
      ) : users.length === 0 ? (
        <div style={styles.empty}>{t("admin.noUsers")}</div>
      ) : (
        <table style={styles.table}>
          <thead>
            <tr>
              <th style={styles.th}>{t("admin.colUser")}</th>
              <th style={styles.th}>{t("admin.colEmail")}</th>
              <th style={styles.th}>{t("admin.colStatus")}</th>
              <th style={styles.th}>{t("admin.colAction")}</th>
            </tr>
          </thead>
          <tbody>
            {users.map((user) => (
              <tr key={user.keycloak_id}>
                <td style={styles.td}>
                  <div style={styles.nameCell}>
                    <span style={styles.avatarCell}>{getInitials(user)}</span>
                    <span>
                      {user.first_name || ""} {user.last_name || ""}
                      {!user.first_name && !user.last_name && (
                        <span style={{ color: "#94a3b8" }}>—</span>
                      )}
                      {user.keycloak_id === currentUserId && (
                        <span style={{
                          marginLeft: "0.5rem", fontSize: "0.75rem",
                          background: "#e0e7ff", color: "#3730a3",
                          padding: "0.1rem 0.4rem", borderRadius: "4px",
                        }}>{t("admin.you")}</span>
                      )}
                    </span>
                  </div>
                </td>
                <td style={styles.td}>{user.email}</td>
                <td style={styles.td}>
                  <span style={user.is_active ? styles.activeBadge : styles.disabledBadge}>
                    {user.is_active ? t("admin.active") : t("admin.disabled")}
                  </span>
                </td>
                <td style={styles.td}>
                  {user.keycloak_id === currentUserId ? (
                    <span style={{ color: "#94a3b8", fontSize: "0.8rem" }}>
                      {t("admin.cannotModifySelf")}
                    </span>
                  ) : (
                    <button
                      style={user.is_active ? styles.disableBtn : styles.enableBtn}
                      onClick={() => handleToggle(user)}
                      disabled={toggling === user.keycloak_id}
                    >
                      {toggling === user.keycloak_id
                        ? "…"
                        : user.is_active
                        ? t("admin.disable")
                        : t("admin.enable")}
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
