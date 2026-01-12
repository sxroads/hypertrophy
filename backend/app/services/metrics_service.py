"""
Weekly metrics service.

Aggregates workout data into weekly summaries.
"""

from uuid import UUID
from datetime import date, datetime, timedelta
from typing import Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from app.models.projections import WorkoutProjection, SetProjection, WeeklyMetrics


def get_week_start(dt: datetime) -> date:
    """Get the Monday of the week for a given date."""
    # Get Monday of the week (weekday() returns 0=Monday, 6=Sunday)
    days_since_monday = dt.weekday()
    monday = dt.date() - timedelta(days=days_since_monday)
    return monday


class MetricsService:
    """Service for calculating and storing weekly metrics."""

    def __init__(self, db: Session):
        self.db = db

    def calculate_weekly_metrics(
        self, user_id: UUID, week_start: date
    ) -> WeeklyMetrics:
        """
        Calculate weekly metrics for a user and week.
        
        Args:
            user_id: User ID
            week_start: Monday date of the week
            
        Returns:
            WeeklyMetrics object (created or updated)
        """
        week_end = week_start + timedelta(days=6)
        
        # Get all completed workouts for this week
        workouts = (
            self.db.query(WorkoutProjection)
            .filter(
                and_(
                    WorkoutProjection.user_id == user_id,
                    WorkoutProjection.status == "completed",
                    func.date(WorkoutProjection.started_at) >= week_start,
                    func.date(WorkoutProjection.started_at) <= week_end,
                )
            )
            .all()
        )

        # Calculate metrics
        total_workouts = len(workouts)
        total_volume = 0.0
        unique_exercises = set()

        # Get all sets for all workouts in one query (fixes N+1 query problem)
        # Instead of querying sets per workout in a loop (N queries), we batch fetch all sets
        # This is critical for performance when a week has many workouts (5-20+)
        workout_ids = [w.workout_id for w in workouts]
        all_sets = (
            self.db.query(SetProjection)
            .filter(SetProjection.workout_id.in_(workout_ids))
            .all()
        ) if workout_ids else []

        # Calculate volume for all workouts
        # Volume = sum of (reps * weight) for all sets across all workouts in the week
        for s in all_sets:
            volume = (s.reps or 0) * (s.weight or 0)
            total_volume += volume
            unique_exercises.add(s.exercise_id)

        exercises_count = len(unique_exercises)

        # Find or create weekly metrics
        metrics = (
            self.db.query(WeeklyMetrics)
            .filter(
                and_(
                    WeeklyMetrics.user_id == user_id,
                    WeeklyMetrics.week_start == week_start,
                )
            )
            .first()
        )

        if metrics:
            # Update existing metrics
            metrics.total_workouts = total_workouts
            metrics.total_volume = total_volume
            metrics.exercises_count = exercises_count
        else:
            # Create new metrics
            metrics = WeeklyMetrics(
                user_id=user_id,
                week_start=week_start,
                total_workouts=total_workouts,
                total_volume=total_volume,
                exercises_count=exercises_count,
            )
            self.db.add(metrics)

        self.db.commit()
        return metrics

    def rebuild_weekly_metrics(self, user_id: UUID) -> None:
        """
        Rebuild all weekly metrics for a user.
        
        This scans all workouts and recalculates metrics for each week.
        """
        # Get all completed workouts for the user
        workouts = (
            self.db.query(WorkoutProjection)
            .filter(
                and_(
                    WorkoutProjection.user_id == user_id,
                    WorkoutProjection.status == "completed",
                )
            )
            .order_by(WorkoutProjection.started_at)
            .all()
        )

        # Group workouts by week
        weeks_data = {}
        for workout in workouts:
            week_start = get_week_start(workout.started_at)
            if week_start not in weeks_data:
                weeks_data[week_start] = []
            weeks_data[week_start].append(workout)

        # Calculate metrics for each week
        # Process each week independently to build separate weekly metrics records
        for week_start, week_workouts in weeks_data.items():
            # Get all sets for workouts in this week (batch query - no N+1)
            # Groups sets by week to calculate per-week aggregates
            workout_ids = [w.workout_id for w in week_workouts]
            sets = (
                self.db.query(SetProjection)
                .filter(SetProjection.workout_id.in_(workout_ids))
                .all()
            )

            # Calculate aggregates: total volume and unique exercise count
            total_volume = sum((s.reps or 0) * (s.weight or 0) for s in sets)
            unique_exercises = set(s.exercise_id for s in sets)

            # Find or create metrics
            metrics = (
                self.db.query(WeeklyMetrics)
                .filter(
                    and_(
                        WeeklyMetrics.user_id == user_id,
                        WeeklyMetrics.week_start == week_start,
                    )
                )
                .first()
            )

            if metrics:
                metrics.total_workouts = len(week_workouts)
                metrics.total_volume = total_volume
                metrics.exercises_count = len(unique_exercises)
            else:
                metrics = WeeklyMetrics(
                    user_id=user_id,
                    week_start=week_start,
                    total_workouts=len(week_workouts),
                    total_volume=total_volume,
                    exercises_count=len(unique_exercises),
                )
                self.db.add(metrics)

        self.db.commit()

    def get_weekly_metrics(
        self, user_id: UUID, week_start: Optional[date] = None
    ) -> Optional[WeeklyMetrics]:
        """
        Get weekly metrics for a user.
        
        Args:
            user_id: User ID
            week_start: Monday date of the week (defaults to current week)
            
        Returns:
            WeeklyMetrics or None if not found
        """
        if week_start is None:
            week_start = get_week_start(datetime.now())

        return (
            self.db.query(WeeklyMetrics)
            .filter(
                and_(
                    WeeklyMetrics.user_id == user_id,
                    WeeklyMetrics.week_start == week_start,
                )
            )
            .first()
        )

