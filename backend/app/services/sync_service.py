"""
Idempotent event ingestion service.

Handles event sync with:
- event_id uniqueness (idempotency)
- (device_id, sequence_number) ordering
- Transactional writes
- Partial batch handling
- Ack cursor response
"""

import traceback
from typing import List, Optional
from uuid import UUID
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from app.models.events import Event
from app.domain.events import validate_event_payload
from app.services.projection_service import WorkoutProjectionBuilder


class SyncResult:
    """Result of a sync operation."""

    def __init__(
        self,
        accepted_count: int,
        rejected_count: int,
        last_acked_sequence: Optional[int],
        rejected_event_ids: List[UUID],
    ):
        self.accepted_count = accepted_count
        self.rejected_count = rejected_count
        self.last_acked_sequence = last_acked_sequence
        self.rejected_event_ids = rejected_event_ids


class SyncService:
    """Service for idempotent event ingestion."""

    def __init__(self, db: Session):
        self.db = db

    def sync_events(
        self,
        device_id: UUID,
        user_id: UUID,
        events: List[dict],
    ) -> SyncResult:
        """
        Sync events with idempotency and ordering guarantees.

        Args:
            device_id: Device identifier
            user_id: User identifier (anonymous or real)
            events: List of event dictionaries with event_id, event_type, payload, sequence_number

        Returns:
            SyncResult with accepted/rejected counts and ack cursor
        """
        accepted_count = 0
        rejected_count = 0
        rejected_event_ids: List[UUID] = []
        last_acked_sequence: Optional[int] = None

        # Validate sequence numbers are monotonic per device (required for ordering)
        sequence_numbers = [e.get("sequence_number") for e in events]
        if sequence_numbers != sorted(set(sequence_numbers)):
            # Check if there are duplicates or non-monotonic sequences
            seen = set()
            for seq in sequence_numbers:
                if seq in seen:
                    # Duplicate sequence number in batch - reject entire batch
                    rejected_count = len(events)
                    rejected_event_ids = [UUID(e["event_id"]) for e in events]
                    return SyncResult(0, rejected_count, None, rejected_event_ids)
                seen.add(seq)

            # Non-monotonic sequence (reordering not allowed) - reject entire batch
            rejected_count = len(events)
            rejected_event_ids = [UUID(e["event_id"]) for e in events]
            return SyncResult(0, rejected_count, None, rejected_event_ids)

        # Process events in transaction
        events_to_insert = []

        # Batch check for existing events (fixes N+1 query problem)
        # Instead of checking each event individually (N queries), we fetch all existing
        # event_ids in a single query and use a set for O(1) lookup
        event_ids = [UUID(e["event_id"]) for e in events]
        existing_events = (
            self.db.query(Event.event_id).filter(Event.event_id.in_(event_ids)).all()
        )
        existing_event_ids = {e.event_id for e in existing_events}

        for event_data in events:
            event_id = UUID(event_data["event_id"])
            event_type = event_data["event_type"]
            payload = event_data["payload"]
            sequence_number = event_data["sequence_number"]

            # Validate payload against schema
            try:
                validate_event_payload(event_type, payload)
            except Exception as validation_error:
                print(
                    f"[SYNC] ⚠️ Event validation failed for {event_type}: {validation_error}"
                )
                print(f"[SYNC] Payload: {payload}")
                rejected_count += 1
                rejected_event_ids.append(event_id)
                continue

            # Check if event already exists (idempotency check via event_id)
            # Using set lookup from batch query above - O(1) instead of N database queries
            if event_id in existing_event_ids:
                # Event already exists, skip insertion but count as accepted (idempotent)
                # This ensures duplicate syncs don't create duplicate events
                accepted_count += 1
                # Update ack cursor even for duplicate events to maintain sequence tracking
                if last_acked_sequence is None or sequence_number > last_acked_sequence:
                    last_acked_sequence = sequence_number
                continue

            # Prepare event for insertion
            events_to_insert.append(
                {
                    "event_id": event_id,
                    "event_type": event_type,
                    "payload": payload,
                    "sequence_number": sequence_number,
                }
            )

        # Insert new events in a single transaction
        if events_to_insert:
            try:
                for event_data in events_to_insert:
                    event = Event(
                        event_id=event_data["event_id"],
                        event_type=event_data["event_type"],
                        payload=event_data["payload"],
                        user_id=user_id,
                        device_id=device_id,
                        sequence_number=event_data["sequence_number"],
                    )
                    self.db.add(event)

                # Commit all new events atomically
                self.db.commit()

                # Update read-optimized projections after successful event insertion
                # Projections are denormalized views optimized for reads (workouts_projection, sets_projection)
                if events_to_insert:
                    try:
                        # Get the Event objects for the newly inserted events
                        # Query by event_id list to fetch all events in one query (batch operation)
                        new_event_objects = (
                            self.db.query(Event)
                            .filter(
                                Event.event_id.in_(
                                    [e["event_id"] for e in events_to_insert]
                                )
                            )
                            .order_by(Event.device_id, Event.sequence_number)
                            .all()
                        )

                        # Update projections incrementally (only new events)
                        # This keeps projections in sync with events without full rebuild
                        builder = WorkoutProjectionBuilder(self.db)
                        builder.update_projections(new_event_objects, user_id)
                    except Exception as e:
                        # Log error but don't fail sync - projections can be rebuilt later via /rebuild endpoint
                        # This ensures event ingestion succeeds even if projection update fails
                        # In production, consider using a background job for projection updates
                        import traceback

                        print(f"[SYNC] ❌ ERROR: Failed to update projections: {e}")
                        print(traceback.format_exc())
                        # Rollback any partial projection changes to maintain consistency
                        try:
                            self.db.rollback()
                        except Exception:
                            pass

                # Update accepted count and ack cursor
                for event_data in events_to_insert:
                    accepted_count += 1
                    seq = event_data["sequence_number"]
                    if last_acked_sequence is None or seq > last_acked_sequence:
                        last_acked_sequence = seq

            except IntegrityError:
                # Rollback and handle duplicates individually
                # This handles race conditions where events were inserted between our batch check and insert
                # Fall back to individual inserts to identify which specific event caused the conflict
                self.db.rollback()
                for event_data in events_to_insert:
                    event_id = event_data["event_id"]
                    sequence_number = event_data["sequence_number"]

                    # Try to insert individually to handle duplicates
                    try:
                        event = Event(
                            event_id=event_id,
                            event_type=event_data["event_type"],
                            payload=event_data["payload"],
                            user_id=user_id,
                            device_id=device_id,
                            sequence_number=sequence_number,
                        )
                        self.db.add(event)
                        self.db.commit()
                        accepted_count += 1
                        if (
                            last_acked_sequence is None
                            or sequence_number > last_acked_sequence
                        ):
                            last_acked_sequence = sequence_number
                    except IntegrityError:
                        # Event already exists (idempotent)
                        self.db.rollback()
                        accepted_count += 1
                        if (
                            last_acked_sequence is None
                            or sequence_number > last_acked_sequence
                        ):
                            last_acked_sequence = sequence_number
                    except Exception:
                        self.db.rollback()
                        rejected_count += 1
                        rejected_event_ids.append(event_id)
            except Exception as e:
                # Rollback on any other error
                error_traceback = traceback.format_exc()
                print(f"[SYNC] ❌ ERROR during event insertion: {e}")
                print(error_traceback)
                self.db.rollback()
                # Mark all pending events as rejected
                for event_data in events_to_insert:
                    rejected_count += 1
                    rejected_event_ids.append(event_data["event_id"])
                raise

        return SyncResult(
            accepted_count=accepted_count,
            rejected_count=rejected_count,
            last_acked_sequence=last_acked_sequence,
            rejected_event_ids=rejected_event_ids,
        )
