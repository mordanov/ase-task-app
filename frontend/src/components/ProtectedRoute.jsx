import React from "react";
import { Navigate } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { useAuth } from "../hooks/useAuth";

export default function ProtectedRoute({ children, requiredRole }) {
  const { initialized, isAuthenticated, hasRole } = useAuth();
  const { t } = useTranslation();

  if (!initialized) {
    return (
      <div style={{ textAlign: "center", marginTop: "6rem", color: "#64748b" }}>
        {t("auth.loading")}
      </div>
    );
  }

  if (!isAuthenticated) {
    return <Navigate to="/" replace />;
  }

  if (requiredRole && !hasRole(requiredRole)) {
    return (
      <div style={{ textAlign: "center", marginTop: "6rem" }}>
        <p style={{ color: "#ef4444", fontSize: "1.1rem" }}>{t("auth.accessDenied")}</p>
        <p style={{ color: "#64748b", marginTop: "0.5rem" }}>
          {t("auth.noRole", { role: requiredRole })}
        </p>
      </div>
    );
  }

  return children;
}
