from typing import Literal
from pydantic import model_validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_env: Literal["local", "dev", "prod"] = "local"

    # Keycloak
    keycloak_url: str = "http://keycloak:8080"
    keycloak_realm: str = "app-realm"
    keycloak_client_id: str = "backend-client"
    keycloak_client_secret: str = "backend-secret-key"
    cors_origins: str = "http://localhost:3000"

    # Database — full URL takes priority; otherwise assembled from parts (dev/prod)
    database_url: str = ""
    db_host: str = ""
    db_port: int = 5432
    db_user: str = "keycloakapp"
    db_password: str = ""
    db_name: str = "keycloakapp"

    # DynamoDB
    aws_region: str = "us-east-1"
    dynamodb_endpoint_url: str = ""  # http://dynamodb-local:8000 for local
    dynamodb_sessions_table: str = "keycloak-app-local-sessions"

    # Redis cache
    redis_url: str = "redis://redis:6379/0"  # rediss:// with TLS in dev/prod

    @model_validator(mode="after")
    def assemble_database_url(self) -> "Settings":
        if self.app_env == "local":
            self.database_url = "sqlite+aiosqlite:///./local.db"
        elif not self.database_url and self.db_host:
            self.database_url = (
                f"postgresql+asyncpg://{self.db_user}:{self.db_password}"
                f"@{self.db_host}:{self.db_port}/{self.db_name}"
            )
        return self

    class Config:
        env_file = ".env"


settings = Settings()
