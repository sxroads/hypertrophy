"""
Unit tests for MetricsService.

Tests weekly metrics calculation and rebuild functionality.
"""

from uuid import uuid4
from datetime import datetime, date, timedelta, timezone

from app.services.metrics_service import MetricsService, get_week_start
from app.models.projections import WorkoutProjection, SetProjection, WeeklyMetrics
from app.domain.events import EventType


class TestGetWeekStart:
    """Tests for get_week_start helper function."""

    def test_get_week_start_monday(self):
        """Monday returns itself."""
        monday = datetime(2024, 1, 1, 10, 0, 0)  # Monday
        week_start = get_week_start(monday)
        assert week_start == date(2024, 1, 1)

    def test_get_week_start_tuesday(self):
        """Tuesday returns previous Monday."""
        tuesday = datetime(2024, 1, 2, 10, 0, 0)  # Tuesday
        week_start = get_week_start(tuesday)
        assert week_start == date(2024, 1, 1)

    def test_get_week_start_sunday(self):
        """Sunday returns previous Monday."""
        sunday = datetime(2024, 1, 7, 10, 0, 0)  # Sunday
        week_start = get_week_start(sunday)
        assert week_start == date(2024, 1, 1)


class TestCalculateWeeklyMetrics:
    """Tests for calculate_weekly_metrics method."""

    def test_calculate_weekly_metrics_single_workout(self, test_db, sample_user_id):
        """Calculates metrics for one workout."""
        service = MetricsService(test_db)

        workout_id = uuid4()
        exercise_id = uuid4()
        set_id = uuid4()
        # Use a Monday for week_start
        monday = datetime(2024, 1, 1, 10, 0, 0)  # Monday
        week_start = get_week_start(monday)

        # Create workout projection
        workout = WorkoutProjection(
            workout_id=workout_id,
            user_id=sample_user_id,
            started_at=monday,
            ended_at=monday + timedelta(hours=1),
            status="completed",
        )
        test_db.add(workout)
        test_db.commit()

        # Create set projection
        set_proj = SetProjection(
            set_id=set_id,
            workout_id=workout_id,
            exercise_id=exercise_id,
            reps=10,
            weight=100.0,
            completed_at=monday,
        )
        test_db.add(set_proj)
        test_db.commit()

        metrics = service.calculate_weekly_metrics(sample_user_id, week_start)

        assert metrics.user_id == sample_user_id
        assert metrics.week_start == week_start
        assert metrics.total_workouts == 1
        assert metrics.total_volume == 1000.0  # 10 reps * 100.0 kg
        assert metrics.exercises_count == 1

    def test_calculate_weekly_metrics_multiple_workouts(self, test_db, sample_user_id):
        """Aggregates multiple workouts."""
        service = MetricsService(test_db)

        workout1_id = uuid4()
        workout2_id = uuid4()
        exercise1_id = uuid4()
        exercise2_id = uuid4()
        set1_id = uuid4()
        set2_id = uuid4()
        set3_id = uuid4()

        monday = datetime(2024, 1, 1, 10, 0, 0)  # Monday
        week_start = get_week_start(monday)

        # Create two workouts
        workout1 = WorkoutProjection(
            workout_id=workout1_id,
            user_id=sample_user_id,
            started_at=monday,
            ended_at=monday + timedelta(hours=1),
            status="completed",
        )
        workout2 = WorkoutProjection(
            workout_id=workout2_id,
            user_id=sample_user_id,
            started_at=monday + timedelta(days=1),
            ended_at=monday + timedelta(days=1, hours=1),
            status="completed",
        )
        test_db.add(workout1)
        test_db.add(workout2)
        test_db.commit()

        # Create sets
        set1 = SetProjection(
            set_id=set1_id,
            workout_id=workout1_id,
            exercise_id=exercise1_id,
            reps=10,
            weight=100.0,
            completed_at=monday,
        )
        set2 = SetProjection(
            set_id=set2_id,
            workout_id=workout1_id,
            exercise_id=exercise2_id,
            reps=8,
            weight=80.0,
            completed_at=monday,
        )
        set3 = SetProjection(
            set_id=set3_id,
            workout_id=workout2_id,
            exercise_id=exercise1_id,
            reps=12,
            weight=90.0,
            completed_at=monday + timedelta(days=1),
        )
        test_db.add(set1)
        test_db.add(set2)
        test_db.add(set3)
        test_db.commit()

        metrics = service.calculate_weekly_metrics(sample_user_id, week_start)

        assert metrics.total_workouts == 2
        assert metrics.total_volume == 2560.0  # (10*100) + (8*80) + (12*90)
        assert metrics.exercises_count == 2  # exercise1_id and exercise2_id

    def test_calculate_weekly_metrics_no_workouts(self, test_db, sample_user_id):
        """Returns zero metrics for empty week."""
        service = MetricsService(test_db)

        monday = datetime(2024, 1, 1, 10, 0, 0)
        week_start = get_week_start(monday)

        metrics = service.calculate_weekly_metrics(sample_user_id, week_start)

        assert metrics.user_id == sample_user_id
        assert metrics.week_start == week_start
        assert metrics.total_workouts == 0
        assert metrics.total_volume == 0.0
        assert metrics.exercises_count == 0

    def test_calculate_weekly_metrics_volume_calculation(self, test_db, sample_user_id):
        """Correctly sums reps * weight."""
        service = MetricsService(test_db)

        workout_id = uuid4()
        exercise_id = uuid4()
        monday = datetime(2024, 1, 1, 10, 0, 0)
        week_start = get_week_start(monday)

        workout = WorkoutProjection(
            workout_id=workout_id,
            user_id=sample_user_id,
            started_at=monday,
            ended_at=monday + timedelta(hours=1),
            status="completed",
        )
        test_db.add(workout)
        test_db.commit()

        # Create multiple sets
        for i, (reps, weight) in enumerate([(10, 100.0), (8, 80.0), (12, 90.0)]):
            set_proj = SetProjection(
                set_id=uuid4(),
                workout_id=workout_id,
                exercise_id=exercise_id,
                reps=reps,
                weight=weight,
                completed_at=monday + timedelta(minutes=i * 10),
            )
            test_db.add(set_proj)
        test_db.commit()

        metrics = service.calculate_weekly_metrics(sample_user_id, week_start)

        expected_volume = (10 * 100.0) + (8 * 80.0) + (12 * 90.0)  # 2560.0
        assert metrics.total_volume == expected_volume

    def test_calculate_weekly_metrics_unique_exercises(self, test_db, sample_user_id):
        """Counts unique exercises correctly."""
        service = MetricsService(test_db)

        workout_id = uuid4()
        exercise1_id = uuid4()
        exercise2_id = uuid4()
        monday = datetime(2024, 1, 1, 10, 0, 0)
        week_start = get_week_start(monday)

        workout = WorkoutProjection(
            workout_id=workout_id,
            user_id=sample_user_id,
            started_at=monday,
            ended_at=monday + timedelta(hours=1),
            status="completed",
        )
        test_db.add(workout)
        test_db.commit()

        # Create sets with same exercise multiple times
        for exercise_id in [exercise1_id, exercise2_id, exercise1_id]:
            set_proj = SetProjection(
                set_id=uuid4(),
                workout_id=workout_id,
                exercise_id=exercise_id,
                reps=10,
                weight=100.0,
                completed_at=monday,
            )
            test_db.add(set_proj)
        test_db.commit()

        metrics = service.calculate_weekly_metrics(sample_user_id, week_start)

        assert metrics.exercises_count == 2  # Only unique exercises

    def test_calculate_weekly_metrics_week_boundaries(self, test_db, sample_user_id):
        """Only includes workouts in week range."""
        service = MetricsService(test_db)

        workout1_id = uuid4()
        workout2_id = uuid4()
        exercise_id = uuid4()

        monday = datetime(2024, 1, 1, 10, 0, 0)  # Monday
        week_start = get_week_start(monday)
        previous_sunday = monday - timedelta(days=1)  # Sunday before
        next_monday = monday + timedelta(days=7)  # Next Monday

        # Workout in previous week (should be excluded)
        workout1 = WorkoutProjection(
            workout_id=workout1_id,
            user_id=sample_user_id,
            started_at=previous_sunday,
            ended_at=previous_sunday + timedelta(hours=1),
            status="completed",
        )
        # Workout in current week (should be included)
        workout2 = WorkoutProjection(
            workout_id=workout2_id,
            user_id=sample_user_id,
            started_at=monday + timedelta(days=2),
            ended_at=monday + timedelta(days=2, hours=1),
            status="completed",
        )
        # Workout in next week (should be excluded)
        workout3 = WorkoutProjection(
            workout_id=uuid4(),
            user_id=sample_user_id,
            started_at=next_monday,
            ended_at=next_monday + timedelta(hours=1),
            status="completed",
        )

        test_db.add(workout1)
        test_db.add(workout2)
        test_db.add(workout3)
        test_db.commit()

        # Add sets only to workout2
        set_proj = SetProjection(
            set_id=uuid4(),
            workout_id=workout2_id,
            exercise_id=exercise_id,
            reps=10,
            weight=100.0,
            completed_at=monday + timedelta(days=2),
        )
        test_db.add(set_proj)
        test_db.commit()

        metrics = service.calculate_weekly_metrics(sample_user_id, week_start)

        assert metrics.total_workouts == 1  # Only workout2
        assert metrics.total_volume == 1000.0

    def test_calculate_weekly_metrics_updates_existing(self, test_db, sample_user_id):
        """Updates existing metrics record."""
        service = MetricsService(test_db)

        workout_id = uuid4()
        exercise_id = uuid4()
        monday = datetime(2024, 1, 1, 10, 0, 0)
        week_start = get_week_start(monday)

        # Create existing metrics
        existing_metrics = WeeklyMetrics(
            user_id=sample_user_id,
            week_start=week_start,
            total_workouts=1,
            total_volume=500.0,
            exercises_count=1,
        )
        test_db.add(existing_metrics)
        test_db.commit()

        # Create new workout
        workout = WorkoutProjection(
            workout_id=workout_id,
            user_id=sample_user_id,
            started_at=monday,
            ended_at=monday + timedelta(hours=1),
            status="completed",
        )
        test_db.add(workout)
        test_db.commit()

        set_proj = SetProjection(
            set_id=uuid4(),
            workout_id=workout_id,
            exercise_id=exercise_id,
            reps=10,
            weight=100.0,
            completed_at=monday,
        )
        test_db.add(set_proj)
        test_db.commit()

        metrics = service.calculate_weekly_metrics(sample_user_id, week_start)

        # Should update existing record
        assert metrics.id == existing_metrics.id
        assert metrics.total_workouts == 1
        assert metrics.total_volume == 1000.0


