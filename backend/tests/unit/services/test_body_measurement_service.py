"""
Unit tests for BodyMeasurementService.

Tests measurement creation, retrieval, and automatic calculations.
"""

from uuid import uuid4
from datetime import datetime, timezone, timedelta
import pytest

from app.services.body_measurement_service import BodyMeasurementService
from app.models.body_measurement import BodyMeasurement
from app.models.user import User


class TestCreateMeasurement:
    """Tests for create_measurement method."""

    def test_create_measurement_valid(self, test_db, sample_user_id):
        """Creates measurement with all fields."""
        # Create user with gender
        user = User(
            user_id=sample_user_id,
            email="test@example.com",
            gender="male",
            is_anonymous=False,
        )
        test_db.add(user)
        test_db.commit()

        service = BodyMeasurementService(test_db)

        measured_at = datetime.now(timezone.utc)
        measurement = service.create_measurement(
            user_id=sample_user_id,
            measured_at=measured_at,
            height_cm=180.0,
            weight_kg=80.0,
            neck_cm=40.0,
            waist_cm=90.0,
            chest_cm=100.0,
            shoulder_cm=110.0,
            bicep_cm=35.0,
            forearm_cm=28.0,
            thigh_cm=60.0,
            calf_cm=38.0,
        )

        assert measurement.user_id == sample_user_id
        assert measurement.height_cm == 180.0
        assert measurement.weight_kg == 80.0
        assert measurement.neck_cm == 40.0
        assert measurement.waist_cm == 90.0
        assert measurement.chest_cm == 100.0
        assert measurement.body_fat_percentage is not None
        assert measurement.fat_mass_kg is not None
        assert measurement.lean_mass_kg is not None

    def test_create_measurement_calculates_bfp(self, test_db, sample_user_id):
        """Automatically calculates body fat."""
        user = User(
            user_id=sample_user_id,
            email="test@example.com",
            gender="male",
            is_anonymous=False,
        )
        test_db.add(user)
        test_db.commit()

        service = BodyMeasurementService(test_db)

        measurement = service.create_measurement(
            user_id=sample_user_id,
            measured_at=datetime.now(timezone.utc),
            height_cm=180.0,
            weight_kg=80.0,
            neck_cm=40.0,
            waist_cm=90.0,
        )

        assert measurement.body_fat_percentage is not None
        assert 0 <= measurement.body_fat_percentage <= 50

    def test_create_measurement_calculates_fat_mass(self, test_db, sample_user_id):
        """Calculates fat mass correctly."""
        user = User(
            user_id=sample_user_id,
            email="test@example.com",
            gender="male",
            is_anonymous=False,
        )
        test_db.add(user)
        test_db.commit()

        service = BodyMeasurementService(test_db)

        measurement = service.create_measurement(
            user_id=sample_user_id,
            measured_at=datetime.now(timezone.utc),
            height_cm=180.0,
            weight_kg=80.0,
            neck_cm=40.0,
            waist_cm=90.0,
        )

        assert measurement.fat_mass_kg is not None
        assert measurement.fat_mass_kg == pytest.approx(
            80.0 * (measurement.body_fat_percentage / 100.0), abs=0.01
        )

    def test_create_measurement_calculates_lean_mass(self, test_db, sample_user_id):
        """Calculates lean mass correctly."""
        user = User(
            user_id=sample_user_id,
            email="test@example.com",
            gender="male",
            is_anonymous=False,
        )
        test_db.add(user)
        test_db.commit()

        service = BodyMeasurementService(test_db)

        measurement = service.create_measurement(
            user_id=sample_user_id,
            measured_at=datetime.now(timezone.utc),
            height_cm=180.0,
            weight_kg=80.0,
            neck_cm=40.0,
            waist_cm=90.0,
        )

        assert measurement.lean_mass_kg is not None
        assert measurement.lean_mass_kg == pytest.approx(
            80.0 - measurement.fat_mass_kg, abs=0.01
        )

    def test_create_measurement_female_requires_hip(self, test_db, sample_user_id):
        """Female measurements require hip."""
        user = User(
            user_id=sample_user_id,
            email="test@example.com",
            gender="female",
            is_anonymous=False,
        )
        test_db.add(user)
        test_db.commit()

        service = BodyMeasurementService(test_db)

        with pytest.raises(ValueError, match="Hip measurement is required for women"):
            service.create_measurement(
                user_id=sample_user_id,
                measured_at=datetime.now(timezone.utc),
                height_cm=165.0,
                weight_kg=60.0,
                neck_cm=35.0,
                waist_cm=75.0,
                hip_cm=None,
            )

    def test_create_measurement_female_with_hip(self, test_db, sample_user_id):
        """Female measurements work with hip."""
        user = User(
            user_id=sample_user_id,
            email="test@example.com",
            gender="female",
            is_anonymous=False,
        )
        test_db.add(user)
        test_db.commit()

        service = BodyMeasurementService(test_db)

        measurement = service.create_measurement(
            user_id=sample_user_id,
            measured_at=datetime.now(timezone.utc),
            height_cm=165.0,
            weight_kg=60.0,
            neck_cm=35.0,
            waist_cm=75.0,
            hip_cm=95.0,
        )

        assert measurement.hip_cm == 95.0
        assert measurement.body_fat_percentage is not None

    def test_create_measurement_invalid_measurements(self, test_db, sample_user_id):
        """Raises ValueError for invalid inputs."""
        user = User(
            user_id=sample_user_id,
            email="test@example.com",
            gender="male",
            is_anonymous=False,
        )
        test_db.add(user)
        test_db.commit()

        service = BodyMeasurementService(test_db)

        with pytest.raises(ValueError, match="must be positive"):
            service.create_measurement(
                user_id=sample_user_id,
                measured_at=datetime.now(timezone.utc),
                height_cm=-180.0,
                weight_kg=80.0,
                neck_cm=40.0,
                waist_cm=90.0,
            )

        with pytest.raises(ValueError, match="Waist must be greater than neck"):
            service.create_measurement(
                user_id=sample_user_id,
                measured_at=datetime.now(timezone.utc),
                height_cm=180.0,
                weight_kg=80.0,
                neck_cm=90.0,
                waist_cm=40.0,
            )

    def test_create_measurement_user_not_found(self, test_db):
        """Raises ValueError when user not found."""
        service = BodyMeasurementService(test_db)
        non_existent_user_id = uuid4()

        with pytest.raises(ValueError, match="not found"):
            service.create_measurement(
                user_id=non_existent_user_id,
                measured_at=datetime.now(timezone.utc),
                height_cm=180.0,
                weight_kg=80.0,
                neck_cm=40.0,
                waist_cm=90.0,
            )

    def test_create_measurement_user_no_gender(self, test_db, sample_user_id):
        """Raises ValueError when user has no gender."""
        user = User(
            user_id=sample_user_id,
            email="test@example.com",
            gender=None,
            is_anonymous=False,
        )
        test_db.add(user)
        test_db.commit()

        service = BodyMeasurementService(test_db)

        with pytest.raises(ValueError, match="User gender must be set"):
            service.create_measurement(
                user_id=sample_user_id,
                measured_at=datetime.now(timezone.utc),
                height_cm=180.0,
                weight_kg=80.0,
                neck_cm=40.0,
                waist_cm=90.0,
            )


