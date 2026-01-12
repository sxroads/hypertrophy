"""
Workout history endpoints.
"""

from uuid import UUID
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import and_
from datetime import datetime

from app.db.database import get_db
from app.models.projections import WorkoutProjection, SetProjection, Exercise
from app.utils.auth import get_optional_user_id

router = APIRouter()


class SetResponse(BaseModel):
    """Set response model."""

    set_id: UUID
    workout_id: UUID
    exercise_id: UUID
    reps: Optional[int]
    weight: Optional[float]
    completed_at: datetime


class ExerciseInfo(BaseModel):
    """Exercise information in workout."""

    exercise_id: UUID
    name: str


class WorkoutResponse(BaseModel):
    """Workout response model."""

    workout_id: UUID
    started_at: datetime
    ended_at: Optional[datetime]
    status: str
    sets_count: int = 0
    total_volume: float = 0.0  # Sum of (reps * weight) for all sets
    exercises: List[ExerciseInfo] = []  # List of exercises in this workout


@router.get(
    "/workouts", response_model=List[WorkoutResponse], status_code=status.HTTP_200_OK
)
async def get_workout_history(
    user_id: UUID,
    authenticated_user_id: Optional[UUID] = Depends(get_optional_user_id),
    db: Session = Depends(get_db),
):
    """
    Get workout history for a user.

    Supports both authenticated and anonymous users:
    - If authenticated: user_id must match authenticated user (ownership validation)
    - If anonymous: user_id can be any anonymous user_id

    Args:
        user_id: User ID to fetch workouts for
        authenticated_user_id: Authenticated user ID from JWT (optional)
        db: Database session
        include_sets: Whether to include sets in response (default: False)
    """
    # Ownership validation: if authenticated, user_id must match
    if authenticated_user_id is not None:
        if user_id != authenticated_user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="user_id does not match authenticated user",
            )

    # Query workouts for user
    workouts = (
        db.query(WorkoutProjection)
        .filter(WorkoutProjection.user_id == user_id)
        .order_by(WorkoutProjection.started_at.desc())
        .all()
    )

    # Get all sets for all workouts in one query (batch operation - fixes N+1)
    # Instead of querying sets per workout (N queries), we fetch all sets at once
    workout_ids = [w.workout_id for w in workouts]
    all_sets = (
        db.query(SetProjection).filter(SetProjection.workout_id.in_(workout_ids)).all()
    )

    # Group sets by workout_id for efficient lookup
    # Builds a dictionary mapping workout_id -> list of sets
    sets_by_workout = {}
    for s in all_sets:
        if s.workout_id not in sets_by_workout:
            sets_by_workout[s.workout_id] = []
        sets_by_workout[s.workout_id].append(s)

    # Get all unique exercise IDs from all sets
    # Used to batch fetch exercise names in a single query
    exercise_ids = list(set(s.exercise_id for s in all_sets))

    # Get exercise names in batch (fixes potential N+1 for exercise lookups)
    # Maps exercise_id -> exercise name for quick lookup when building response
    exercise_map = {}
    if exercise_ids:
        exercises = (
            db.query(Exercise).filter(Exercise.exercise_id.in_(exercise_ids)).all()
        )
        exercise_map = {ex.exercise_id: ex.name for ex in exercises}

    # Build response with set statistics and exercises
    workout_responses = []
    for workout in workouts:
        sets = sets_by_workout.get(workout.workout_id, [])

        # Calculate total volume (reps * weight)
        total_volume = sum((s.reps or 0) * (s.weight or 0) for s in sets)

        # Get unique exercises for this workout
        workout_exercise_ids = list(set(s.exercise_id for s in sets))
        exercises = [
            ExerciseInfo(
                exercise_id=ex_id,
                name=exercise_map.get(ex_id, "Unknown Exercise"),
            )
            for ex_id in workout_exercise_ids
        ]

        workout_responses.append(
            WorkoutResponse(
                workout_id=workout.workout_id,
                started_at=workout.started_at,
                ended_at=workout.ended_at,
                status=workout.status,
                sets_count=len(sets),
                total_volume=total_volume,
                exercises=exercises,
            )
        )

    return workout_responses


