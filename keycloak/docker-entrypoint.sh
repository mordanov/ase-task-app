#!/bin/bash
set -euo pipefail

# Substitute all placeholders in the realm template before Keycloak imports it.
# Keycloak's --import-realm only supports ${env.VAR} syntax, not ${VAR},
# so we resolve everything here instead.

TEMPLATE=/opt/keycloak/data/import/realm-export.json.tmpl
REALM_FILE=/opt/keycloak/data/import/realm-export.json

if [[ -f "$TEMPLATE" ]]; then
  sed \
    -e "s|FRONTEND_URL_PLACEHOLDER|${FRONTEND_URL:-http://localhost:3001}|g" \
    -e "s|BACKEND_CLIENT_SECRET_PLACEHOLDER|${KC_BACKEND_CLIENT_SECRET:-backend-secret-key}|g" \
    -e "s|\${GOOGLE_CLIENT_ID}|${GOOGLE_CLIENT_ID:-}|g" \
    -e "s|\${GOOGLE_CLIENT_SECRET}|${GOOGLE_CLIENT_SECRET:-}|g" \
    -e "s|\${GITHUB_CLIENT_ID}|${GITHUB_CLIENT_ID:-}|g" \
    -e "s|\${GITHUB_CLIENT_SECRET}|${GITHUB_CLIENT_SECRET:-}|g" \
    -e "s|\${AZURE_APPLICATION_ID}|${AZURE_APPLICATION_ID:-}|g" \
    -e "s|\${AZURE_CLIENT_SECRET}|${AZURE_CLIENT_SECRET:-}|g" \
    "$TEMPLATE" > "$REALM_FILE"
  echo "[entrypoint] Realm config written to $REALM_FILE"
fi

exec /opt/keycloak/bin/kc.sh "$@"
