# AGENTS.md — Keycloak Auth App

Guide for AI agents working on this full-stack authentication platform with Keycloak, FastAPI, and React.

## Architecture Overview

**Three-tier architecture:**

1. **Frontend (React 18 + Vite)** — Port 3000 in container (exposed as 3001 on host), uses `keycloak-js` adapter for OIDC login flow
2. **Backend API (FastAPI)** — Port 8000 (exposed as 3030), verifies JWT tokens and manages user access
3. **Keycloak (OIDC provider)** — Port 8080, manages realm (`app-realm`), clients, roles, and identity
4. **PostgreSQL** — Shared database for both Keycloak state and application `user_access` table

**Service naming in Docker Compose:** service DNS names are `keycloak`, `backend`, `frontend`, `postgres`; container names are `keycloak`, `kc_backend`, `kc_frontend`, `kc_postgres`.

## Critical Token Flow (Why Architecture Matters)

Understanding this flow is essential for debugging auth issues:

1. User visits frontend → Keycloak JS adapter detects not authenticated
2. Frontend redirects to Keycloak login (e.g., `http://keycloak:8080/realms/app-realm/protocol/openid-connect/auth`)
3. User authenticates (email/password, Google OAuth, etc.)
4. Keycloak issues signed JWT (RS256) and redirects back with auth code
5. Frontend exchanges code for token silently via iframe (see `public/silent-check-sso.html`)
6. Frontend stores token in memory via `keycloak.token` (XSS protection); only lightweight auth cache (`roles`) is kept in localStorage (`kc_auth`)
7. Frontend sends `Authorization: Bearer <token>` with every API call (via `api.js` axios interceptor)
8. Backend validates signature against Keycloak's public JWKS endpoint (fetched and cached in `auth.py`)
9. Backend extracts `realm_access.roles` from token payload and checks permissions
10. On first successful API call to `/api/me`, backend **upserts** user into `user_access` table (auto-registration)

**Critical**: JWKS cache (`_jwks_cache` in `auth.py`) is global. If Keycloak keys rotate, cache invalidation happens only on failed verification.

## Project-Specific Conventions

### Database Design
- **Single table: `user_access`** — Only tracks Keycloak users who have logged in at least once
- **Keycloak ID is primary key** — Immutable link to Keycloak identity
- **Admin disable is independent** — Admins can disable access without modifying Keycloak (403 response from `GET /api/me` if `is_active=false`)
- **No explicit migrations** — `Alembic` is in requirements.txt but unused; schema auto-created via SQLAlchemy on startup (`init_db()` in lifespan)

### Authentication Pattern
- **Backend uses FastAPI dependency injection** — `get_current_user` and `require_role()` are reusable dependency functions (see `auth.py` lines 59–76)
- **Role enforcement on backend only** — Frontend checks roles client-side for UX (hiding buttons) but **all endpoints validate server-side**
- **No refresh token handling** — Access token lifetime is 5 minutes (Keycloak config); frontend must re-authenticate when token expires

### Frontend Auth State Management
- **useAuth() hook** — Single source of truth in `src/hooks/useAuth.js`; exposes `keycloak`, `initialized`, `isAuthenticated`, `token`, `hasRole(role)`, `isAdmin()`, `isUser()`, `login()`, `register()`, `logout()`
- **Local auth cache for pre-init UX** — `useAuth()` stores only `roles` in localStorage key `kc_auth` so role-based UI does not flicker before Keycloak initialization finishes
- **Token injection** — `api.js` calls `setAuthToken(token)` after login to configure axios default headers
- **Protected routes via `ProtectedRoute` component** — Wraps components requiring auth; accepts optional `requiredRole` prop (see `src/components/ProtectedRoute.jsx`)

### API Structure
- **All endpoints under `/api/` prefix** — Matches `CORS_ORIGINS` config
- **Health endpoint is public** — `/health` (no auth) for Kubernetes readiness probes
- **Admin endpoints namespaced** — `/api/admin/*` (role-protected via `require_role("admin")`)
- **Pydantic models for request/response** — See `main.py` lines 35–56 for schema definitions