@router.get(
    "/workouts/{workout_id}/sets",
    response_model=List[SetResponse],
    status_code=status.HTTP_200_OK,
)
async def get_workout_sets(
    workout_id: UUID,
    authenticated_user_id: Optional[UUID] = Depends(get_optional_user_id),
    db: Session = Depends(get_db),
):
    """
    Get sets for a specific workout.

    Args:
        workout_id: Workout ID to fetch sets for
        authenticated_user_id: Authenticated user ID from JWT (optional)
        db: Database session
    """
    # Get workout to verify ownership
    workout = (
        db.query(WorkoutProjection)
        .filter(WorkoutProjection.workout_id == workout_id)
        .first()
    )

    if not workout:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Workout not found",
        )

    # Ownership validation: if authenticated, user_id must match
    if authenticated_user_id is not None:
        if workout.user_id != authenticated_user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Workout does not belong to authenticated user",
            )

    # Get sets for workout
    sets = (
        db.query(SetProjection)
        .filter(SetProjection.workout_id == workout_id)
        .order_by(SetProjection.completed_at)
        .all()
    )

    return [
        SetResponse(
            set_id=s.set_id,
            workout_id=s.workout_id,
            exercise_id=s.exercise_id,
            reps=s.reps,
            weight=s.weight,
            completed_at=s.completed_at,
        )
        for s in sets
    ]


@router.get(
    "/workouts/sets/batch",
    response_model=List[SetResponse],
    status_code=status.HTTP_200_OK,
)
async def get_workout_sets_batch(
    workout_ids: List[UUID] = Query(..., description="List of workout IDs"),
    user_id: UUID = Query(..., description="User ID for ownership validation"),
    authenticated_user_id: Optional[UUID] = Depends(get_optional_user_id),
    db: Session = Depends(get_db),
):
    """
    Get sets for multiple workouts in a single query (fixes N+1).
    
    This endpoint solves the N+1 problem where fetching sets for N workouts
    would require N+1 queries (1 for workouts + N for sets). Instead, we use
    a single batch query with IN clause to fetch all sets at once.
    
    Performance: O(1) queries instead of O(N) queries
    Critical for: Records page, workout history with many workouts

    Args:
        workout_ids: List of workout IDs to fetch sets for
        user_id: User ID for ownership validation
        authenticated_user_id: Authenticated user ID from JWT (optional)
        db: Database session
    """
    if not workout_ids:
        return []

    # Ownership validation: if authenticated, user_id must match
    # Prevents users from accessing other users' workout data
    if authenticated_user_id is not None:
        if user_id != authenticated_user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="user_id does not match authenticated user",
            )

    # Verify all workouts belong to the user (batch check)
    # Ensures no unauthorized access even if some workout_ids are valid
    workouts = (
        db.query(WorkoutProjection)
        .filter(
            and_(
                WorkoutProjection.workout_id.in_(workout_ids),
                WorkoutProjection.user_id == user_id,
            )
        )
        .all()
    )

    # Security check: all requested workouts must belong to the user
    if len(workouts) != len(workout_ids):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="One or more workouts do not belong to the user",
        )

    # Get all sets for all workouts in one query (batch operation - fixes N+1)
    # Uses IN clause to fetch sets for multiple workouts simultaneously
    sets = (
        db.query(SetProjection)
        .filter(SetProjection.workout_id.in_(workout_ids))
        .order_by(SetProjection.completed_at)
        .all()
    )

    return [
        SetResponse(
            set_id=s.set_id,
            workout_id=s.workout_id,
            exercise_id=s.exercise_id,
            reps=s.reps,
            weight=s.weight,
            completed_at=s.completed_at,
        )
        for s in sets
    ]


@router.get(
    "/exercises/{exercise_id}/last-sets",
    response_model=List[SetResponse],
    status_code=status.HTTP_200_OK,
)
async def get_last_sets_for_exercise(
    exercise_id: UUID,
    user_id: UUID,
    authenticated_user_id: Optional[UUID] = Depends(get_optional_user_id),
    db: Session = Depends(get_db),
):
    """
    Get all sets from the last workout for a specific exercise for a user.

    Supports both authenticated and anonymous users:
    - If authenticated: user_id must match authenticated user (ownership validation)
    - If anonymous: user_id can be any anonymous user_id

    Args:
        exercise_id: Exercise ID to fetch last sets for
        user_id: User ID to fetch sets for
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

    # Find the most recent workout that contains this exercise
    last_workout = (
        db.query(WorkoutProjection)
        .join(
            SetProjection,
            WorkoutProjection.workout_id == SetProjection.workout_id,
        )
        .filter(
            and_(
                SetProjection.exercise_id == exercise_id,
                WorkoutProjection.user_id == user_id,
            )
        )
        .order_by(WorkoutProjection.started_at.desc())
        .first()
    )

    if not last_workout:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No previous workout found for this exercise",
        )

    # Get all sets for this exercise from that workout
    sets = (
        db.query(SetProjection)
        .filter(
            and_(
                SetProjection.workout_id == last_workout.workout_id,
                SetProjection.exercise_id == exercise_id,
            )
        )
        .order_by(SetProjection.completed_at.asc())
        .all()
    )

    return [
        SetResponse(
            set_id=s.set_id,
            workout_id=s.workout_id,
            exercise_id=s.exercise_id,
            reps=s.reps,
            weight=s.weight,
            completed_at=s.completed_at,
        )
        for s in sets
    ]
