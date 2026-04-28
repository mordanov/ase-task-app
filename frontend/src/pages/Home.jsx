import React from "react";
import { useTranslation } from "react-i18next";
import { useAuth } from "../hooks/useAuth";

const styles = {
  container: {
    maxWidth: "700px",
    margin: "5rem auto",
    textAlign: "center",
    padding: "0 1.5rem",
  },
  title: { fontSize: "2.5rem", fontWeight: "700", color: "#1e293b", marginBottom: "1rem" },
  subtitle: { color: "#64748b", fontSize: "1.1rem", lineHeight: "1.7", marginBottom: "2.5rem" },
  btnGroup: { display: "flex", gap: "1rem", justifyContent: "center", flexWrap: "wrap" },
  primary: {
    background: "#6366f1", color: "#fff", border: "none",
    padding: "0.75rem 2rem", borderRadius: "8px", cursor: "pointer",
    fontSize: "1rem", fontWeight: "600",
  },
  secondary: {
    background: "transparent", color: "#6366f1",
    border: "2px solid #6366f1", padding: "0.75rem 2rem",
    borderRadius: "8px", cursor: "pointer", fontSize: "1rem", fontWeight: "600",
  },
  pill: {
    display: "inline-block",
    background: "#e0e7ff",
    color: "#4338ca",
    padding: "0.25rem 0.75rem",
    borderRadius: "999px",
    fontSize: "0.85rem",
    fontWeight: "600",
    marginBottom: "1.5rem",
  },
};

export default function Home() {
  const { isAuthenticated, login, register } = useAuth();
  const { t } = useTranslation();

  return (
    <div style={styles.container}>
      <span style={styles.pill}>{t("home.poweredBy")}</span>
      <h1 style={styles.title}>{t("home.title")}</h1>
      <p style={styles.subtitle}>{t("home.subtitle")}</p>

      {!isAuthenticated ? (
        <div style={styles.btnGroup}>
          <button style={styles.primary} onClick={login}>{t("nav.signIn")}</button>
          <button style={styles.secondary} onClick={register}>{t("home.createAccount")}</button>
        </div>
      ) : (
        <p style={{ color: "#16a34a", fontWeight: "600", fontSize: "1.1rem" }}>
          {t("home.signedIn")}
        </p>
      )}
    </div>
  );
}