class TestRebuildWeeklyMetrics:
    """Tests for rebuild_weekly_metrics method."""

    def test_rebuild_weekly_metrics_multiple_weeks(self, test_db, sample_user_id):
        """Rebuilds metrics for all weeks."""
        service = MetricsService(test_db)

        # Create workouts in different weeks
        monday1 = datetime(2024, 1, 1, 10, 0, 0)  # Week 1 Monday
        monday2 = datetime(2024, 1, 8, 10, 0, 0)  # Week 2 Monday

        workout1_id = uuid4()
        workout2_id = uuid4()
        exercise_id = uuid4()

        workout1 = WorkoutProjection(
            workout_id=workout1_id,
            user_id=sample_user_id,
            started_at=monday1,
            ended_at=monday1 + timedelta(hours=1),
            status="completed",
        )
        workout2 = WorkoutProjection(
            workout_id=workout2_id,
            user_id=sample_user_id,
            started_at=monday2,
            ended_at=monday2 + timedelta(hours=1),
            status="completed",
        )
        test_db.add(workout1)
        test_db.add(workout2)
        test_db.commit()

        set1 = SetProjection(
            set_id=uuid4(),
            workout_id=workout1_id,
            exercise_id=exercise_id,
            reps=10,
            weight=100.0,
            completed_at=monday1,
        )
        set2 = SetProjection(
            set_id=uuid4(),
            workout_id=workout2_id,
            exercise_id=exercise_id,
            reps=8,
            weight=80.0,
            completed_at=monday2,
        )
        test_db.add(set1)
        test_db.add(set2)
        test_db.commit()

        service.rebuild_weekly_metrics(sample_user_id)

        # Check metrics for both weeks
        week1_metrics = (
            test_db.query(WeeklyMetrics)
            .filter(
                WeeklyMetrics.user_id == sample_user_id,
                WeeklyMetrics.week_start == get_week_start(monday1),
            )
            .first()
        )
        week2_metrics = (
            test_db.query(WeeklyMetrics)
            .filter(
                WeeklyMetrics.user_id == sample_user_id,
                WeeklyMetrics.week_start == get_week_start(monday2),
            )
            .first()
        )

        assert week1_metrics is not None
        assert week1_metrics.total_workouts == 1
        assert week1_metrics.total_volume == 1000.0

        assert week2_metrics is not None
        assert week2_metrics.total_workouts == 1
        assert week2_metrics.total_volume == 640.0

    def test_rebuild_weekly_metrics_updates_existing(self, test_db, sample_user_id):
        """Updates existing metrics records."""
        service = MetricsService(test_db)

        workout_id = uuid4()
        exercise_id = uuid4()
        monday = datetime(2024, 1, 1, 10, 0, 0)
        week_start = get_week_start(monday)

        # Create existing metrics
        existing_metrics = WeeklyMetrics(
            user_id=sample_user_id,
            week_start=week_start,
            total_workouts=0,
            total_volume=0.0,
            exercises_count=0,
        )
        test_db.add(existing_metrics)
        test_db.commit()

        # Create workout
        workout = WorkoutProjection(
            workout_id=workout_id,
            user_id=sample_user_id,
            started_at=monday,
            ended_at=monday + timedelta(hours=1),
            status="completed",
        )
        test_db.add(workout)
        test_db.commit()

        set_proj = SetProjection(
            set_id=uuid4(),
            workout_id=workout_id,
            exercise_id=exercise_id,
            reps=10,
            weight=100.0,
            completed_at=monday,
        )
        test_db.add(set_proj)
        test_db.commit()

        service.rebuild_weekly_metrics(sample_user_id)

        # Should update existing record
        updated_metrics = (
            test_db.query(WeeklyMetrics)
            .filter(
                WeeklyMetrics.user_id == sample_user_id,
                WeeklyMetrics.week_start == week_start,
            )
            .first()
        )

        assert updated_metrics.id == existing_metrics.id
        assert updated_metrics.total_workouts == 1
        assert updated_metrics.total_volume == 1000.0


