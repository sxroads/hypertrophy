from sqlalchemy import Column, Float, DateTime, Index
from sqlalchemy.sql import func
import uuid
from app.db.database import Base
from app.db.types import GUID


class BodyMeasurement(Base):
    __tablename__ = "body_measurements"

    measurement_id = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id = Column(GUID(), nullable=False, index=True)
    measured_at = Column(DateTime(timezone=True), nullable=False, index=True)

    # Required measurements
    height_cm = Column(Float, nullable=False)
    weight_kg = Column(Float, nullable=False)
    neck_cm = Column(Float, nullable=False)
    waist_cm = Column(Float, nullable=False)

    # Optional measurements
    hip_cm = Column(Float, nullable=True)
    chest_cm = Column(Float, nullable=True)
    shoulder_cm = Column(Float, nullable=True)
    bicep_cm = Column(Float, nullable=True)
    forearm_cm = Column(Float, nullable=True)
    thigh_cm = Column(Float, nullable=True)
    calf_cm = Column(Float, nullable=True)

    # Calculated metrics
    body_fat_percentage = Column(Float, nullable=True)
    fat_mass_kg = Column(Float, nullable=True)
    lean_mass_kg = Column(Float, nullable=True)

    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
