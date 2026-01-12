"""
Pytest configuration and fixtures for integration tests.
"""

import os
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.database import Base

# Import models to register with Base.metadata
from app.models import events, projections, user  # noqa: F401


# Use test database URL from env, or default to SQLite in-memory
TEST_DATABASE_URL = os.getenv("TEST_DATABASE_URL", "sqlite:///:memory:")


@pytest.fixture(scope="function")
def test_engine():
    """Create a test database engine."""
    if TEST_DATABASE_URL.startswith("sqlite"):
        # SQLite in-memory for fast tests
        engine = create_engine(
            TEST_DATABASE_URL,
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
            echo=False,
        )
    else:
        # Postgres for more realistic integration tests
        engine = create_engine(TEST_DATABASE_URL, echo=False)

    # Create all tables
    Base.metadata.create_all(bind=engine)

    yield engine

    # Drop all tables after test
    Base.metadata.drop_all(bind=engine)
    engine.dispose()


@pytest.fixture(scope="function")
def test_db(test_engine):
    """Create a test database session."""
    TestSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=test_engine)
    session = TestSessionLocal()

    try:
        yield session
    finally:
        session.close()


@pytest.fixture(scope="function")
def override_get_db(test_db):
    """Override get_db dependency for FastAPI."""

    def _get_db():
        try:
            yield test_db
        finally:
            pass  # Don't close, we'll handle it in fixture

    return _get_db


@pytest.fixture
def sample_user_id():
    """Sample user ID for tests."""
    from uuid import uuid4

    return uuid4()


@pytest.fixture
def sample_device_id():
    """Sample device ID for tests."""
    from uuid import uuid4

    return uuid4()
