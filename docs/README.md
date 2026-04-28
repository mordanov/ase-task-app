# Keycloak Auth Application — Documentation

## Table of contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Prerequisites](#3-prerequisites)
4. [Project structure](#4-project-structure)
5. [Installation guide](#5-installation-guide)
6. [Deployment guide](#6-deployment-guide)
7. [First login](#7-first-login)
8. [User management](#8-user-management)
9. [Adding Google / Microsoft / GitHub login](#9-adding-google--microsoft--github-login)
10. [Configuration reference](#10-configuration-reference)
11. [API reference](#11-api-reference)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Overview

This application provides a fully working authentication and authorisation platform built on:

| Layer | Technology |
|---|---|
| Identity provider | Keycloak 24 |
| Database | PostgreSQL 16 |
| Backend API | Python 3.12, FastAPI |
| Frontend | React 18, Vite |
| Orchestration | Docker Compose |

Users can register and sign in via:
- **Email + password** (managed by Keycloak)
- **Google OAuth 2.0** (configured in Keycloak admin console)
- **Microsoft Entra ID / Azure AD** (configured in Keycloak admin console)
- **GitHub OAuth** (configured in Keycloak admin console)

Two roles exist: `user` (default for all registrants) and `admin`. The admin panel shows all users who have ever logged in, and lets the admin enable or disable their access independently of Keycloak.

---

## 2. Architecture

```
Browser
  │
  ├─► Frontend (React, port 3000)
  │     └─ Keycloak JS adapter handles OIDC redirect/callback
  │
  ├─► Keycloak (port 8080)
  │     ├─ Realm: app-realm
  │     ├─ Clients: frontend-client (public), backend-client (confidential)
  │     ├─ Roles: user, admin
  │     ├─ Identity providers: Google, Microsoft, GitHub (optional, configured post-deploy)
  │     └─ Database: PostgreSQL
  │
  └─► Backend API (FastAPI, port 8000)
        ├─ Verifies JWT tokens from Keycloak (JWKS endpoint)
        ├─ Upserts users into local PostgreSQL table on first login
        └─ Admin endpoints protected by role check
```

**Token flow:**
1. User clicks Sign in → frontend redirects to Keycloak login page
2. User authenticates (email/password, Google, Microsoft, or GitHub)
3. Keycloak issues a signed JWT (access token) and redirects back to frontend
4. Frontend stores the token in memory (via Keycloak JS adapter)
5. Frontend sends `Authorization: Bearer <token>` with every API request
6. Backend validates the JWT signature against Keycloak's public keys (JWKS)
7. Backend extracts roles from the token and enforces access control

---

## 3. Prerequisites

You need the following installed on your machine:

- **Docker** ≥ 24.0 — [install](https://docs.docker.com/get-docker/)
- **Docker Compose** ≥ 2.20 — included with Docker Desktop; on Linux install separately
- **Git** (optional, to clone the project)

No local Python or Node.js installation is required — everything runs inside containers.

Verify your installation:

```bash
docker --version
docker compose version
```

---

## 4. Project structure

```
keycloak-app/
├── docker-compose.yml          # Orchestrates all four services
├── keycloak/
│   └── realm-export.json       # Pre-configured Keycloak realm (auto-imported)
├── backend/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py                 # FastAPI application, all API routes
│   ├── auth.py                 # JWT verification, role guards
│   ├── database.py             # SQLAlchemy models, DB session
│   └── config.py               # Environment-based settings
├── frontend/
│   ├── Dockerfile
│   ├── package.json
│   ├── vite.config.js
│   ├── index.html
│   └── src/
│       ├── main.jsx            # ReactKeycloakProvider initialisation
│       ├── App.jsx             # Router
│       ├── api.js              # Axios API client
│       ├── hooks/
│       │   └── useAuth.js      # Auth helpers (login, logout, hasRole)
│       ├── components/
│       │   ├── Navbar.jsx
│       │   └── ProtectedRoute.jsx
│       └── pages/
│           ├── Home.jsx        # Public landing page
│           ├── Profile.jsx     # Authenticated user profile
│           └── Admin.jsx       # Admin: user management table
└── docs/
    └── README.md               # This file
```

---

## 5. Installation guide

### Step 1 — Clone or unzip the project

```bash
unzip keycloak-app.zip
cd keycloak-app
```

### Step 2 — (Optional) Review environment variables

The defaults work out of the box for local deployment. If you want to change passwords or ports, edit `docker-compose.yml`. Key variables:

| Variable | Default | Where |
|---|---|---|
| `POSTGRES_PASSWORD` | `keycloak_secret` | `postgres` service |
| `KEYCLOAK_ADMIN_PASSWORD` | `admin` | `keycloak` service |
| `KC_DB_PASSWORD` | `keycloak_secret` | `keycloak` service |
| `KEYCLOAK_CLIENT_SECRET` | `backend-secret-key` | `backend` service |

If you change `KEYCLOAK_CLIENT_SECRET`, also update the matching value in `keycloak/realm-export.json` under the `backend-client` entry before first run.

### Step 3 — Pull images and build containers

```bash
docker compose build
```

This builds the Python backend image and the React frontend image. The Keycloak and PostgreSQL images are pulled from Docker Hub automatically.

---

## 6. Deployment guide

### Local deployment

```bash
docker compose up -d
```

Docker Compose starts four containers in the correct order:

1. `kc_postgres` — PostgreSQL starts first
2. `keycloak` — waits for Postgres to be healthy, then imports the realm
3. `kc_backend` — waits for Keycloak to be healthy, then starts FastAPI
4. `kc_frontend` — starts after backend

**Keycloak takes 60–90 seconds to start on first run** while it initialises the database and imports the realm. You can watch progress with:

```bash
docker compose logs -f keycloak
```

When you see `Keycloak 24.0.3 on JVM (powered by Quarkus) started`, all services are ready.

### Verify everything is running

```bash
docker compose ps
```

All four services should show `Up` (or `healthy` for postgres and keycloak).

| Service | URL |
|---|---|
| Frontend | http://localhost:3000 |
| Keycloak admin console | http://localhost:8080 |
| Backend API | http://localhost:8000 |
| Backend health check | http://localhost:8000/health |
| Backend API docs (Swagger) | http://localhost:8000/docs |

### Stopping the application

```bash
# Stop without removing data
docker compose stop

# Stop and remove containers (keeps Postgres volume)
docker compose down

# Full reset — removes all data including the database
docker compose down -v
```

---

## 7. First login

### As admin

1. Open http://localhost:3000
2. Click **Sign in**
3. You are redirected to the Keycloak login page
4. Enter credentials: `admin@example.com` / `admin`
5. You are redirected back to the app and land on the home page
6. Click **User Management** in the navbar — you will see the admin panel

### Keycloak admin console

To manage Keycloak directly:

1. Open http://localhost:8080
2. Click **Administration Console**
3. Login: `admin` / `admin`

From here you can manage users, roles, sessions, identity providers, and realm settings.

### Registering a new user

1. Open http://localhost:3000
2. Click **Register**
3. Fill in the registration form (first name, last name, email, password)
4. The new user is assigned the `user` role by default
5. After registering and logging in, the user sees their profile page with the "You are authorised" badge
6. The admin can see this user in the User Management panel immediately after their first login

---

## 8. User management

### What the admin can do

The admin panel (http://localhost:3000/admin) shows every user who has logged in at least once. For each user the admin can:

- **Disable access** — the user's Keycloak account remains active, but the backend will reject their requests with `403 Forbidden`. This lets you block access without touching Keycloak.
- **Re-enable access** — restores API access immediately.

The admin cannot disable their own account.

### Promoting a user to admin

This is done in the Keycloak admin console:

1. Go to http://localhost:8080 → Administration Console
2. Select realm **app-realm**
3. Go to **Users** → find the user → **Role mappings**
4. Under **Realm roles**, assign the `admin` role
5. The user must log out and log back in for the new role to take effect in their token

### Removing admin role

Same process — go to Role mappings and remove the `admin` role.

---

## 9. Adding Google / Microsoft / GitHub login

These are configured in the Keycloak admin console after deployment. No code changes are required.

### Google OAuth 2.0

**Step 1 — Create Google OAuth credentials:**
1. Go to https://console.cloud.google.com
2. Create a new project (or select an existing one)
3. Go to **APIs & Services → Credentials → Create Credentials → OAuth 2.0 Client ID**
4. Application type: **Web application**
5. Authorised redirect URI: `http://localhost:8080/realms/app-realm/broker/google/endpoint`
6. Save and note the **Client ID** and **Client Secret**

**Step 2 — Add Google to Keycloak:**
1. Keycloak admin console → **app-realm** → **Identity Providers**
2. Click **Add provider → Google**
3. Enter the Client ID and Client Secret from Step 1
4. Set **First Login Flow** to `first broker login`
5. Click **Save**

Google login now appears on the Keycloak login page automatically.

### Microsoft Entra ID (Azure AD)

**Step 1 — Register an app in Azure:**
1. Go to https://portal.azure.com → **Azure Active Directory → App registrations → New registration**
2. Name: anything (e.g. `keycloak-auth-app`)
3. Redirect URI (Web): `http://localhost:8080/realms/app-realm/broker/microsoft/endpoint`
4. After creation, go to **Certificates & secrets → New client secret** — copy the value
5. Note the **Application (client) ID** and your **Directory (tenant) ID**

**Step 2 — Add Microsoft to Keycloak:**
1. Keycloak admin console → **app-realm** → **Identity Providers**
2. Click **Add provider → Microsoft**
3. Enter the Client ID and Client Secret
4. Click **Save**

Microsoft login now appears on the Keycloak login page.

### GitHub OAuth

**Step 1 — Create a GitHub OAuth App:**
1. Go to https://github.com/settings/developers → **OAuth Apps → New OAuth App**
2. Application name: anything (e.g. `keycloak-auth-app`)
3. Homepage URL: `http://localhost:3001`
4. Authorization callback URL: `http://localhost:8080/realms/app-realm/broker/github/endpoint`
5. Click **Register application**
6. On the app page click **Generate a new client secret**
7. Note the **Client ID** and the generated **Client secret**

**Step 2 — Add credentials to `.env`:**
```
GITHUB_CLIENT_ID=<your client id>
GITHUB_CLIENT_SECRET=<your client secret>
```

**Step 3 — Restart Keycloak to pick up the new values:**
```bash
docker compose down -v
docker compose up -d
```

> **Note:** GitHub does not guarantee that email addresses are verified or even public. Users who hide their email on GitHub will land on a "missing email" screen in Keycloak. To work around this, enable the **GitHub** scope `user:email` — Keycloak's built-in GitHub provider requests it by default.

GitHub login now appears on the Keycloak login page automatically.

### Account linking

If a user registers with email/password and later signs in with Google or GitHub using the same email address, Keycloak will detect the match and prompt them to link the accounts. This is controlled by the **First Login Flow** setting on each identity provider.

---

## 10. Configuration reference

### docker-compose.yml environment variables

#### postgres

| Variable | Description |
|---|---|
| `POSTGRES_DB` | Database name |
| `POSTGRES_USER` | Database user |
| `POSTGRES_PASSWORD` | Database password |

#### keycloak

| Variable | Description |
|---|---|
| `KC_DB_URL` | JDBC connection string for PostgreSQL |
| `KEYCLOAK_ADMIN` | Admin username for Keycloak console |
| `KEYCLOAK_ADMIN_PASSWORD` | Admin password for Keycloak console |
| `KC_HTTP_PORT` | Port Keycloak listens on (default 8080) |

#### backend

| Variable | Description |
|---|---|
| `KEYCLOAK_URL` | Internal URL of Keycloak (container-to-container) |
| `KEYCLOAK_REALM` | Realm name (must match realm-export.json) |
| `KEYCLOAK_CLIENT_ID` | Backend service client ID |
| `KEYCLOAK_CLIENT_SECRET` | Backend service client secret |
| `DATABASE_URL` | SQLAlchemy async connection string |
| `CORS_ORIGINS` | Comma-separated list of allowed frontend origins |

#### frontend

| Variable | Description |
|---|---|
| `VITE_KEYCLOAK_URL` | Public Keycloak URL (accessed from the browser) |
| `VITE_KEYCLOAK_REALM` | Realm name |
| `VITE_KEYCLOAK_CLIENT_ID` | Frontend public client ID |
| `VITE_API_URL` | Public backend URL (accessed from the browser) |

### Keycloak realm settings (realm-export.json)

The realm is pre-configured with:
- Self-registration enabled
- Email as username
- Brute-force protection enabled (30 failed attempts locks the account)
- Access token lifetime: 5 minutes
- SSO session idle timeout: 30 minutes
- Default role for new users: `user`

---

## 11. API reference

### Authentication

All protected endpoints require an `Authorization: Bearer <token>` header where the token is the Keycloak access token obtained after login.

### Endpoints

#### `GET /health`

Public. Returns `{"status": "ok"}`.

---

#### `GET /api/me`

**Auth required:** any authenticated user

Returns the current user's profile. Also registers the user in the local database on first call.

**Response:**
```json
{
  "keycloak_id": "uuid",
  "email": "user@example.com",
  "first_name": "Jane",
  "last_name": "Doe",
  "roles": ["user"],
  "is_active": true
}
```

**Error 403:** returned if the user has been disabled by an admin.

---

#### `GET /api/admin/users`

**Auth required:** `admin` role

Returns all users who have logged in at least once.

**Response:** array of user records:
```json
[
  {
    "keycloak_id": "uuid",
    "email": "user@example.com",
    "first_name": "Jane",
    "last_name": "Doe",
    "is_active": true
  }
]
```

---

#### `PATCH /api/admin/users/{keycloak_id}/toggle`

**Auth required:** `admin` role

Enable or disable a user's access.

**Request body:**
```json
{ "is_active": false }
```

**Response:** updated user record.

**Error 400:** if the admin attempts to disable their own account.
**Error 404:** if the user is not found.

---

## 12. Troubleshooting

### Keycloak takes a very long time to start

This is normal on first run — Keycloak initialises its database schema and imports the realm. Wait 90 seconds, then check:

```bash
docker compose logs keycloak | tail -20
```

### Frontend shows a blank page or OIDC error

Make sure Keycloak is fully started before opening the frontend. If you opened http://localhost:3000 too early, hard-refresh the page (Ctrl+Shift+R).

### "Invalid redirect_uri" error on Keycloak login page

The frontend URL must match the redirect URIs configured in the `frontend-client` Keycloak client. By default it allows `http://localhost:3000/*`. If you run the frontend on a different port, update the client in the Keycloak admin console:

1. Admin console → **app-realm** → **Clients** → **frontend-client**
2. Add your URL to **Valid redirect URIs** and **Web origins**

### Backend returns 401 for valid tokens

The JWKS cache may be stale. Restart the backend:

```bash
docker compose restart backend
```

### "Cannot connect to database" in backend logs

If the backend starts before Keycloak has finished importing the realm, it may fail to connect on the first health check. Docker Compose will restart it automatically. Wait a minute and check again:

```bash
docker compose logs backend
```

### Resetting everything to a clean state

```bash
docker compose down -v
docker compose up -d
```

This destroys the PostgreSQL volume and reimports the realm from scratch, restoring the default admin user.

### Viewing logs

```bash
docker compose logs -f              # all services
docker compose logs -f keycloak     # Keycloak only
docker compose logs -f backend      # FastAPI only
docker compose logs -f frontend     # Frontend only
```
