"""
FastAPI application entry point.
"""

from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi
from app.api.v1 import (
    sync,
    projections,
    auth,
    users,
    workouts,
    metrics,
    reports,
    exercises,
    ai,
    measurements,
)

app = FastAPI(
    title="Hypertrophy Workout API",
    description="Event-driven workout tracking API",
    version="1.0.0",
    docs_url="/docs",  # Swagger UI at /docs
    redoc_url="/redoc",  # ReDoc at /redoc
    openapi_url="/openapi.json",  # OpenAPI JSON schema
)


def custom_openapi():
    """Custom OpenAPI schema with security schemes."""
    if app.openapi_schema:
        return app.openapi_schema

    openapi_schema = get_openapi(
        title=app.title,
        version=app.version,
        description=app.description,
        routes=app.routes,
    )

    openapi_schema["components"]["securitySchemes"] = {
        "Bearer": {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT",
            "description": "Enter your JWT token. Get it from /api/v1/auth/login endpoint.",
        }
    }

    app.openapi_schema = openapi_schema
    return app.openapi_schema


app.openapi = custom_openapi

app.include_router(sync.router, prefix="/api/v1", tags=["sync"])
app.include_router(projections.router, prefix="/api/v1", tags=["projections"])
app.include_router(auth.router, prefix="/api/v1/auth", tags=["auth"])
app.include_router(users.router, prefix="/api/v1/users", tags=["users"])
app.include_router(workouts.router, prefix="/api/v1", tags=["workouts"])
app.include_router(metrics.router, prefix="/api/v1", tags=["metrics"])
app.include_router(reports.router, prefix="/api/v1", tags=["reports"])
app.include_router(exercises.router, prefix="/api/v1", tags=["exercises"])
app.include_router(ai.router, prefix="/api/v1", tags=["ai"])
app.include_router(measurements.router, prefix="/api/v1", tags=["measurements"])


@app.get("/")
async def root():
    """Root endpoint."""
    return {"message": "Hypertrophy Workout API"}


@app.get("/health")
def health():
    """Health check endpoint."""
    return {"status": "ok"}