class TestGetWeeklyMetrics:
    """Tests for get_weekly_metrics method."""

    def test_get_weekly_metrics_current_week(self, test_db, sample_user_id):
        """Returns current week metrics."""
        service = MetricsService(test_db)

        workout_id = uuid4()
        exercise_id = uuid4()
        monday = datetime(2024, 1, 1, 10, 0, 0)
        week_start = get_week_start(monday)

        # Create metrics
        metrics = WeeklyMetrics(
            user_id=sample_user_id,
            week_start=week_start,
            total_workouts=1,
            total_volume=1000.0,
            exercises_count=1,
        )
        test_db.add(metrics)
        test_db.commit()

        # Mock current week to be the same
        result = service.get_weekly_metrics(sample_user_id, week_start)

        assert result is not None
        assert result.user_id == sample_user_id
        assert result.week_start == week_start

    def test_get_weekly_metrics_specific_week(self, test_db, sample_user_id):
        """Returns specific week metrics."""
        service = MetricsService(test_db)

        monday = datetime(2024, 1, 1, 10, 0, 0)
        week_start = get_week_start(monday)

        metrics = WeeklyMetrics(
            user_id=sample_user_id,
            week_start=week_start,
            total_workouts=2,
            total_volume=2000.0,
            exercises_count=2,
        )
        test_db.add(metrics)
        test_db.commit()

        result = service.get_weekly_metrics(sample_user_id, week_start)

        assert result is not None
        assert result.total_workouts == 2

    def test_get_weekly_metrics_not_found(self, test_db, sample_user_id):
        """Returns None when no metrics exist."""
        service = MetricsService(test_db)

        monday = datetime(2024, 1, 1, 10, 0, 0)
        week_start = get_week_start(monday)

        result = service.get_weekly_metrics(sample_user_id, week_start)

        assert result is None

