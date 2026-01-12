"""
Event domain models and payload schemas.

Defines canonical event types and their strict payload schemas.
All events must have: event_id (UUID, client-generated), user_id, device_id,
event_type, payload (JSON), sequence_number (per device), created_at.

Ordering rules:
- sequence_number must be monotonic per device
- Gaps are allowed (e.g., 1, 2, 5, 6 is valid)
- Reordering is NOT allowed (e.g., 1, 3, 2 is invalid)
"""

from enum import Enum
from typing import Optional
from uuid import UUID
from datetime import datetime
from pydantic import BaseModel, Field


class EventType(str, Enum):
    """Canonical event types for workout tracking."""

    WORKOUT_STARTED = "WorkoutStarted"
    WORKOUT_ENDED = "WorkoutEnded"
    EXERCISE_ADDED = "ExerciseAdded"
    SET_COMPLETED = "SetCompleted"


# Event Payload Schemas


class WorkoutStartedPayload(BaseModel):
    """Payload for WorkoutStarted event."""

    workout_id: UUID = Field(..., description="Unique workout identifier")
    started_at: datetime = Field(..., description="Workout start timestamp")


class WorkoutEndedPayload(BaseModel):
    """Payload for WorkoutEnded event."""

    workout_id: UUID = Field(..., description="Unique workout identifier")
    ended_at: datetime = Field(..., description="Workout end timestamp")


class ExerciseAddedPayload(BaseModel):
    """Payload for ExerciseAdded event."""

    workout_id: UUID = Field(..., description="Unique workout identifier")
    exercise_id: UUID = Field(..., description="Unique exercise identifier")
    exercise_name: str = Field(..., description="Name of the exercise")


class SetCompletedPayload(BaseModel):
    """Payload for SetCompleted event."""

    workout_id: UUID = Field(..., description="Unique workout identifier")
    exercise_id: UUID = Field(..., description="Unique exercise identifier")
    set_id: UUID = Field(..., description="Unique set identifier")
    reps: int = Field(..., gt=0, description="Number of repetitions")
    weight: float = Field(..., gt=0, description="Weight lifted (in kg)")
    completed_at: datetime = Field(..., description="Set completion timestamp")


# Event payload mapping
EVENT_PAYLOAD_SCHEMAS = {
    EventType.WORKOUT_STARTED: WorkoutStartedPayload,
    EventType.WORKOUT_ENDED: WorkoutEndedPayload,
    EventType.EXERCISE_ADDED: ExerciseAddedPayload,
    EventType.SET_COMPLETED: SetCompletedPayload,
}


# This function validates the event payload against its schema
def validate_event_payload(event_type: str, payload: dict) -> BaseModel:
    """
    Validate event payload against its schema.

    Args:
        event_type: The event type string
        payload: The payload dictionary to validate

    Returns:
        Validated Pydantic model instance

    Raises:
        ValueError: If event_type is unknown or payload is invalid
    """
    try:
        event_type_enum = EventType(event_type)
    except ValueError:
        raise ValueError(f"Unknown event type: {event_type}")

    schema_class = EVENT_PAYLOAD_SCHEMAS.get(event_type_enum)
    if not schema_class:
        raise ValueError(f"No schema defined for event type: {event_type}")

    return schema_class(**payload)