## Developer Workflows

### Starting the Stack
```bash
docker compose up -d
# Wait ~90 seconds for Keycloak to initialize
# Watch logs: docker compose logs -f keycloak
```

### Ports & URLs
| Component | Port | URL |
|-----------|------|-----|
| Frontend | 3000 (internal) / 3001 (host) | http://localhost:3001 |
| Backend | 8000 (internal) / 3030 (host) | http://localhost:3030/docs (Swagger) |
| Keycloak | 8080 | http://localhost:8080 (admin console at /auth) |
| Postgres | 5432 (internal) | — |

### Database Access from Backend
- Connection string: `postgresql+asyncpg://keycloak:keycloak_secret@postgres:5432/keycloak` (from `config.py`)
- Backend uses **async SQLAlchemy** — All DB calls use `async with AsyncSessionLocal()` pattern
- Session provided via `get_db()` dependency (see `database.py` line 31)

### Debugging Auth Issues

**JWKS cache stale?** → `docker compose restart backend` (clears `_jwks_cache` global)

**401 on valid token?** → Check Keycloak health: `docker compose logs keycloak | grep "started"`

**Frontend shows blank page?** → Check browser console for OIDC redirect errors; ensure Keycloak is ready before opening `http://localhost:3001`

**User disabled but still has valid token?** → That's by design; backend checks `user_access.is_active` on `/api/me` call, not on middleware

### Adding New API Endpoints
1. Add Pydantic schema in `main.py` (near line 33)
2. Define route with `@app.get()` or `@app.post()` etc.
3. Add dependencies: `token_data: dict = Depends(get_current_user)` or `Depends(require_role("admin"))`
4. Pass `db: AsyncSession = Depends(get_db)` if accessing database
5. Endpoint auto-documented in Swagger (`/docs`)

### Adding Frontend Pages
1. Create component in `src/pages/`
2. Add route in `App.jsx` (line 14)
3. Wrap route in `<ProtectedRoute>` if auth required
4. Use `useAuth()` hook to access token and user roles
5. Call API via `api.js` functions (token header auto-injected by `setAuthToken()`)

## Integration Points & External Dependencies

### Keycloak
- **Why this version?** — 24.0.3 specified in `docker-compose.yml` line 22; matches `keycloak-js` version in frontend
- **Pre-configured realm** — `keycloak/realm-export.json` auto-imported on container start (volume mount on line 37)
- **Realm details:**
  - Name: `app-realm`
  - Clients: `frontend-client` (public, no secret), `backend-client` (confidential, secret required)
  - Roles: `user` (default), `admin`
  - Self-registration enabled
  - JWKS endpoint: `http://keycloak:8080/realms/app-realm/protocol/openid-connect/certs`

### Frontend Libraries
- **`@react-keycloak/web`** — Wraps Keycloak JS adapter; provides `useKeycloak()` hook initialized at app root
- **`react-router-dom`** — Client-side routing; no special auth middleware needed (manual `ProtectedRoute` guards)
- **`axios`** — HTTP client; configured once in `api.js` with auth token default header
- **`i18next` + `react-i18next` + `i18next-browser-languagedetector`** — UI translations are initialized in `frontend/src/i18n/index.js` with language preference cached in localStorage key `lang`

### Backend Libraries
- **`python-keycloak`** — Installed but **not used**; JWT verification done manually via `python-jose` (lower overhead)
- **`python-jose[cryptography]`** — JWT decode with RS256 verification
- **`sqlalchemy` + `asyncpg`** — Async ORM + PostgreSQL driver
- **`pydantic` + `pydantic-settings`** — Request validation and environment config (no `.env` file required; defaults in `config.py`)

### Deployment Integrations
- **AWS IaC + CI/CD exist in-repo** — `aws/cloudformation/*.yml` and `aws/scripts/bootstrap.sh` provision infra; `.github/workflows/deploy.yml` builds backend/keycloak images, deploys frontend to S3/CloudFront, and rolls ECS services
- **Keycloak realm template for cloud deploys** — CI temporarily swaps to `keycloak/realm-export-template.json`; `keycloak/docker-entrypoint.sh` injects `KC_FRONTEND_URL` and `KC_BACKEND_CLIENT_SECRET` at container startup

