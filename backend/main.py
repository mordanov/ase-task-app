from contextlib import asynccontextmanager
from datetime import datetime
from typing import Optional

from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from config import settings
from database import init_db, get_db, UserAccess
from auth import get_current_user, require_role
import session_store


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    await session_store.init_table()
    yield


app = FastAPI(title="Keycloak Auth App", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins.split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Pydantic schemas ──────────────────────────────────────────────────────────

class UserProfile(BaseModel):
    keycloak_id: str
    email: str
    first_name: Optional[str]
    last_name: Optional[str]
    nickname: Optional[str]
    roles: list[str]
    is_active: bool
    last_login: Optional[datetime]


class UserAccessRecord(BaseModel):
    keycloak_id: str
    email: str
    first_name: Optional[str]
    last_name: Optional[str]
    is_active: bool


class ToggleActiveRequest(BaseModel):
    is_active: bool


# ── Helpers ───────────────────────────────────────────────────────────────────

def extract_profile(token_data: dict) -> dict:
    return {
        "keycloak_id": token_data.get("sub", ""),
        "email": token_data.get("email", ""),
        "first_name": token_data.get("given_name"),
        "last_name": token_data.get("family_name"),
        "nickname": token_data.get("preferred_username"),
        "roles": token_data.get("realm_access", {}).get("roles", []),
    }


async def upsert_user(db: AsyncSession, token_data: dict) -> UserAccess:
    """Create or update user access record on first login."""
    profile = extract_profile(token_data)
    result = await db.execute(
        select(UserAccess).where(UserAccess.keycloak_id == profile["keycloak_id"])
    )
    user = result.scalar_one_or_none()

    now = datetime.utcnow()
    if user is None:
        user = UserAccess(
            keycloak_id=profile["keycloak_id"],
            email=profile["email"],
            first_name=profile["first_name"],
            last_name=profile["last_name"],
            is_active=True,
            last_login=now,
        )
        db.add(user)
    else:
        user.email = profile["email"]
        user.first_name = profile["first_name"]
        user.last_name = profile["last_name"]
        user.last_login = now

    await db.commit()
    await db.refresh(user)
    return user


# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/api/me", response_model=UserProfile)
async def get_me(
    token_data: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Returns the authenticated user's profile. Also registers them on first call."""
    user = await upsert_user(db, token_data)

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your account has been disabled by an administrator.",
        )

    profile = extract_profile(token_data)
    await session_store.upsert_session(
        keycloak_id=profile["keycloak_id"],
        email=profile["email"],
        first_name=profile["first_name"],
        last_name=profile["last_name"],
    )
    return UserProfile(**profile, is_active=user.is_active, last_login=user.last_login)


@app.get("/api/admin/users", response_model=list[UserAccessRecord])
async def list_users(
    token_data: dict = Depends(require_role("admin")),
    db: AsyncSession = Depends(get_db),
):
    """Admin only: list all users who have logged in at least once."""
    result = await db.execute(select(UserAccess).order_by(UserAccess.email))
    users = result.scalars().all()
    return [
        UserAccessRecord(
            keycloak_id=u.keycloak_id,
            email=u.email,
            first_name=u.first_name,
            last_name=u.last_name,
            is_active=u.is_active,
        )
        for u in users
    ]


@app.patch("/api/admin/users/{keycloak_id}/toggle", response_model=UserAccessRecord)
async def toggle_user_access(
    keycloak_id: str,
    body: ToggleActiveRequest,
    token_data: dict = Depends(require_role("admin")),
    db: AsyncSession = Depends(get_db),
):
    """Admin only: enable or disable a user's access."""
    if keycloak_id == token_data.get("sub"):
        raise HTTPException(status_code=400, detail="Cannot disable your own account.")

    result = await db.execute(
        select(UserAccess).where(UserAccess.keycloak_id == keycloak_id)
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")

    user.is_active = body.is_active
    await db.commit()
    await db.refresh(user)

    return UserAccessRecord(
        keycloak_id=user.keycloak_id,
        email=user.email,
        first_name=user.first_name,
        last_name=user.last_name,
        is_active=user.is_active,
    )
