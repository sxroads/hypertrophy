"""
Projection builder service.

Replays events in (device_id, sequence_number) order to build
deterministic projections: workouts_projection and sets_projection.
"""

from typing import Dict
from uuid import UUID
from datetime import datetime
from sqlalchemy.orm import Session
from sqlalchemy import distinct

from app.models.events import Event
from app.models.projections import WorkoutProjection, SetProjection
from app.domain.events import EventType
from app.services.metrics_service import MetricsService


class WorkoutProjectionBuilder:
    """Builds workout projections from events."""

    def __init__(self, db: Session):
        self.db = db

    def rebuild_projections(self) -> None:
        """
        Rebuild all projections from events.

        Drops existing projections and replays full event log
        to produce identical projection state.
        """
        # Drop existing projections - delete sets first (they have foreign key to workouts)
        self.db.query(SetProjection).delete()
        self.db.query(WorkoutProjection).delete()
        self.db.commit()

        # Replay all events in order
        self._replay_events()

        # Rebuild weekly metrics for all users who have workouts
        self._rebuild_metrics_for_all_users()

    def _replay_events(self) -> None:
        """Replay events in (device_id, sequence_number) order."""
        # Query all events ordered by device_id and sequence_number
        events = (
            self.db.query(Event).order_by(Event.device_id, Event.sequence_number).all()
        )

        # Track workout state per workout_id
        workouts: Dict[UUID, Dict] = {}

        for event in events:
            if event.event_type == EventType.WORKOUT_STARTED:
                payload = event.payload
                workout_id = UUID(payload["workout_id"])
                started_at = payload["started_at"]
                if isinstance(started_at, str):
                    started_at = datetime.fromisoformat(
                        started_at.replace("Z", "+00:00")
                    )

                workouts[workout_id] = {
                    "workout_id": workout_id,
                    "user_id": event.user_id,
                    "started_at": started_at,
                    "ended_at": None,
                    "status": "in_progress",
                }

            elif event.event_type == EventType.WORKOUT_ENDED:
                payload = event.payload
                workout_id = UUID(payload["workout_id"])
                if workout_id in workouts:
                    ended_at = payload["ended_at"]
                    if isinstance(ended_at, str):
                        ended_at = datetime.fromisoformat(
                            ended_at.replace("Z", "+00:00")
                        )
                    workouts[workout_id]["ended_at"] = ended_at
                    workouts[workout_id]["status"] = "completed"
                else:
                    print(
                        f"[PROJECTION] WARNING: WORKOUT_ENDED for unknown workout_id={workout_id}"
                    )

        # Insert workout projections first (sets have foreign key dependency)
        for workout_data in workouts.values():
            workout = WorkoutProjection(
                workout_id=workout_data["workout_id"],
                user_id=workout_data["user_id"],
                started_at=workout_data["started_at"],
                ended_at=workout_data["ended_at"],
                status=workout_data["status"],
            )
            self.db.add(workout)

        # Commit workouts first so foreign key constraint is satisfied
        self.db.commit()

        # Process sets - only include sets for workouts that exist
        sets: Dict[UUID, Dict] = {}
        skipped_sets = 0

        for event in events:
            if event.event_type == EventType.SET_COMPLETED:
                payload = event.payload
                workout_id = UUID(payload["workout_id"])

                # Only process sets for workouts that exist
                if workout_id not in workouts:
                    skipped_sets += 1
                    continue

                set_id = UUID(payload["set_id"])
                completed_at = payload["completed_at"]
                if isinstance(completed_at, str):
                    completed_at = datetime.fromisoformat(
                        completed_at.replace("Z", "+00:00")
                    )

                sets[set_id] = {
                    "set_id": set_id,
                    "workout_id": workout_id,
                    "exercise_id": UUID(payload["exercise_id"]),
                    "reps": payload["reps"],
                    "weight": payload["weight"],
                    "completed_at": completed_at,
                }

        # Insert set projections
        for set_data in sets.values():
            set_proj = SetProjection(
                set_id=set_data["set_id"],
                workout_id=set_data["workout_id"],
                exercise_id=set_data["exercise_id"],
                reps=set_data["reps"],
                weight=set_data["weight"],
                completed_at=set_data["completed_at"],
            )
            self.db.add(set_proj)

        self.db.commit()

    def update_projections(self, new_events: list[Event], user_id: UUID) -> None:
        """
        Update projections incrementally from new events.
        Only processes new events and updates affected projections.

        Args:
            new_events: List of new events to process (already ordered)
            user_id: User ID whose projections are being updated
        """
        # Track workouts created in this transaction to avoid duplicate inserts
        # SQLAlchemy queries don't see objects added to session until flushed
        # This dictionary tracks workouts added in the current transaction
        workouts_in_transaction: Dict[UUID, WorkoutProjection] = {}

        # Separate workout events from set events to ensure workouts are committed before sets
        # Sets have a foreign key constraint to workouts, so workouts must exist first
        # This separation ensures proper ordering and avoids foreign key violations
        workout_events = []
        set_events = []

        for event in new_events:
            if event.event_type in (EventType.WORKOUT_STARTED, EventType.WORKOUT_ENDED):
                workout_events.append(event)
            elif event.event_type == EventType.SET_COMPLETED:
                set_events.append(event)

        # Process workout events first
        for event in workout_events:
            if event.event_type == EventType.WORKOUT_STARTED:
                payload = event.payload
                workout_id = UUID(payload["workout_id"])
                started_at = payload["started_at"]
                if isinstance(started_at, str):
                    started_at = datetime.fromisoformat(
                        started_at.replace("Z", "+00:00")
                    )

                # Check if workout was created in this transaction first
                if workout_id in workouts_in_transaction:
                    workout = workouts_in_transaction[workout_id]
                    # Update started_at but preserve completed status if already completed
                    workout.started_at = started_at
                    if workout.status != "completed":
                        workout.status = "in_progress"
                        workout.ended_at = None
                else:
                    # Upsert workout projection
                    existing = (
                        self.db.query(WorkoutProjection)
                        .filter(WorkoutProjection.workout_id == workout_id)
                        .first()
                    )

                    if existing:
                        # Update started_at but preserve completed status if already completed
                        # This prevents resetting completed workouts to in_progress
                        existing.started_at = started_at
                        if existing.status != "completed":
                            existing.status = "in_progress"
                            existing.ended_at = None
                    else:
                        workout = WorkoutProjection(
                            workout_id=workout_id,
                            user_id=event.user_id,
                            started_at=started_at,
                            ended_at=None,
                            status="in_progress",
                        )
                        self.db.add(workout)
                        workouts_in_transaction[workout_id] = workout

            elif event.event_type == EventType.WORKOUT_ENDED:
                payload = event.payload
                workout_id = UUID(payload["workout_id"])
                ended_at = payload["ended_at"]
                if isinstance(ended_at, str):
                    ended_at = datetime.fromisoformat(ended_at.replace("Z", "+00:00"))

                # Check if workout was created in this transaction first
                if workout_id in workouts_in_transaction:
                    workout = workouts_in_transaction[workout_id]
                    workout.ended_at = ended_at
                    workout.status = "completed"
                else:
                    # Update existing workout projection
                    workout = (
                        self.db.query(WorkoutProjection)
                        .filter(WorkoutProjection.workout_id == workout_id)
                        .first()
                    )

                    if workout:
                        workout.ended_at = ended_at
                        workout.status = "completed"
                    else:
                        # Create workout if it doesn't exist (handles edge case where WorkoutEnded comes before WorkoutStarted)
                        # This can happen if events are processed out of order or if WorkoutStarted failed
                        print(
                            f"[PROJECTION] WARNING: WORKOUT_ENDED for unknown workout_id={workout_id}, creating workout"
                        )
                        # Try to get user_id from the event
                        workout = WorkoutProjection(
                            workout_id=workout_id,
                            user_id=event.user_id,
                            started_at=ended_at,  # Use ended_at as fallback if started_at not available
                            ended_at=ended_at,
                            status="completed",
                        )
                        self.db.add(workout)
                        workouts_in_transaction[workout_id] = workout

        # Flush workouts to database before processing sets (required for foreign key constraint)
        # flush() writes to DB without committing, making workouts visible to subsequent queries
        # This is necessary because sets have a foreign key to workouts
        if workouts_in_transaction:
            self.db.flush()

        # Process set events after workouts are flushed
        # Now we can safely create sets that reference the workouts
        for event in set_events:
            payload = event.payload
            set_id = UUID(payload["set_id"])
            workout_id = UUID(payload["workout_id"])

            # Check if workout exists (in transaction or database)
            # First check in-memory transaction cache, then query database
            # This handles cases where workout was created in this transaction or already exists
            workout_exists = workout_id in workouts_in_transaction
            if not workout_exists:
                # Query database for existing workout (single query per set - acceptable here)
                # Note: This could be optimized with batch lookup if many sets reference same workout
                workout = (
                    self.db.query(WorkoutProjection)
                    .filter(WorkoutProjection.workout_id == workout_id)
                    .first()
                )
                workout_exists = workout is not None

            if not workout_exists:
                print(
                    f"[PROJECTION] WARNING: SET_COMPLETED for unknown workout_id={workout_id}, skipping"
                )
                continue

            completed_at = payload["completed_at"]
            if isinstance(completed_at, str):
                completed_at = datetime.fromisoformat(
                    completed_at.replace("Z", "+00:00")
                )

            # Upsert set projection
            existing = (
                self.db.query(SetProjection)
                .filter(SetProjection.set_id == set_id)
                .first()
            )

            if existing:
                existing.workout_id = workout_id
                existing.exercise_id = UUID(payload["exercise_id"])
                existing.reps = payload["reps"]
                existing.weight = payload["weight"]
                existing.completed_at = completed_at
            else:
                set_proj = SetProjection(
                    set_id=set_id,
                    workout_id=workout_id,
                    exercise_id=UUID(payload["exercise_id"]),
                    reps=payload["reps"],
                    weight=payload["weight"],
                    completed_at=completed_at,
                )
                self.db.add(set_proj)

        self.db.commit()

        # Rebuild metrics only for this user
        metrics_service = MetricsService(self.db)
        try:
            metrics_service.rebuild_weekly_metrics(user_id)
        except Exception as e:
            print(
                f"[PROJECTION] WARNING: Failed to rebuild metrics for user {user_id}: {e}"
            )

    def _rebuild_metrics_for_all_users(self) -> None:
        """Rebuild weekly metrics for all users who have workouts."""
        # Get all unique user_ids from workouts
        user_ids = self.db.query(distinct(WorkoutProjection.user_id)).all()

        if not user_ids:
            return

        metrics_service = MetricsService(self.db)

        for (user_id,) in user_ids:
            try:
                metrics_service.rebuild_weekly_metrics(user_id)
            except Exception as e:
                print(
                    f"[PROJECTION] WARNING: Failed to rebuild metrics for user {user_id}: {e}"
                )
