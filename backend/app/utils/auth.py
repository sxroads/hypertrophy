"""
Authentication utilities: JWT token validation and user extraction.
"""

from typing import Optional
from uuid import UUID
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.utils.jwt import decode_access_token

security = HTTPBearer()
security_optional = HTTPBearer(auto_error=False)


def get_current_user_id(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db),
) -> UUID:
    """
    Extract and validate user_id from JWT token.

    This is a FastAPI dependency that can be used in route handlers.

    Args:
        credentials: HTTP Bearer token from Authorization header
        db: Database session

    Returns:
        user_id (UUID) from token

    Raises:
        HTTPException: If token is invalid or missing
    """
    token = credentials.credentials
    user_id = decode_access_token(token)

    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user_id


def get_optional_user_id(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security_optional),
    db: Session = Depends(get_db),
) -> Optional[UUID]:
    """
    Extract user_id from JWT token if present, otherwise return None.

    Useful for endpoints that support both authenticated and anonymous access.

    Args:
        credentials: HTTP Bearer token from Authorization header (optional)
        db: Database session

    Returns:
        user_id (UUID) if token is valid, None otherwise
    """
    if credentials is None:
        return None

    token = credentials.credentials
    return decode_access_token(token)
