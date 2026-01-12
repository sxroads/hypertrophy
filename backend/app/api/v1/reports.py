"""
Weekly AI reports endpoints.
"""

from uuid import UUID
from typing import Optional
from datetime import date, datetime
from fastapi import APIRouter, Depends, HTTPException, status, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.models.projections import WeeklyReport
from app.services.ai_report_service import AIReportService, get_week_start
from app.utils.auth import get_optional_user_id

router = APIRouter()


class WeeklyReportResponse(BaseModel):
    """Weekly report response model."""

    id: UUID
    user_id: UUID
    week_start: date
    report_text: str
    generated_at: datetime


@router.get(
    "/reports/weekly",
    response_model=WeeklyReportResponse,
    status_code=status.HTTP_200_OK,
)
async def get_weekly_report(
    user_id: UUID,
    week_start: Optional[date] = Query(None, description="Monday date of the week (defaults to current week)"),
    authenticated_user_id: Optional[UUID] = Depends(get_optional_user_id),
    db: Session = Depends(get_db),
):
    """
    Get or generate weekly AI report for a user.
    
    If report doesn't exist, it will be generated automatically.
    
    Supports both authenticated and anonymous users:
    - If authenticated: user_id must match authenticated user (ownership validation)
    - If anonymous: user_id can be any anonymous user_id
    
    Args:
        user_id: User ID to fetch report for
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

    report_service = AIReportService(db)
    
    # Generate report if it doesn't exist
    report = report_service.generate_weekly_report(user_id, week_start)

    return WeeklyReportResponse(
        id=report.id,
        user_id=report.user_id,
        week_start=report.week_start,
        report_text=report.report_text,
        generated_at=report.generated_at,
    )


@router.post(
    "/reports/weekly/regenerate",
    response_model=WeeklyReportResponse,
    status_code=status.HTTP_200_OK,
)
async def regenerate_weekly_report(
    user_id: UUID,
    week_start: Optional[date] = Query(None, description="Monday date of the week (defaults to current week)"),
    authenticated_user_id: Optional[UUID] = Depends(get_optional_user_id),
    db: Session = Depends(get_db),
):
    """
    Regenerate weekly AI report for a user.
    
    This will delete the existing report and create a new one.
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

    report_service = AIReportService(db)
    
    # Delete existing report if it exists
    existing_report = report_service.get_weekly_report(user_id, week_start)
    if existing_report:
        db.delete(existing_report)
        db.commit()

    # Generate new report
    report = report_service.generate_weekly_report(user_id, week_start)

    return WeeklyReportResponse(
        id=report.id,
        user_id=report.user_id,
        week_start=report.week_start,
        report_text=report.report_text,
        generated_at=report.generated_at,
    )

