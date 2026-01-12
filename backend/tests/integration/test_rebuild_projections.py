"""
Test rebuild: build projections, drop projections, rebuild → identical result.

This test verifies that:
1. Projections can be rebuilt from events
2. Rebuilding produces identical results
3. Rebuild is deterministic (same events → same projections)
"""

import pytest
from uuid import uuid4
from datetime import datetime, timezone

from app.services.sync_service import SyncService
from app.services.projection_service import WorkoutProjectionBuilder
from app.models.events import Event
from app.models.projections import WorkoutProjection, SetProjection


def test_rebuild_projections_produces_identical_result(
    test_db, sample_user_id, sample_device_id
):
    """Test that rebuilding projections produces identical results."""
    sync_service = SyncService(test_db)
    projection_builder = WorkoutProjectionBuilder(test_db)

    # Create multiple workouts with sets
    workout1_id = uuid4()
    workout2_id = uuid4()
    exercise1_id = uuid4()
    exercise2_id = uuid4()
    started_at = datetime.now(timezone.utc)
    ended_at = datetime.now(timezone.utc)

    events = [
        # Workout 1
        {
            "event_id": str(uuid4()),
            "event_type": "WorkoutStarted",
            "payload": {
                "workout_id": str(workout1_id),
                "started_at": started_at.isoformat(),
            },
            "sequence_number": 1,
        },
        {
            "event_id": str(uuid4()),
            "event_type": "ExerciseAdded",
            "payload": {
                "workout_id": str(workout1_id),
                "exercise_id": str(exercise1_id),
                "exercise_name": "Bench Press",
            },
            "sequence_number": 2,
        },
        {
            "event_id": str(uuid4()),
            "event_type": "SetCompleted",
            "payload": {
                "workout_id": str(workout1_id),
                "exercise_id": str(exercise1_id),
                "set_id": str(uuid4()),
                "reps": 10,
                "weight": 100.0,
                "completed_at": started_at.isoformat(),
            },
            "sequence_number": 3,
        },
        {
            "event_id": str(uuid4()),
            "event_type": "SetCompleted",
            "payload": {
                "workout_id": str(workout1_id),
                "exercise_id": str(exercise1_id),
                "set_id": str(uuid4()),
                "reps": 8,
                "weight": 100.0,
                "completed_at": started_at.isoformat(),
            },
            "sequence_number": 4,
        },
        {
            "event_id": str(uuid4()),
            "event_type": "WorkoutEnded",
            "payload": {
                "workout_id": str(workout1_id),
                "ended_at": ended_at.isoformat(),
            },
            "sequence_number": 5,
        },
        # Workout 2
        {
            "event_id": str(uuid4()),
            "event_type": "WorkoutStarted",
            "payload": {
                "workout_id": str(workout2_id),
                "started_at": started_at.isoformat(),
            },
            "sequence_number": 6,
        },
        {
            "event_id": str(uuid4()),
            "event_type": "ExerciseAdded",
            "payload": {
                "workout_id": str(workout2_id),
                "exercise_id": str(exercise2_id),
                "exercise_name": "Squat",
            },
            "sequence_number": 7,
        },
        {
            "event_id": str(uuid4()),
            "event_type": "SetCompleted",
            "payload": {
                "workout_id": str(workout2_id),
                "exercise_id": str(exercise2_id),
                "set_id": str(uuid4()),
                "reps": 5,
                "weight": 150.0,
                "completed_at": started_at.isoformat(),
            },
            "sequence_number": 8,
        },
        {
            "event_id": str(uuid4()),
            "event_type": "WorkoutEnded",
            "payload": {
                "workout_id": str(workout2_id),
                "ended_at": ended_at.isoformat(),
            },
            "sequence_number": 9,
        },
    ]

    # Sync all events
    result = sync_service.sync_events(
        device_id=sample_device_id,
        user_id=sample_user_id,
        events=events,
    )
    assert result.accepted_count == 9

    # Build projections first time
    projection_builder.rebuild_projections()

    # Capture first projection state
    workouts_first = test_db.query(WorkoutProjection).all()
    sets_first = test_db.query(SetProjection).all()

    # Serialize for comparison
    workouts_data_first = sorted(
        [
            {
                "workout_id": str(w.workout_id),
                "user_id": str(w.user_id),
                "status": w.status,
            }
            for w in workouts_first
        ],
        key=lambda x: x["workout_id"],
    )

    sets_data_first = sorted(
        [
            {
                "set_id": str(s.set_id),
                "workout_id": str(s.workout_id),
                "reps": s.reps,
                "weight": s.weight,
            }
            for s in sets_first
        ],
        key=lambda x: x["set_id"],
    )

    # Drop projections
    test_db.query(WorkoutProjection).delete()
    test_db.query(SetProjection).delete()
    test_db.commit()

    assert test_db.query(WorkoutProjection).count() == 0
    assert test_db.query(SetProjection).count() == 0

    # Rebuild projections
    projection_builder.rebuild_projections()

    # Capture second projection state
    workouts_second = test_db.query(WorkoutProjection).all()
    sets_second = test_db.query(SetProjection).all()

    workouts_data_second = sorted(
        [
            {
                "workout_id": str(w.workout_id),
                "user_id": str(w.user_id),
                "status": w.status,
            }
            for w in workouts_second
        ],
        key=lambda x: x["workout_id"],
    )

    sets_data_second = sorted(
        [
            {
                "set_id": str(s.set_id),
                "workout_id": str(s.workout_id),
                "reps": s.reps,
                "weight": s.weight,
            }
            for s in sets_second
        ],
        key=lambda x: x["set_id"],
    )

    # Verify projections are identical
    assert len(workouts_data_first) == len(workouts_data_second)
    assert len(sets_data_first) == len(sets_data_second)
    assert workouts_data_first == workouts_data_second, (
        "Workout projections must be identical after rebuild"
    )
    assert sets_data_first == sets_data_second, (
        "Set projections must be identical after rebuild"
    )


