"""
Integration tests for authentication endpoints.

Tests register and login endpoints with success and error cases.
"""

from fastapi.testclient import TestClient
from app.main import app
from app.db.database import get_db
from app.models.user import User
from app.utils.password import hash_password


class TestRegisterEndpoint:
    """Tests for POST /api/v1/auth/register endpoint."""

    def test_register_success(self, test_db, override_get_db):
        """Successful registration returns token and user_id."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            client = TestClient(app)
            response = client.post(
                "/api/v1/auth/register",
                json={
                    "email": "newuser@example.com",
                    "password": "password123",
                },
            )

            assert response.status_code == 201
            data = response.json()
            assert "user_id" in data
            assert "token" in data
            assert data["is_anonymous"] is False

            # Verify user was created in database
            user = test_db.query(User).filter(User.email == "newuser@example.com").first()
            assert user is not None
            assert user.email == "newuser@example.com"
            assert user.is_anonymous is False
        finally:
            app.dependency_overrides.clear()

    def test_register_duplicate_email(self, test_db, override_get_db):
        """Returns 400 for duplicate email."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            # Create existing user
            existing_user = User(
                email="existing@example.com",
                password_hash=hash_password("password123"),
                is_anonymous=False,
            )
            test_db.add(existing_user)
            test_db.commit()

            client = TestClient(app)
            response = client.post(
                "/api/v1/auth/register",
                json={
                    "email": "existing@example.com",
                    "password": "password123",
                },
            )

            assert response.status_code == 400
            assert "already registered" in response.json()["detail"].lower()
        finally:
            app.dependency_overrides.clear()

    def test_register_invalid_email(self, test_db, override_get_db):
        """Returns 422 for invalid email format."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            client = TestClient(app)
            response = client.post(
                "/api/v1/auth/register",
                json={
                    "email": "not-an-email",
                    "password": "password123",
                },
            )

            assert response.status_code == 422
        finally:
            app.dependency_overrides.clear()

    def test_register_short_password(self, test_db, override_get_db):
        """Returns 422 for password < 8 chars."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            client = TestClient(app)
            response = client.post(
                "/api/v1/auth/register",
                json={
                    "email": "user@example.com",
                    "password": "short",
                },
            )

            assert response.status_code == 422
        finally:
            app.dependency_overrides.clear()

    def test_register_long_password(self, test_db, override_get_db):
        """Returns 422 for password > 72 chars."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            long_password = "a" * 73
            client = TestClient(app)
            response = client.post(
                "/api/v1/auth/register",
                json={
                    "email": "user@example.com",
                    "password": long_password,
                },
            )

            assert response.status_code == 422
        finally:
            app.dependency_overrides.clear()

    def test_register_missing_fields(self, test_db, override_get_db):
        """Returns 422 for missing required fields."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            client = TestClient(app)
            response = client.post(
                "/api/v1/auth/register",
                json={
                    "email": "user@example.com",
                },
            )

            assert response.status_code == 422

            response = client.post(
                "/api/v1/auth/register",
                json={
                    "password": "password123",
                },
            )

            assert response.status_code == 422
        finally:
            app.dependency_overrides.clear()


class TestLoginEndpoint:
    """Tests for POST /api/v1/auth/login endpoint."""

    def test_login_success(self, test_db, override_get_db):
        """Successful login returns token."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            # Create user
            user = User(
                email="loginuser@example.com",
                password_hash=hash_password("password123"),
                is_anonymous=False,
            )
            test_db.add(user)
            test_db.commit()

            client = TestClient(app)
            response = client.post(
                "/api/v1/auth/login",
                json={
                    "email": "loginuser@example.com",
                    "password": "password123",
                },
            )

            assert response.status_code == 200
            data = response.json()
            assert "user_id" in data
            assert "token" in data
            assert data["user_id"] == str(user.user_id)
        finally:
            app.dependency_overrides.clear()

    def test_login_invalid_email(self, test_db, override_get_db):
        """Returns 401 for non-existent email."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            client = TestClient(app)
            response = client.post(
                "/api/v1/auth/login",
                json={
                    "email": "nonexistent@example.com",
                    "password": "password123",
                },
            )

            assert response.status_code == 401
            assert "invalid" in response.json()["detail"].lower()
        finally:
            app.dependency_overrides.clear()

    def test_login_wrong_password(self, test_db, override_get_db):
        """Returns 401 for incorrect password."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            # Create user
            user = User(
                email="wrongpass@example.com",
                password_hash=hash_password("correctpassword"),
                is_anonymous=False,
            )
            test_db.add(user)
            test_db.commit()

            client = TestClient(app)
            response = client.post(
                "/api/v1/auth/login",
                json={
                    "email": "wrongpass@example.com",
                    "password": "wrongpassword",
                },
            )

            assert response.status_code == 401
            assert "invalid" in response.json()["detail"].lower()
        finally:
            app.dependency_overrides.clear()

    def test_login_invalid_credentials_message(self, test_db, override_get_db):
        """Error message doesn't reveal which field is wrong."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            client = TestClient(app)
            # Test with wrong email
            response1 = client.post(
                "/api/v1/auth/login",
                json={
                    "email": "nonexistent@example.com",
                    "password": "password123",
                },
            )

            # Test with wrong password
            user = User(
                email="testuser@example.com",
                password_hash=hash_password("correctpassword"),
                is_anonymous=False,
            )
            test_db.add(user)
            test_db.commit()

            response2 = client.post(
                "/api/v1/auth/login",
                json={
                    "email": "testuser@example.com",
                    "password": "wrongpassword",
                },
            )

            # Both should return same generic message
            assert response1.status_code == 401
            assert response2.status_code == 401
            assert response1.json()["detail"] == response2.json()["detail"]
        finally:
            app.dependency_overrides.clear()

    def test_login_missing_fields(self, test_db, override_get_db):
        """Returns 422 for missing required fields."""
        app.dependency_overrides[get_db] = override_get_db
        try:
            client = TestClient(app)
            response = client.post(
                "/api/v1/auth/login",
                json={
                    "email": "user@example.com",
                },
            )

            assert response.status_code == 422

            response = client.post(
                "/api/v1/auth/login",
                json={
                    "password": "password123",
                },
            )

            assert response.status_code == 422
        finally:
            app.dependency_overrides.clear()
