"""
Integration tests for measurements endpoints.

Tests measurement creation, retrieval with authentication and validation.
"""

from fastapi.testclient import TestClient
from app.main import app
from app.db.database import get_db
from app.models.user import User
from app.utils.jwt import create_access_token
from app.utils.password import hash_password
from datetime import datetime, timezone, timedelta


def get_auth_headers(user_id):
    """Helper to create auth headers."""
    token = create_access_token(user_id)
    return {"Authorization": f"Bearer {token}"}


class TestCreateMeasurement:
    """Tests for POST /api/v1/measurements endpoint."""

    def test_create_measurement_authenticated(self, test_db, override_get_db, sample_user_id):
        """Authenticated user can create measurement."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            # Create user with gender
            user = User(
                user_id=sample_user_id,
                email="test@example.com",
                gender="male",
                is_anonymous=False,
            )
            test_db.add(user)
            test_db.commit()

            client = TestClient(app)
            response = client.post(
                "/api/v1/measurements",
                headers=get_auth_headers(sample_user_id),
                json={
                    "measured_at": datetime.now(timezone.utc).isoformat(),
                    "height_cm": 180.0,
                    "weight_kg": 80.0,
                    "neck_cm": 40.0,
                    "waist_cm": 90.0,
                },
            )

            assert response.status_code == 201
            data = response.json()
            assert "measurement_id" in data
            assert data["body_fat_percentage"] is not None
            assert data["fat_mass_kg"] is not None
            assert data["lean_mass_kg"] is not None
        finally:
            app.dependency_overrides.clear()

    def test_create_measurement_unauthenticated(self, test_db, override_get_db):
        """Returns 401 without token."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            client = TestClient(app)
            response = client.post(
                "/api/v1/measurements",
                json={
                    "measured_at": datetime.now(timezone.utc).isoformat(),
                    "height_cm": 180.0,
                    "weight_kg": 80.0,
                    "neck_cm": 40.0,
                    "waist_cm": 90.0,
                },
            )

            assert response.status_code == 401
        finally:
            app.dependency_overrides.clear()

    def test_create_measurement_auto_calculates_metrics(self, test_db, override_get_db, sample_user_id):
        """BFP, fat mass, lean mass calculated."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            user = User(
                user_id=sample_user_id,
                email="test@example.com",
                gender="male",
                is_anonymous=False,
            )
            test_db.add(user)
            test_db.commit()

            client = TestClient(app)
            response = client.post(
                "/api/v1/measurements",
                headers=get_auth_headers(sample_user_id),
                json={
                    "measured_at": datetime.now(timezone.utc).isoformat(),
                    "height_cm": 180.0,
                    "weight_kg": 80.0,
                    "neck_cm": 40.0,
                    "waist_cm": 90.0,
                },
            )

            assert response.status_code == 201
            data = response.json()
            assert data["body_fat_percentage"] is not None
            assert 0 <= data["body_fat_percentage"] <= 50
            assert data["fat_mass_kg"] > 0
            assert data["lean_mass_kg"] > 0
        finally:
            app.dependency_overrides.clear()

    def test_create_measurement_invalid_data(self, test_db, override_get_db, sample_user_id):
        """Returns 400 for invalid measurements."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            user = User(
                user_id=sample_user_id,
                email="test@example.com",
                gender="male",
                is_anonymous=False,
            )
            test_db.add(user)
            test_db.commit()

            client = TestClient(app)
            response = client.post(
                "/api/v1/measurements",
                headers=get_auth_headers(sample_user_id),
                json={
                    "measured_at": datetime.now(timezone.utc).isoformat(),
                    "height_cm": -180.0,  # Invalid
                    "weight_kg": 80.0,
                    "neck_cm": 40.0,
                    "waist_cm": 90.0,
                },
            )

            assert response.status_code == 400
        finally:
            app.dependency_overrides.clear()


class TestGetMeasurements:
    """Tests for GET /api/v1/measurements endpoint."""

    def test_get_measurements_authenticated(self, test_db, override_get_db, sample_user_id):
        """Returns user's measurements."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            user = User(
                user_id=sample_user_id,
                email="test@example.com",
                gender="male",
                is_anonymous=False,
            )
            test_db.add(user)
            test_db.commit()

            # Create a measurement via service
            from app.services.body_measurement_service import BodyMeasurementService
            service = BodyMeasurementService(test_db)
            service.create_measurement(
                user_id=sample_user_id,
                measured_at=datetime.now(timezone.utc),
                height_cm=180.0,
                weight_kg=80.0,
                neck_cm=40.0,
                waist_cm=90.0,
            )

            client = TestClient(app)
            response = client.get(
                "/api/v1/measurements",
                headers=get_auth_headers(sample_user_id),
            )

            assert response.status_code == 200
            data = response.json()
            assert isinstance(data, list)
            assert len(data) == 1
        finally:
            app.dependency_overrides.clear()

    def test_get_measurements_ordered(self, test_db, override_get_db, sample_user_id):
        """Measurements returned in date order."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            user = User(
                user_id=sample_user_id,
                email="test@example.com",
                gender="male",
                is_anonymous=False,
            )
            test_db.add(user)
            test_db.commit()

            from app.services.body_measurement_service import BodyMeasurementService
            service = BodyMeasurementService(test_db)
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

            client = TestClient(app)
            response = client.get(
                "/api/v1/measurements",
                headers=get_auth_headers(sample_user_id),
            )

            assert response.status_code == 200
            data = response.json()
            assert len(data) == 3
            # Should be ordered newest first
            assert data[0]["measured_at"] > data[1]["measured_at"]
        finally:
            app.dependency_overrides.clear()