## Critical Files to Know

| File | Purpose | Common Edits |
|------|---------|--------------|
| `backend/auth.py` | JWT validation, role guards | Add new role checks; debug token parsing |
| `backend/main.py` | API routes, Pydantic schemas | Add endpoints; modify request/response shapes |
| `backend/database.py` | SQLAlchemy ORM, migrations | Add new tables/columns (auto-migrates on startup) |
| `backend/config.py` | Environment variables | Change Keycloak URL, CORS origins, etc. |
| `frontend/src/hooks/useAuth.js` | Auth state & methods | Expose new auth helpers |
| `frontend/src/components/ProtectedRoute.jsx` | Route guards | Modify permission logic |
| `frontend/src/api.js` | API client | Add new endpoints; configure interceptors |
| `frontend/src/i18n/index.js` | i18n setup and language detection | Add locales; adjust language persistence |
| `keycloak/realm-export.json` | Keycloak config | Add new roles, clients, identity providers (regenerate export if changed) |
| `keycloak/realm-export-template.json` | Production realm template | Update placeholders for CloudFront URL/client secret |
| `docker-compose.yml` | Service orchestration | Expose ports, add environment variables, change service order |
| `.github/workflows/deploy.yml` | AWS deployment pipeline | Adjust image build/deploy steps and environment wiring |

## Environment Variables (How to Override)

**Backend** (set in `docker-compose.yml` backend service):
- `KEYCLOAK_URL` — Internal URL (use `http://keycloak:8080` in container)
- `KEYCLOAK_REALM` — Must match realm name in Keycloak (default: `app-realm`)
- `KEYCLOAK_CLIENT_ID` — Backend confidential client id (`backend-client`)
- `KEYCLOAK_CLIENT_SECRET` — Backend confidential client secret (must match Keycloak client secret)
- `DATABASE_URL` — SQLAlchemy async connection string
- `CORS_ORIGINS` — Comma-separated; checked on line 26 of `main.py`

**Frontend** (build-time args in `docker-compose.yml` frontend service):
- `VITE_KEYCLOAK_URL` — Public URL from browser (use `http://localhost:8080` for local dev)
- `VITE_KEYCLOAK_REALM` — Must match realm name (`app-realm`)
- `VITE_KEYCLOAK_CLIENT_ID` — Must match client in Keycloak admin console
- `VITE_API_URL` — Public API URL from browser (use `http://localhost:3030` for local dev)

**To debug:** `docker compose logs backend | grep "keycloak_url"` or inspect running container: `docker exec kc_backend env | grep KEYCLOAK`

## Testing Helpers

### Curl examples
```bash
# Health check (no auth)
curl http://localhost:3030/health

# Get user profile (requires valid token from Keycloak)
curl -H "Authorization: Bearer $TOKEN" http://localhost:3030/api/me

# List users (admin only)
curl -H "Authorization: Bearer $ADMIN_TOKEN" http://localhost:3030/api/admin/users
```

### Default Test Credentials
- **Admin user:** `admin@example.com` / `admin` (has `admin` role)
- **Keycloak admin:** `admin` / `admin` (for console at `http://localhost:8080`)

## Known Limitations & Gotchas

1. **No token refresh** — Access token lifetime is 5 minutes; expired tokens cause 401 until user re-logs in
2. **JWKS cache is global** — Keycloak key rotation requires backend restart (`docker compose restart backend`)
3. **User auto-registration** — Any valid Keycloak user can access the app; disable access only via admin toggle in UI, not Keycloak
4. **No API client credentials flow** — Backend is stateless; only user tokens accepted (no service-to-service auth)
5. **Realm export is pre-baked** — Changes made in Keycloak admin console don't persist after `docker compose down -v`; export and update `realm-export.json` to save config