class TestGetMeasurements:
    """Tests for get_measurements method."""

    def test_get_measurements_for_user(self, test_db, sample_user_id):
        """Returns all measurements for user."""
        user = User(
            user_id=sample_user_id,
            email="test@example.com",
            gender="male",
            is_anonymous=False,
        )
        test_db.add(user)
        test_db.commit()

        service = BodyMeasurementService(test_db)

        # Create multiple measurements
        for i in range(3):
            service.create_measurement(
                user_id=sample_user_id,
                measured_at=datetime.now(timezone.utc),
                height_cm=180.0 + i,
                weight_kg=80.0 + i,
                neck_cm=40.0,
                waist_cm=90.0,
            )

        measurements = service.get_measurements(sample_user_id)

        assert len(measurements) == 3
        assert all(m.user_id == sample_user_id for m in measurements)

    def test_get_measurements_ordered_by_date(self, test_db, sample_user_id):
        """Returns measurements in date order (newest first)."""
        user = User(
            user_id=sample_user_id,
            email="test@example.com",
            gender="male",
            is_anonymous=False,
        )
        test_db.add(user)
        test_db.commit()

        service = BodyMeasurementService(test_db)

        # Create measurements with different dates
        base_time = datetime.now(timezone.utc)
        for i in range(3):
            service.create_measurement(
                user_id=sample_user_id,
                measured_at=base_time - timedelta(days=i),
                height_cm=180.0,
                weight_kg=80.0,
                neck_cm=40.0,
                waist_cm=90.0,
            )

        measurements = service.get_measurements(sample_user_id)

        assert len(measurements) == 3
        # Should be ordered newest first
        assert measurements[0].measured_at > measurements[1].measured_at
        assert measurements[1].measured_at > measurements[2].measured_at

    def test_get_measurements_with_limit(self, test_db, sample_user_id):
        """Respects limit parameter."""
        user = User(
            user_id=sample_user_id,
            email="test@example.com",
            gender="male",
            is_anonymous=False,
        )
        test_db.add(user)
        test_db.commit()

        service = BodyMeasurementService(test_db)

        # Create 5 measurements
        for i in range(5):
            service.create_measurement(
                user_id=sample_user_id,
                measured_at=datetime.now(timezone.utc),
                height_cm=180.0,
                weight_kg=80.0,
                neck_cm=40.0,
                waist_cm=90.0,
            )

        measurements = service.get_measurements(sample_user_id, limit=3)

        assert len(measurements) == 3

    def test_get_measurements_empty(self, test_db, sample_user_id):
        """Returns empty list when no measurements."""
        service = BodyMeasurementService(test_db)

        measurements = service.get_measurements(sample_user_id)

        assert measurements == []


