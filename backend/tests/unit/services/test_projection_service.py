"""
Unit tests for WorkoutProjectionBuilder service.

Tests event replay and projection building logic.
"""

from uuid import uuid4
from datetime import datetime, timezone

from app.services.projection_service import WorkoutProjectionBuilder
from app.models.events import Event
from app.models.projections import WorkoutProjection, SetProjection
from app.domain.events import EventType


class TestRebuildProjections:
    """Tests for rebuild_projections method."""

    def test_rebuild_projections_empty_events(self, test_db):
        """Handles empty event log."""
        builder = WorkoutProjectionBuilder(test_db)
        builder.rebuild_projections()

        workouts = test_db.query(WorkoutProjection).all()
        sets = test_db.query(SetProjection).all()

        assert len(workouts) == 0
        assert len(sets) == 0

    def test_rebuild_projections_workout_started_only(self, test_db, sample_user_id, sample_device_id):
        """Creates in_progress workout."""
        builder = WorkoutProjectionBuilder(test_db)

        workout_id = uuid4()
        started_at = datetime.now(timezone.utc)

        # Create WorkoutStarted event
        event = Event(
            event_id=uuid4(),
            user_id=sample_user_id,
            device_id=sample_device_id,
            event_type=EventType.WORKOUT_STARTED,
            payload={"workout_id": str(workout_id), "started_at": started_at.isoformat()},
            sequence_number=1,
        )
        test_db.add(event)
        test_db.commit()

        builder.rebuild_projections()

        workouts = test_db.query(WorkoutProjection).all()
        assert len(workouts) == 1
        assert workouts[0].workout_id == workout_id
        assert workouts[0].user_id == sample_user_id
        assert workouts[0].status == "in_progress"
        assert workouts[0].ended_at is None

    def test_rebuild_projections_complete_workout(self, test_db, sample_user_id, sample_device_id):
        """Creates completed workout with sets."""
        builder = WorkoutProjectionBuilder(test_db)

        workout_id = uuid4()
        exercise_id = uuid4()
        set_id = uuid4()
        started_at = datetime.now(timezone.utc)
        ended_at = datetime.now(timezone.utc)

        # Create events
        events = [
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.WORKOUT_STARTED,
                payload={"workout_id": str(workout_id), "started_at": started_at.isoformat()},
                sequence_number=1,
            ),
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.SET_COMPLETED,
                payload={
                    "workout_id": str(workout_id),
                    "exercise_id": str(exercise_id),
                    "set_id": str(set_id),
                    "reps": 10,
                    "weight": 100.0,
                    "completed_at": started_at.isoformat(),
                },
                sequence_number=2,
            ),
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.WORKOUT_ENDED,
                payload={"workout_id": str(workout_id), "ended_at": ended_at.isoformat()},
                sequence_number=3,
            ),
        ]

        for event in events:
            test_db.add(event)
        test_db.commit()

        builder.rebuild_projections()

        workouts = test_db.query(WorkoutProjection).all()
        sets = test_db.query(SetProjection).all()

        assert len(workouts) == 1
        assert workouts[0].status == "completed"
        assert workouts[0].ended_at is not None

        assert len(sets) == 1
        assert sets[0].workout_id == workout_id
        assert sets[0].exercise_id == exercise_id
        assert sets[0].reps == 10
        assert sets[0].weight == 100.0

    def test_rebuild_projections_multiple_workouts(self, test_db, sample_user_id, sample_device_id):
        """Handles multiple workouts correctly."""
        builder = WorkoutProjectionBuilder(test_db)

        workout1_id = uuid4()
        workout2_id = uuid4()
        started_at = datetime.now(timezone.utc)
        ended_at = datetime.now(timezone.utc)

        # Create events for two workouts
        events = [
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.WORKOUT_STARTED,
                payload={"workout_id": str(workout1_id), "started_at": started_at.isoformat()},
                sequence_number=1,
            ),
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.WORKOUT_ENDED,
                payload={"workout_id": str(workout1_id), "ended_at": ended_at.isoformat()},
                sequence_number=2,
            ),
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.WORKOUT_STARTED,
                payload={"workout_id": str(workout2_id), "started_at": started_at.isoformat()},
                sequence_number=3,
            ),
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.WORKOUT_ENDED,
                payload={"workout_id": str(workout2_id), "ended_at": ended_at.isoformat()},
                sequence_number=4,
            ),
        ]

        for event in events:
            test_db.add(event)
        test_db.commit()

        builder.rebuild_projections()

        workouts = test_db.query(WorkoutProjection).all()
        assert len(workouts) == 2

        workout_ids = {w.workout_id for w in workouts}
        assert workout1_id in workout_ids
        assert workout2_id in workout_ids

    def test_rebuild_projections_skips_orphaned_sets(self, test_db, sample_user_id, sample_device_id):
        """Skips sets without workout."""
        builder = WorkoutProjectionBuilder(test_db)

        workout_id = uuid4()
        exercise_id = uuid4()
        set_id = uuid4()
        started_at = datetime.now(timezone.utc)

        # Create SetCompleted event without WorkoutStarted
        event = Event(
            event_id=uuid4(),
            user_id=sample_user_id,
            device_id=sample_device_id,
            event_type=EventType.SET_COMPLETED,
            payload={
                "workout_id": str(workout_id),
                "exercise_id": str(exercise_id),
                "set_id": str(set_id),
                "reps": 10,
                "weight": 100.0,
                "completed_at": started_at.isoformat(),
            },
            sequence_number=1,
        )
        test_db.add(event)
        test_db.commit()

        builder.rebuild_projections()

        workouts = test_db.query(WorkoutProjection).all()
        sets = test_db.query(SetProjection).all()

        assert len(workouts) == 0
        assert len(sets) == 0  # Orphaned set should be skipped

    def test_rebuild_projections_orders_by_sequence(self, test_db, sample_user_id, sample_device_id):
        """Events processed in correct order."""
        builder = WorkoutProjectionBuilder(test_db)

        workout_id = uuid4()
        exercise_id = uuid4()
        set1_id = uuid4()
        set2_id = uuid4()
        started_at = datetime.now(timezone.utc)
        ended_at = datetime.now(timezone.utc)

        # Create events out of order
        events = [
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.SET_COMPLETED,
                payload={
                    "workout_id": str(workout_id),
                    "exercise_id": str(exercise_id),
                    "set_id": str(set2_id),
                    "reps": 8,
                    "weight": 80.0,
                    "completed_at": started_at.isoformat(),
                },
                sequence_number=3,  # Higher sequence
            ),
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.WORKOUT_STARTED,
                payload={"workout_id": str(workout_id), "started_at": started_at.isoformat()},
                sequence_number=1,  # Lower sequence
            ),
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.SET_COMPLETED,
                payload={
                    "workout_id": str(workout_id),
                    "exercise_id": str(exercise_id),
                    "set_id": str(set1_id),
                    "reps": 10,
                    "weight": 100.0,
                    "completed_at": started_at.isoformat(),
                },
                sequence_number=2,  # Middle sequence
            ),
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.WORKOUT_ENDED,
                payload={"workout_id": str(workout_id), "ended_at": ended_at.isoformat()},
                sequence_number=4,  # Highest sequence
            ),
        ]

        for event in events:
            test_db.add(event)
        test_db.commit()

        builder.rebuild_projections()

        workouts = test_db.query(WorkoutProjection).all()
        sets = test_db.query(SetProjection).all()

        assert len(workouts) == 1
        assert workouts[0].status == "completed"
        assert len(sets) == 2  # Both sets should be included

    def test_rebuild_projections_rebuilds_metrics(self, test_db, sample_user_id, sample_device_id):
        """Calls metrics rebuild after projections."""
        builder = WorkoutProjectionBuilder(test_db)

        workout_id = uuid4()
        exercise_id = uuid4()
        set_id = uuid4()
        started_at = datetime.now(timezone.utc)
        ended_at = datetime.now(timezone.utc)

        # Create complete workout
        events = [
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.WORKOUT_STARTED,
                payload={"workout_id": str(workout_id), "started_at": started_at.isoformat()},
                sequence_number=1,
            ),
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.SET_COMPLETED,
                payload={
                    "workout_id": str(workout_id),
                    "exercise_id": str(exercise_id),
                    "set_id": str(set_id),
                    "reps": 10,
                    "weight": 100.0,
                    "completed_at": started_at.isoformat(),
                },
                sequence_number=2,
            ),
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.WORKOUT_ENDED,
                payload={"workout_id": str(workout_id), "ended_at": ended_at.isoformat()},
                sequence_number=3,
            ),
        ]

        for event in events:
            test_db.add(event)
        test_db.commit()

        # Rebuild should not raise exception (metrics rebuild is called)
        builder.rebuild_projections()

        # Verify projections were created
        workouts = test_db.query(WorkoutProjection).all()
        assert len(workouts) == 1

    def test_rebuild_projections_clears_existing(self, test_db, sample_user_id, sample_device_id):
        """Clears existing projections before rebuilding."""
        builder = WorkoutProjectionBuilder(test_db)

        workout_id = uuid4()
        started_at = datetime.now(timezone.utc)
        ended_at = datetime.now(timezone.utc)

        # Create initial workout
        events = [
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.WORKOUT_STARTED,
                payload={"workout_id": str(workout_id), "started_at": started_at.isoformat()},
                sequence_number=1,
            ),
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.WORKOUT_ENDED,
                payload={"workout_id": str(workout_id), "ended_at": ended_at.isoformat()},
                sequence_number=2,
            ),
        ]

        for event in events:
            test_db.add(event)
        test_db.commit()

        # First rebuild
        builder.rebuild_projections()
        workouts_first = test_db.query(WorkoutProjection).count()
        assert workouts_first == 1

        # Delete the event
        test_db.query(Event).delete()
        test_db.commit()

        # Second rebuild should clear existing
        builder.rebuild_projections()
        workouts_second = test_db.query(WorkoutProjection).count()
        assert workouts_second == 0


