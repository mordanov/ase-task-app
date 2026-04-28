import React from "react";
import { Link, useLocation } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { useAuth } from "../hooks/useAuth";

const styles = {
  nav: {
    background: "#1e293b",
    padding: "0 2rem",
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    height: "60px",
    boxShadow: "0 1px 3px rgba(0,0,0,0.3)",
  },
  logo: {
    color: "#fff",
    fontWeight: "700",
    fontSize: "1.1rem",
    textDecoration: "none",
    letterSpacing: "0.02em",
  },
  links: { display: "flex", gap: "1.5rem", alignItems: "center" },
  link: {
    color: "#94a3b8",
    textDecoration: "none",
    fontSize: "0.9rem",
    padding: "0.3rem 0",
    borderBottom: "2px solid transparent",
    transition: "color 0.15s, border-color 0.15s",
  },
  activeLink: { color: "#fff", borderBottom: "2px solid #6366f1" },
  btn: {
    background: "transparent",
    border: "1px solid #475569",
    color: "#94a3b8",
    padding: "0.4rem 1rem",
    borderRadius: "6px",
    cursor: "pointer",
    fontSize: "0.85rem",
    transition: "all 0.15s",
  },
  loginBtn: {
    background: "#6366f1",
    border: "none",
    color: "#fff",
    padding: "0.4rem 1rem",
    borderRadius: "6px",
    cursor: "pointer",
    fontSize: "0.85rem",
    marginRight: "0.5rem",
  },
  divider: {
    width: "1px",
    height: "20px",
    background: "#334155",
    margin: "0 0.25rem",
  },
  langBtn: {
    background: "transparent",
    border: "1px solid transparent",
    color: "#64748b",
    padding: "0.25rem 0.45rem",
    borderRadius: "4px",
    cursor: "pointer",
    fontSize: "0.75rem",
    fontWeight: "700",
    letterSpacing: "0.06em",
    transition: "all 0.15s",
  },
  langBtnActive: {
    color: "#fff",
    border: "1px solid #475569",
    background: "#334155",
  },
};

export default function Navbar() {
  const { isAuthenticated, isAdmin, login, register, logout } = useAuth();
  const location = useLocation();
  const { t, i18n } = useTranslation();

  const isActive = (path) =>
    location.pathname === path ? { ...styles.link, ...styles.activeLink } : styles.link;

  const setLang = (lng) => i18n.changeLanguage(lng);

  return (
    <nav style={styles.nav}>
      <Link to="/" style={styles.logo}>🔐 AuthApp</Link>

      <div style={styles.links}>
        {isAuthenticated && (
          <>
            <Link to="/profile" style={isActive("/profile")}>{t("nav.profile")}</Link>
            {isAdmin() && (
              <Link to="/admin" style={isActive("/admin")}>{t("nav.userManagement")}</Link>
            )}
            {isAdmin() && (
              <a
                href="/admin/"
                target="_blank"
                rel="noopener noreferrer"
                style={styles.link}
              >
                {t("nav.adminConsole")}
              </a>
            )}
          </>
        )}

        {!isAuthenticated ? (
          <>
            <button style={styles.loginBtn} onClick={login}>{t("nav.signIn")}</button>
            <button style={styles.btn} onClick={register}>{t("nav.register")}</button>
          </>
        ) : (
          <button style={styles.btn} onClick={logout}>{t("nav.signOut")}</button>
        )}

        <div style={styles.divider} />

        <button
          style={i18n.language === "en" ? { ...styles.langBtn, ...styles.langBtnActive } : styles.langBtn}
          onClick={() => setLang("en")}
          aria-label="Switch to English"
        >
          EN
        </button>
        <button
          style={i18n.language === "ru" ? { ...styles.langBtn, ...styles.langBtnActive } : styles.langBtn}
          onClick={() => setLang("ru")}
          aria-label="Переключить на русский"
        >
          RU
        </button>
      </div>
    </nav>
  );
}
