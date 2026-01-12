"""
Smoke tests for health checks and critical endpoint availability.

Quick tests to verify basic functionality.
"""

from fastapi.testclient import TestClient
from app.main import app


class TestHealthChecks:
    """Tests for health check endpoints."""

    def test_health_endpoint(self):
        """`/health` returns 200."""
        client = TestClient(app)
        response = client.get("/health")
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}

    def test_root_endpoint(self):
        """`/` returns API message."""
        client = TestClient(app)
        response = client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert "message" in data
        assert "Hypertrophy" in data["message"]

    def test_critical_endpoints_respond(self):
        """Key endpoints return expected status codes."""
        client = TestClient(app)
        # Health check
        response = client.get("/health")
        assert response.status_code == 200

        # Root
        response = client.get("/")
        assert response.status_code == 200

        # OpenAPI schema
        response = client.get("/openapi.json")
        assert response.status_code == 200