def test_rebuild_multiple_times_consistent(test_db, sample_user_id, sample_device_id):
    """Test that rebuilding multiple times produces consistent results."""
    sync_service = SyncService(test_db)
    projection_builder = WorkoutProjectionBuilder(test_db)

    workout_id = uuid4()
    started_at = datetime.now(timezone.utc)
    ended_at = datetime.now(timezone.utc)

    events = [
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
            "event_type": "WorkoutEnded",
            "payload": {
                "workout_id": str(workout_id),
                "ended_at": ended_at.isoformat(),
            },
            "sequence_number": 2,
        },
    ]

    # Sync events
    sync_service.sync_events(
        device_id=sample_device_id,
        user_id=sample_user_id,
        events=events,
    )

    # Rebuild multiple times and verify consistency
    projection_states = []

    for _ in range(3):
        projection_builder.rebuild_projections()

        workouts = test_db.query(WorkoutProjection).all()
        state = {
            "workout_count": len(workouts),
            "workouts": sorted(
                [
                    {
                        "workout_id": str(w.workout_id),
                        "status": w.status,
                    }
                    for w in workouts
                ],
                key=lambda x: x["workout_id"],
            ),
        }
        projection_states.append(state)

    # All states should be identical
    assert all(state == projection_states[0] for state in projection_states), (
        "Multiple rebuilds must produce identical results"
    )


def test_rebuild_with_no_events(test_db):
    """Test that rebuilding with no events produces empty projections."""
    projection_builder = WorkoutProjectionBuilder(test_db)

    # Rebuild with no events
    projection_builder.rebuild_projections()

    assert test_db.query(WorkoutProjection).count() == 0
    assert test_db.query(SetProjection).count() == 0


def test_rebuild_preserves_all_workouts_and_sets(
    test_db, sample_user_id, sample_device_id
):
    """Test that rebuild preserves all workouts and sets from events."""
    sync_service = SyncService(test_db)
    projection_builder = WorkoutProjectionBuilder(test_db)

    # Create events for 3 workouts
    workout_ids = [uuid4() for _ in range(3)]
    started_at = datetime.now(timezone.utc)
    ended_at = datetime.now(timezone.utc)

    events = []
    for i, workout_id in enumerate(workout_ids):
        events.append(
            {
                "event_id": str(uuid4()),
                "event_type": "WorkoutStarted",
                "payload": {
                    "workout_id": str(workout_id),
                    "started_at": started_at.isoformat(),
                },
                "sequence_number": i * 2 + 1,
            }
        )
        events.append(
            {
                "event_id": str(uuid4()),
                "event_type": "WorkoutEnded",
                "payload": {
                    "workout_id": str(workout_id),
                    "ended_at": ended_at.isoformat(),
                },
                "sequence_number": i * 2 + 2,
            }
        )

    # Sync events
    sync_service.sync_events(
        device_id=sample_device_id,
        user_id=sample_user_id,
        events=events,
    )

    # Rebuild
    projection_builder.rebuild_projections()

    # Verify all workouts are present
    workouts = test_db.query(WorkoutProjection).all()
    assert len(workouts) == 3

    workout_ids_in_projection = {w.workout_id for w in workouts}
    assert workout_ids_in_projection == set(workout_ids)
