"""
JWT token utilities for authentication.

Handles encoding and decoding JWT tokens with user_id payload.
"""

from datetime import datetime, timedelta
from typing import Optional
from uuid import UUID
from jose import JWTError, jwt
from pydantic_settings import BaseSettings


class JWTSettings(BaseSettings):
    """JWT configuration settings."""

    secret_key: str = "your-secret-key-change-in-production"  # Should be in env
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7  # 7 days

    class Config:
        env_file = ".env"


jwt_settings = JWTSettings()


def create_access_token(user_id: UUID) -> str:
    """
    Create a JWT access token for a user.

    Args:
        user_id: The user's UUID

    Returns:
        Encoded JWT token string
    """
    expire = datetime.utcnow() + timedelta(
        minutes=jwt_settings.access_token_expire_minutes
    )
    payload = {
        "sub": str(user_id),  # "sub" (subject) is standard JWT claim
        "exp": expire,
        "iat": datetime.utcnow(),
    }
    return jwt.encode(
        payload, jwt_settings.secret_key, algorithm=jwt_settings.algorithm
    )


def decode_access_token(token: str) -> Optional[UUID]:
    """
    Decode and validate a JWT access token.

    Args:
        token: JWT token string

    Returns:
        user_id (UUID) if token is valid, None otherwise
    """
    try:
        payload = jwt.decode(
            token, jwt_settings.secret_key, algorithms=[jwt_settings.algorithm]
        )
        user_id_str: str = payload.get("sub")
        if user_id_str is None:
            return None
        return UUID(user_id_str)
    except (JWTError, ValueError):
        return None
