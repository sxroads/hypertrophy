"""
POST /api/v1/sync endpoint for idempotent event ingestion.
"""

import traceback
from typing import List
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.services.sync_service import SyncService
from app.utils.auth import get_optional_user_id


router = APIRouter()


class EventRequest(BaseModel):
    """Single event in sync request."""

    event_id: UUID = Field(..., description="Client-generated UUID for idempotency")
    event_type: str = Field(
        ..., description="Event type (WorkoutStarted, WorkoutEnded, etc.)"
    )
    payload: dict = Field(..., description="Event payload (validated against schema)")
    sequence_number: int = Field(
        ..., gt=0, description="Monotonic sequence number per device"
    )


class SyncRequest(BaseModel):
    """Sync request payload."""

    device_id: UUID = Field(..., description="Device identifier")
    user_id: UUID = Field(..., description="User identifier (anonymous or real)")
    events: List[EventRequest] = Field(
        ..., min_length=1, description="List of events to sync"
    )


class AckCursor(BaseModel):
    """Acknowledgment cursor."""

    device_id: UUID
    last_acked_sequence: int


class SyncResponse(BaseModel):
    """Sync response."""

    ack_cursor: AckCursor
    accepted_count: int
    rejected_count: int
    rejected_event_ids: List[UUID] = Field(default_factory=list)


@router.post("/sync", response_model=SyncResponse, status_code=status.HTTP_200_OK)
async def sync_events(
    request: SyncRequest,
    db: Session = Depends(get_db),
    authenticated_user_id: UUID | None = Depends(get_optional_user_id),
):
    """
    Idempotent event sync endpoint.

    Accepts a batch of events and persists them with:
    - event_id uniqueness (idempotency)
    - (device_id, sequence_number) ordering
    - Transactional writes
    - Partial batch success handling
    - Ownership validation (if authenticated)

    Returns ack cursor with last accepted sequence number.

    Supports both anonymous and authenticated users:
    - Anonymous: No token required, user_id in request is used
    - Authenticated: Token required, user_id in request must match token
    """
    # Ownership validation: if authenticated, user_id must match token
    if authenticated_user_id is not None:
        if request.user_id != authenticated_user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="user_id in request does not match authenticated user",
            )

    # Validate required fields
    if not request.device_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="device_id is required",
        )
    if not request.user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="user_id is required",
        )
    if not request.events:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="events list cannot be empty",
        )

    # Validate monotonic sequence_number per device
    # Sequence numbers must be strictly increasing to maintain event ordering
    # Gaps are allowed (e.g., 1, 2, 5, 6) but reordering is not (e.g., 1, 3, 2)
    # This ensures events are processed in the correct order for projections
    sequence_numbers = [e.sequence_number for e in request.events]
    if sequence_numbers != sorted(set(sequence_numbers)):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="sequence_number must be monotonic per device (gaps allowed, reordering not allowed)",
        )

    # Convert to dict format for service
    events_dict = [
        {
            "event_id": str(e.event_id),
            "event_type": e.event_type,
            "payload": e.payload,
            "sequence_number": e.sequence_number,
        }
        for e in request.events
    ]

    # Process sync
    sync_service = SyncService(db)
    try:
        result = sync_service.sync_events(
            device_id=request.device_id,
            user_id=request.user_id,
            events=events_dict,
        )
    except Exception as e:
        # Log full traceback for debugging
        error_traceback = traceback.format_exc()
        print(f"[SYNC] ❌ ERROR: Sync failed: {e}")
        print(error_traceback)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Sync failed: {str(e)}",
        )

    # Build response
    if result.last_acked_sequence is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No events were accepted",
        )

    return SyncResponse(
        ack_cursor=AckCursor(
            device_id=request.device_id,
            last_acked_sequence=result.last_acked_sequence,
        ),
        accepted_count=result.accepted_count,
        rejected_count=result.rejected_count,
        rejected_event_ids=result.rejected_event_ids,
    )
