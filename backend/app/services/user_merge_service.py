"""
User merge service: merge anonymous user data to real user account.

This service is transactional and idempotent - safe to call multiple times.
"""

from uuid import UUID
from sqlalchemy.orm import Session
from sqlalchemy import update

from app.models.user import User
from app.models.events import Event
from app.models.projections import (
    WorkoutProjection,
    WeeklyMetrics,
    WeeklyReport,
)


class UserMergeService:
    """Service for merging anonymous user data to real user account."""

    def __init__(self, db: Session):
        self.db = db

    def merge_user_data(
        self,
        anonymous_user_id: UUID,
        real_user_id: UUID,
    ) -> dict:
        """
        Merge all anonymous user data to real user account.

        Updates all tables atomically:
        - events.user_id
        - workouts_projection.user_id (sets are linked via workout_id, no direct update needed)
        - weekly_metrics.user_id
        - weekly_reports.user_id

        Args:
            anonymous_user_id: The anonymous user's UUID
            real_user_id: The real (authenticated) user's UUID

        Returns:
            Dictionary with merge statistics

        Raises:
            ValueError: If users don't exist or validation fails
        """
        # Validate users exist
        anonymous_user = (
            self.db.query(User).filter(User.user_id == anonymous_user_id).first()
        )
        if not anonymous_user:
            raise ValueError(f"Anonymous user {anonymous_user_id} not found")

        real_user = self.db.query(User).filter(User.user_id == real_user_id).first()
        if not real_user:
            raise ValueError(f"Real user {real_user_id} not found")

        # Validate anonymous user is actually anonymous
        if not anonymous_user.is_anonymous:
            raise ValueError(
                f"User {anonymous_user_id} is not anonymous (already merged?)"
            )

        # Validate real user is not anonymous
        if real_user.is_anonymous:
            raise ValueError(
                f"User {real_user_id} is anonymous (cannot merge to anonymous user)"
            )

        # Check if already merged (idempotency check)
        # If no events exist for anonymous_user_id, assume already merged
        event_count = (
            self.db.query(Event).filter(Event.user_id == anonymous_user_id).count()
        )

        if event_count == 0:
            # Already merged or no data to merge
            return {
                "merged": False,
                "message": "No data to merge (already merged or no anonymous data)",
                "events_updated": 0,
                "workouts_updated": 0,
                "metrics_updated": 0,
                "reports_updated": 0,
            }

        # Perform merge in single transaction
        try:
            # Update events
            events_updated = self.db.execute(
                update(Event)
                .where(Event.user_id == anonymous_user_id)
                .values(user_id=real_user_id)
            ).rowcount

            # Update workouts_projection
            # (sets are linked via workout_id foreign key, no direct update needed)
            workouts_updated = self.db.execute(
                update(WorkoutProjection)
                .where(WorkoutProjection.user_id == anonymous_user_id)
                .values(user_id=real_user_id)
            ).rowcount

            # Update weekly_metrics
            metrics_updated = self.db.execute(
                update(WeeklyMetrics)
                .where(WeeklyMetrics.user_id == anonymous_user_id)
                .values(user_id=real_user_id)
            ).rowcount

            # Update weekly_reports
            reports_updated = self.db.execute(
                update(WeeklyReport)
                .where(WeeklyReport.user_id == anonymous_user_id)
                .values(user_id=real_user_id)
            ).rowcount

            # Delete anonymous user record after successful merge
            # All data has been transferred to real user, so anonymous user is no longer needed
            self.db.delete(anonymous_user)

            # Commit all changes atomically
            self.db.commit()

            return {
                "merged": True,
                "message": "User data merged successfully",
                "events_updated": events_updated,
                "workouts_updated": workouts_updated,
                "metrics_updated": metrics_updated,
                "reports_updated": reports_updated,
            }

        except Exception as e:
            # Rollback on any error
            self.db.rollback()
            raise ValueError(f"Merge failed: {str(e)}") from e
