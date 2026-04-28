import asyncio
from datetime import datetime, timedelta

import boto3
from botocore.exceptions import ClientError

from config import settings

SESSION_TTL_HOURS = 24

_client = None


def _get_client():
    global _client
    if _client is None:
        kwargs: dict = {"region_name": settings.aws_region}
        if settings.dynamodb_endpoint_url:
            kwargs["endpoint_url"] = settings.dynamodb_endpoint_url
        _client = boto3.client("dynamodb", **kwargs)
    return _client


async def init_table() -> None:
    """Create the sessions table if it does not exist (idempotent)."""
    client = _get_client()
    try:
        await asyncio.to_thread(
            client.create_table,
            TableName=settings.dynamodb_sessions_table,
            AttributeDefinitions=[
                {"AttributeName": "session_id", "AttributeType": "S"}
            ],
            KeySchema=[
                {"AttributeName": "session_id", "KeyType": "HASH"}
            ],
            BillingMode="PAY_PER_REQUEST",
        )
        await asyncio.to_thread(
            client.update_time_to_live,
            TableName=settings.dynamodb_sessions_table,
            TimeToLiveSpecification={
                "Enabled": True,
                "AttributeName": "expires_at",
            },
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] != "ResourceInUseException":
            raise


async def upsert_session(
    keycloak_id: str,
    email: str,
    first_name: str | None,
    last_name: str | None,
) -> None:
    now = datetime.utcnow()
    expires_at = int((now + timedelta(hours=SESSION_TTL_HOURS)).timestamp())
    item: dict = {
        "session_id": {"S": keycloak_id},
        "email": {"S": email},
        "last_seen": {"S": now.isoformat()},
        "expires_at": {"N": str(expires_at)},
    }
    if first_name:
        item["first_name"] = {"S": first_name}
    if last_name:
        item["last_name"] = {"S": last_name}

    client = _get_client()
    await asyncio.to_thread(
        client.put_item,
        TableName=settings.dynamodb_sessions_table,
        Item=item,
    )


async def get_session(keycloak_id: str) -> dict | None:
    client = _get_client()
    try:
        resp = await asyncio.to_thread(
            client.get_item,
            TableName=settings.dynamodb_sessions_table,
            Key={"session_id": {"S": keycloak_id}},
        )
        return resp.get("Item")
    except ClientError:
        return None


async def delete_session(keycloak_id: str) -> None:
    client = _get_client()
    await asyncio.to_thread(
        client.delete_item,
        TableName=settings.dynamodb_sessions_table,
        Key={"session_id": {"S": keycloak_id}},
    )