class TestGetLatestMeasurement:
    """Tests for get_latest_measurement method."""

    def test_get_latest_measurement_returns_newest(self, test_db, sample_user_id):
        """Returns most recent measurement."""
        user = User(
            user_id=sample_user_id,
            email="test@example.com",
            gender="male",
            is_anonymous=False,
        )
        test_db.add(user)
        test_db.commit()

        service = BodyMeasurementService(test_db)

        base_time = datetime.now(timezone.utc)
        # Create older measurement
        service.create_measurement(
            user_id=sample_user_id,
            measured_at=base_time - timedelta(days=10),
            height_cm=180.0,
            weight_kg=80.0,
            neck_cm=40.0,
            waist_cm=90.0,
        )

        # Create newer measurement
        latest = service.create_measurement(
            user_id=sample_user_id,
            measured_at=base_time,
            height_cm=185.0,
            weight_kg=85.0,
            neck_cm=40.0,
            waist_cm=90.0,
        )

        result = service.get_latest_measurement(sample_user_id)

        assert result is not None
        assert result.measurement_id == latest.measurement_id
        assert result.height_cm == 185.0

    def test_get_latest_measurement_none(self, test_db, sample_user_id):
        """Returns None when no measurements."""
        service = BodyMeasurementService(test_db)

        result = service.get_latest_measurement(sample_user_id)

        assert result is None


class TestGetMeasurement:
    """Tests for get_measurement method."""

    def test_get_measurement_by_id(self, test_db, sample_user_id):
        """Returns specific measurement by ID."""
        user = User(
            user_id=sample_user_id,
            email="test@example.com",
            gender="male",
            is_anonymous=False,
        )
        test_db.add(user)
        test_db.commit()

        service = BodyMeasurementService(test_db)

        measurement = service.create_measurement(
            user_id=sample_user_id,
            measured_at=datetime.now(timezone.utc),
            height_cm=180.0,
            weight_kg=80.0,
            neck_cm=40.0,
            waist_cm=90.0,
        )

        result = service.get_measurement(measurement.measurement_id, sample_user_id)

        assert result is not None
        assert result.measurement_id == measurement.measurement_id

    def test_get_measurement_not_found(self, test_db, sample_user_id):
        """Returns None when measurement not found."""
        service = BodyMeasurementService(test_db)
        non_existent_id = uuid4()

        result = service.get_measurement(non_existent_id, sample_user_id)

        assert result is None

    def test_get_measurement_wrong_user(self, test_db, sample_user_id):
        """Returns None when measurement belongs to different user."""
        user = User(
            user_id=sample_user_id,
            email="test@example.com",
            gender="male",
            is_anonymous=False,
        )
        test_db.add(user)
        test_db.commit()

        service = BodyMeasurementService(test_db)

        measurement = service.create_measurement(
            user_id=sample_user_id,
            measured_at=datetime.now(timezone.utc),
            height_cm=180.0,
            weight_kg=80.0,
            neck_cm=40.0,
            waist_cm=90.0,
        )

        other_user_id = uuid4()
        result = service.get_measurement(measurement.measurement_id, other_user_id)

        assert result is None

