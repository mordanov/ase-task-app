"""
Redis-backed query cache.

Usage:
    # One-off get/set
    value = await cache.get("my-key")
    await cache.set("my-key", value, ttl=300)
    await cache.delete("my-key")
    await cache.delete_pattern("reports:2024-*")

    # Decorator — caches the return value of an async function
    @cache.cached(prefix="user-report", ttl=300)
    async def get_report(user_id: str, date: str) -> dict:
        ...  # expensive DB query
"""

import json
import logging
from collections.abc import Callable
from functools import wraps
from typing import Any

import redis.asyncio as aioredis

from config import settings

logger = logging.getLogger(__name__)

_client: aioredis.Redis | None = None


def get_client() -> aioredis.Redis:
    global _client
    if _client is None:
        _client = aioredis.from_url(
            settings.redis_url,
            encoding="utf-8",
            decode_responses=True,
            # ElastiCache uses self-signed certs in transit — skip verification
            ssl_cert_reqs=None if settings.redis_url.startswith("rediss://") else None,
        )
    return _client


async def get(key: str) -> Any | None:
    try:
        raw = await get_client().get(key)
        return json.loads(raw) if raw is not None else None
    except Exception:
        logger.warning("cache.get failed for key=%s", key, exc_info=True)
        return None


async def set(key: str, value: Any, ttl: int = 300) -> None:
    try:
        await get_client().setex(key, ttl, json.dumps(value, default=str))
    except Exception:
        logger.warning("cache.set failed for key=%s", key, exc_info=True)


async def delete(key: str) -> None:
    try:
        await get_client().delete(key)
    except Exception:
        logger.warning("cache.delete failed for key=%s", key, exc_info=True)


async def delete_pattern(pattern: str) -> int:
    """Delete all keys matching a glob pattern. Returns number of deleted keys."""
    try:
        client = get_client()
        keys = [k async for k in client.scan_iter(pattern)]
        if keys:
            return await client.delete(*keys)
        return 0
    except Exception:
        logger.warning("cache.delete_pattern failed for pattern=%s", pattern, exc_info=True)
        return 0


def cached(prefix: str, ttl: int = 300) -> Callable:
    """
    Decorator that caches the return value of an async function in Redis.

    Cache key: "{prefix}:{arg1}:{arg2}:..."

    Example — cache date-range query results for 5 minutes:
        @cache.cached(prefix="sales-by-date", ttl=300)
        async def get_sales(date_from: str, date_to: str) -> list[dict]:
            return await db.execute(...)
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        async def wrapper(*args, **kwargs) -> Any:
            key_parts = [prefix] + [str(a) for a in args] + [f"{k}={v}" for k, v in sorted(kwargs.items())]
            key = ":".join(key_parts)

            cached_value = await get(key)
            if cached_value is not None:
                return cached_value

            result = await func(*args, **kwargs)
            await set(key, result, ttl=ttl)
            return result
        return wrapper
    return decorator
