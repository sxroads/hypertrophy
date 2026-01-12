"""
Weekly metrics endpoints.
"""

from uuid import UUID
from typing import Optional
from datetime import date, datetime
from fastapi import APIRouter, Depends, HTTPException, status, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.models.projections import WeeklyMetrics
from app.services.metrics_service import MetricsService, get_week_start
from app.utils.auth import get_optional_user_id

router = APIRouter()


class WeeklyMetricsResponse(BaseModel):
    """Weekly metrics response model."""

    id: UUID
    user_id: UUID
    week_start: date
    total_workouts: int
    total_volume: float
    exercises_count: int


@router.get(
    "/metrics/weekly",
    response_model=WeeklyMetricsResponse,
    status_code=status.HTTP_200_OK,
)
async def get_weekly_metrics(
    user_id: UUID,
    week_start: Optional[date] = Query(None, description="Monday date of the week (defaults to current week)"),
    authenticated_user_id: Optional[UUID] = Depends(get_optional_user_id),
    db: Session = Depends(get_db),
):
    """
    Get weekly metrics for a user.
    
    Supports both authenticated and anonymous users:
    - If authenticated: user_id must match authenticated user (ownership validation)
    - If anonymous: user_id can be any anonymous user_id
    
    Args:
        user_id: User ID to fetch metrics for
        week_start: Monday date of the week (defaults to current week)
        authenticated_user_id: Authenticated user ID from JWT (optional)
        db: Database session
    """
    # Ownership validation: if authenticated, user_id must match
    if authenticated_user_id is not None:
        if user_id != authenticated_user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="user_id does not match authenticated user",
            )

    # Default to current week if not provided
    if week_start is None:
        week_start = get_week_start(datetime.now())

    metrics_service = MetricsService(db)
    
    # Calculate metrics if they don't exist
    metrics = metrics_service.calculate_weekly_metrics(user_id, week_start)

    return WeeklyMetricsResponse(
        id=metrics.id,
        user_id=metrics.user_id,
        week_start=metrics.week_start,
        total_workouts=metrics.total_workouts,
        total_volume=metrics.total_volume,
        exercises_count=metrics.exercises_count,
    )


@router.post(
    "/metrics/weekly/rebuild",
    status_code=status.HTTP_200_OK,
)
async def rebuild_weekly_metrics(
    user_id: UUID,
    authenticated_user_id: Optional[UUID] = Depends(get_optional_user_id),
    db: Session = Depends(get_db),
):
    """
    Rebuild all weekly metrics for a user.
    
    This recalculates metrics for all weeks based on current workout data.
    """
    # Ownership validation: if authenticated, user_id must match
    if authenticated_user_id is not None:
        if user_id != authenticated_user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="user_id does not match authenticated user",
            )

    metrics_service = MetricsService(db)
    metrics_service.rebuild_weekly_metrics(user_id)

    return {"message": "Weekly metrics rebuilt successfully"}

