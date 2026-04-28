import React from "react";
import ReactDOM from "react-dom/client";
import { ReactKeycloakProvider } from "@react-keycloak/web";
import Keycloak from "keycloak-js";
import "./i18n/index.js";
import App from "./App.jsx";

const keycloak = new Keycloak({
  url: import.meta.env.VITE_KEYCLOAK_URL || "http://localhost:8080",
  realm: import.meta.env.VITE_KEYCLOAK_REALM || "app-realm",
  clientId: import.meta.env.VITE_KEYCLOAK_CLIENT_ID || "frontend-client",
});

const initOptions = {
  onLoad: "check-sso",
  pkceMethod: "S256",
  checkLoginIframe: false,
};

function onKeycloakEvent(event, error) {
  if (error) console.error("Keycloak event error:", error);
}

ReactDOM.createRoot(document.getElementById("root")).render(
  <ReactKeycloakProvider
    authClient={keycloak}
    initOptions={initOptions}
    onEvent={onKeycloakEvent}
  >
    <App />
  </ReactKeycloakProvider>
);
