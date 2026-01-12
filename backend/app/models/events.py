from sqlalchemy import Column, String, Integer, DateTime, Index
from sqlalchemy.sql import func
import uuid
from app.db.database import Base
from app.db.types import GUID, JSONB


class Event(Base):
    __tablename__ = "events"

    event_id = Column(GUID(), primary_key=True)  # Client-generated, no default
    event_type = Column(String, nullable=False, index=True)
    payload = Column(JSONB(), nullable=False)
    user_id = Column(GUID(), nullable=False, index=True)
    device_id = Column(GUID(), nullable=False, index=True)
    sequence_number = Column(Integer, nullable=False)
    correlation_id = Column(GUID(), nullable=True)
    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Composite index for efficient querying by device and sequence
    __table_args__ = (
        Index("idx_events_device_sequence", "device_id", "sequence_number"),
        Index("idx_events_user_created", "user_id", "created_at"),
    )
