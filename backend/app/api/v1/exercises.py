"""
Exercise endpoints.
"""

from uuid import UUID
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.models.projections import Exercise

router = APIRouter()


class ExerciseResponse(BaseModel):
    """Exercise response model."""

    exercise_id: UUID
    name: str
    muscle_category: str


@router.get(
    "/exercises",
    response_model=List[ExerciseResponse],
    status_code=status.HTTP_200_OK,
)
async def get_exercises(
    muscle_category: Optional[str] = Query(
        None, description="Filter by muscle category"
    ),
    db: Session = Depends(get_db),
):
    """
    Get list of exercises, optionally filtered by muscle category.

    Args:
        muscle_category: Optional filter by muscle category (chest, back, legs, shoulders, arms, core)
        db: Database session
    """
    query = db.query(Exercise)

    if muscle_category:
        query = query.filter(Exercise.muscle_category == muscle_category.lower())

    exercises = query.order_by(Exercise.name).all()

    return [
        ExerciseResponse(
            exercise_id=ex.exercise_id,
            name=ex.name,
            muscle_category=ex.muscle_category,
        )
        for ex in exercises
    ]
