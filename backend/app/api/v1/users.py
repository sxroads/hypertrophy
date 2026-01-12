"""
User management endpoints: merge anonymous user data.
"""

from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.models.user import User
from app.services.user_merge_service import UserMergeService
from app.utils.auth import get_current_user_id

router = APIRouter()


class MergeRequest(BaseModel):
    """User merge request."""

    anonymous_user_id: UUID = Field(..., description="Anonymous user ID to merge from")


class AnonymousUserResponse(BaseModel):
    """Anonymous user creation response."""

    user_id: UUID
    is_anonymous: bool = True


class MergeResponse(BaseModel):
    """User merge response."""

    merged: bool
    message: str
    events_updated: int
    workouts_updated: int
    metrics_updated: int
    reports_updated: int


class UserInfoResponse(BaseModel):
    """Current user information response."""

    user_id: UUID
    email: str | None
    is_anonymous: bool
    gender: str | None
    age: int | None


class UserProfileUpdateRequest(BaseModel):
    """Request model for updating user profile."""

    gender: str | None = Field(None, description="Gender: 'male' or 'female'")
    age: int | None = Field(None, ge=1, le=150, description="Age in years")


@router.post(
    "/anonymous",
    response_model=AnonymousUserResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_anonymous_user(
    db: Session = Depends(get_db),
):
    """
    Create an anonymous user for first-time app usage.

    Returns a user_id that can be used for syncing events before the user
    creates an account. This user_id should be stored locally and used
    for the merge endpoint after the user registers/logs in.
    
    Anonymous users allow offline-first functionality - users can start
    tracking workouts immediately without registration, then merge data
    when they create an account.
    """
    # Create anonymous user (no email or password required)
    # These users can sync events but cannot login
    user = User(
        email=None,
        password_hash=None,
        is_anonymous=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    return AnonymousUserResponse(
        user_id=user.user_id,
        is_anonymous=True,
    )


@router.post("/merge", response_model=MergeResponse, status_code=status.HTTP_200_OK)
async def merge_user(
    request: MergeRequest,
    current_user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Merge anonymous user data to real user account.

    This endpoint is idempotent - safe to call multiple times.
    Only the authenticated user can merge their own anonymous data.
    """
    merge_service = UserMergeService(db)

    try:
        result = merge_service.merge_user_data(
            anonymous_user_id=request.anonymous_user_id,
            real_user_id=current_user_id,
        )

        return MergeResponse(**result)

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Merge failed: {str(e)}",
        )


@router.get("/me", response_model=UserInfoResponse, status_code=status.HTTP_200_OK)
async def get_current_user_info(
    current_user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Get current authenticated user information.

    Returns user_id, email, and is_anonymous status for the authenticated user.
    """
    try:
        user = db.query(User).filter(User.user_id == current_user_id).first()

        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found",
            )

        return UserInfoResponse(
            user_id=user.user_id,
            email=user.email,
            is_anonymous=user.is_anonymous,
            gender=getattr(user, "gender", None),
            age=getattr(user, "age", None),
        )
    except Exception as e:
        import traceback

        print(f"[ERROR] get_current_user_info failed: {e}")
        print(traceback.format_exc())
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get user info: {str(e)}. Please ensure database migration 006_add_body_measurements has been run.",
        )


@router.put(
    "/me/profile", response_model=UserInfoResponse, status_code=status.HTTP_200_OK
)
async def update_user_profile(
    request: UserProfileUpdateRequest,
    current_user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Update current user's profile (gender and age).

    Requires authentication.
    """
    try:
        user = db.query(User).filter(User.user_id == current_user_id).first()

        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found",
            )

        # Validate gender if provided
        if request.gender is not None:
            if request.gender not in ["male", "female"]:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Gender must be 'male' or 'female'",
                )
            user.gender = request.gender

        if request.age is not None:
            user.age = request.age

        db.commit()
        db.refresh(user)

        return UserInfoResponse(
            user_id=user.user_id,
            email=user.email,
            is_anonymous=user.is_anonymous,
            gender=getattr(user, "gender", None),
            age=getattr(user, "age", None),
        )
    except HTTPException:
        raise
    except Exception as e:
        import traceback

        print(f"[ERROR] update_user_profile failed: {e}")
        print(traceback.format_exc())
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update profile: {str(e)}. Please ensure database migration 006_add_body_measurements has been run.",
        )
