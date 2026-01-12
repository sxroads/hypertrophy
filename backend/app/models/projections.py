from sqlalchemy import Column, String, Integer, Float, DateTime, ForeignKey, Date
from sqlalchemy.sql import func
import uuid
from app.db.database import Base
from app.db.types import GUID


class Exercise(Base):
    __tablename__ = "exercises"

    exercise_id = Column(GUID(), primary_key=True, default=uuid.uuid4)
    name = Column(String, nullable=False, unique=True, index=True)
    muscle_category = Column(
        String, nullable=False, index=True
    )  # chest, back, legs, shoulders, arms, core
    created_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class WorkoutProjection(Base):
    __tablename__ = "workouts_projection"

    workout_id = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id = Column(GUID(), nullable=False, index=True)
    started_at = Column(DateTime(timezone=True), nullable=False)
    ended_at = Column(DateTime(timezone=True), nullable=True)
    status = Column(String, nullable=False)  # 'in_progress', 'completed', 'cancelled'


class SetProjection(Base):
    __tablename__ = "sets_projection"

    set_id = Column(GUID(), primary_key=True, default=uuid.uuid4)
    workout_id = Column(
        GUID(),
        ForeignKey("workouts_projection.workout_id"),
        nullable=False,
        index=True,
    )
    exercise_id = Column(GUID(), nullable=False, index=True)
    reps = Column(Integer, nullable=True)
    weight = Column(Float, nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=False)


class WeeklyMetrics(Base):
    __tablename__ = "weekly_metrics"

    id = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id = Column(GUID(), nullable=False, index=True)
    week_start = Column(Date, nullable=False)
    total_workouts = Column(Integer, default=0, nullable=False)
    total_volume = Column(Float, default=0.0, nullable=False)  # total weight lifted
    exercises_count = Column(Integer, default=0, nullable=False)

    __table_args__ = ({"schema": None},)


class WeeklyReport(Base):
    __tablename__ = "weekly_reports"

    id = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id = Column(GUID(), nullable=False, index=True)
    week_start = Column(Date, nullable=False)
    report_text = Column(String, nullable=False)
    generated_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
