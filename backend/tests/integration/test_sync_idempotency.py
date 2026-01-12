"""
Test idempotency: same event batch submitted twice → no duplicates.

This test verifies that:
1. Same event batch can be submitted multiple times
2. No duplicate events are created
3. Event replay produces same projections
"""

from uuid import uuid4
from datetime import datetime, timezone

from app.services.sync_service import SyncService
from app.services.projection_service import WorkoutProjectionBuilder
from app.models.events import Event
from app.models.projections import WorkoutProjection, SetProjection


def test_sync_idempotency_same_batch_twice(test_db, sample_user_id, sample_device_id):
    """Test that submitting the same batch twice creates no duplicates."""
    sync_service = SyncService(test_db)

    # Create a batch of events
    workout_id = uuid4()
    exercise_id = uuid4()
    set_id = uuid4()
    started_at = datetime.now(timezone.utc)
    ended_at = datetime.now(timezone.utc)

    events_batch = [
        {
            "event_id": str(uuid4()),
            "event_type": "WorkoutStarted",
            "payload": {
                "workout_id": str(workout_id),
                "started_at": started_at.isoformat(),
            },
            "sequence_number": 1,
        },
        {
            "event_id": str(uuid4()),
            "event_type": "ExerciseAdded",
            "payload": {
                "workout_id": str(workout_id),
                "exercise_id": str(exercise_id),
                "exercise_name": "Bench Press",
            },
            "sequence_number": 2,
        },
        {
            "event_id": str(uuid4()),
            "event_type": "SetCompleted",
            "payload": {
                "workout_id": str(workout_id),
                "exercise_id": str(exercise_id),
                "set_id": str(set_id),
                "reps": 10,
                "weight": 100.0,
                "completed_at": started_at.isoformat(),
            },
            "sequence_number": 3,
        },
        {
            "event_id": str(uuid4()),
            "event_type": "WorkoutEnded",
            "payload": {
                "workout_id": str(workout_id),
                "ended_at": ended_at.isoformat(),
            },
            "sequence_number": 4,
        },
    ]

    # Submit batch first time
    result1 = sync_service.sync_events(
        device_id=sample_device_id,
        user_id=sample_user_id,
        events=events_batch,
    )

    # Verify first submission succeeded
    assert result1.accepted_count == 4
    assert result1.rejected_count == 0
    assert result1.last_acked_sequence == 4

    # Count events in DB
    event_count_after_first = test_db.query(Event).count()
    assert event_count_after_first == 4

    # Submit same batch again (same event_ids)
    result2 = sync_service.sync_events(
        device_id=sample_device_id,
        user_id=sample_user_id,
        events=events_batch,
    )

    # Verify second submission is idempotent
    assert result2.accepted_count == 4  # Events are "accepted" (already exist)
    assert result2.rejected_count == 0
    assert result2.last_acked_sequence == 4

    # Verify no new events were created
    event_count_after_second = test_db.query(Event).count()
    assert event_count_after_second == 4, "Duplicate events should not be created"

    # Verify event_ids are unique
    event_ids = [e.event_id for e in test_db.query(Event).all()]
    assert len(event_ids) == len(set(event_ids)), "All event_ids must be unique"


def test_sync_idempotency_replay_produces_same_projections(
    test_db, sample_user_id, sample_device_id
):
    """Test that event replay produces identical projections after duplicate submissions."""
    sync_service = SyncService(test_db)
    projection_builder = WorkoutProjectionBuilder(test_db)

    # Create events
    workout_id = uuid4()
    exercise_id = uuid4()
    set_id = uuid4()
    started_at = datetime.now(timezone.utc)
    ended_at = datetime.now(timezone.utc)

    events_batch = [
        {
            "event_id": str(uuid4()),
            "event_type": "WorkoutStarted",
            "payload": {
                "workout_id": str(workout_id),
                "started_at": started_at.isoformat(),
            },
            "sequence_number": 1,
        },
        {
            "event_id": str(uuid4()),
            "event_type": "SetCompleted",
            "payload": {
                "workout_id": str(workout_id),
                "exercise_id": str(exercise_id),
                "set_id": str(set_id),
                "reps": 8,
                "weight": 80.0,
                "completed_at": started_at.isoformat(),
            },
            "sequence_number": 2,
        },
        {
            "event_id": str(uuid4()),
            "event_type": "WorkoutEnded",
            "payload": {
                "workout_id": str(workout_id),
                "ended_at": ended_at.isoformat(),
            },
            "sequence_number": 3,
        },
    ]

    # Submit batch
    sync_service.sync_events(
        device_id=sample_device_id,
        user_id=sample_user_id,
        events=events_batch,
    )

    # Build projections first time
    projection_builder.rebuild_projections()

    # Capture first projection state
    workouts_first = test_db.query(WorkoutProjection).all()
    sets_first = test_db.query(SetProjection).all()

    workout_data_first = [
        {
            "workout_id": w.workout_id,
            "user_id": w.user_id,
            "status": w.status,
        }
        for w in workouts_first
    ]
    sets_data_first = [
        {
            "set_id": s.set_id,
            "workout_id": s.workout_id,
            "reps": s.reps,
            "weight": s.weight,
        }
        for s in sets_first
    ]

    # Submit same batch again (idempotent)
    sync_service.sync_events(
        device_id=sample_device_id,
        user_id=sample_user_id,
        events=events_batch,
    )

    # Rebuild projections again
    projection_builder.rebuild_projections()

    # Capture second projection state
    workouts_second = test_db.query(WorkoutProjection).all()
    sets_second = test_db.query(SetProjection).all()

    workout_data_second = [
        {
            "workout_id": w.workout_id,
            "user_id": w.user_id,
            "status": w.status,
        }
        for w in workouts_second
    ]
    sets_data_second = [
        {
            "set_id": s.set_id,
            "workout_id": s.workout_id,
            "reps": s.reps,
            "weight": s.weight,
        }
        for s in sets_second
    ]

    # Verify projections are identical
    assert len(workout_data_first) == len(workout_data_second)
    assert len(sets_data_first) == len(sets_data_second)
    assert workout_data_first == workout_data_second, (
        "Workout projections must be identical"
    )
    assert sets_data_first == sets_data_second, "Set projections must be identical"