class TestUpdateProjections:
    """Tests for update_projections method."""

    def test_update_projections_incremental(self, test_db, sample_user_id, sample_device_id):
        """Updates projections from new events."""
        builder = WorkoutProjectionBuilder(test_db)

        workout_id = uuid4()
        exercise_id = uuid4()
        set_id = uuid4()
        started_at = datetime.now(timezone.utc)
        ended_at = datetime.now(timezone.utc)

        # Create initial events
        initial_events = [
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.WORKOUT_STARTED,
                payload={"workout_id": str(workout_id), "started_at": started_at.isoformat()},
                sequence_number=1,
            ),
        ]

        for event in initial_events:
            test_db.add(event)
        test_db.commit()

        # Initial rebuild
        builder.rebuild_projections()
        workouts = test_db.query(WorkoutProjection).all()
        assert len(workouts) == 1
        assert workouts[0].status == "in_progress"

        # Add more events
        new_events = [
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.SET_COMPLETED,
                payload={
                    "workout_id": str(workout_id),
                    "exercise_id": str(exercise_id),
                    "set_id": str(set_id),
                    "reps": 10,
                    "weight": 100.0,
                    "completed_at": started_at.isoformat(),
                },
                sequence_number=2,
            ),
            Event(
                event_id=uuid4(),
                user_id=sample_user_id,
                device_id=sample_device_id,
                event_type=EventType.WORKOUT_ENDED,
                payload={"workout_id": str(workout_id), "ended_at": ended_at.isoformat()},
                sequence_number=3,
            ),
        ]

        for event in new_events:
            test_db.add(event)
        test_db.commit()

        # Update projections (currently just calls rebuild)
        all_events = test_db.query(Event).all()
        builder.update_projections(all_events)

        workouts = test_db.query(WorkoutProjection).all()
        sets = test_db.query(SetProjection).all()

        assert len(workouts) == 1
        assert workouts[0].status == "completed"
        assert len(sets) == 1

