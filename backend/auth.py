from __future__ import annotations

import httpx
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError
from typing import Optional
from config import settings

bearer_scheme = HTTPBearer(auto_error=False)

_jwks_cache: Optional[dict] = None


async def get_jwks() -> dict:
    global _jwks_cache
    if _jwks_cache:
        return _jwks_cache
    url = f"{settings.keycloak_url}/realms/{settings.keycloak_realm}/protocol/openid-connect/certs"
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(url, timeout=10)
            resp.raise_for_status()
            _jwks_cache = resp.json()
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Unable to reach Keycloak JWKS endpoint: {exc}",
        )
    return _jwks_cache


def clear_jwks_cache():
    global _jwks_cache
    _jwks_cache = None


async def decode_token(token: str) -> dict:
    try:
        jwks = await get_jwks()
        header = jwt.get_unverified_header(token)
        key = next(
            (k for k in jwks["keys"] if k.get("kid") == header.get("kid")),
            None,
        )
        if key is None:
            clear_jwks_cache()
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid signing key")

        payload = jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            audience="account",
            options={"verify_aud": False},
        )
        return payload
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Token validation failed: {exc}",
        )


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> dict:
    if credentials is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="No token provided")
    return await decode_token(credentials.credentials)


def require_role(*roles: str):
    async def _checker(user: dict = Depends(get_current_user)) -> dict:
        realm_roles: list[str] = user.get("realm_access", {}).get("roles", [])
        if not any(r in realm_roles for r in roles):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Required role(s): {', '.join(roles)}",
            )
        return user
    return _checker
