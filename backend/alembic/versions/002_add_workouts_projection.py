"""Add workouts and sets projections

Revision ID: 002_add_workouts_projection
Revises: 001_create_users_devices_events

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "002_add_workouts_projection"
down_revision: Union[str, None] = "001_create_users_devices_events"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Workouts projection
    op.create_table(
        "workouts_projection",
        sa.Column("workout_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(), nullable=False),
        sa.PrimaryKeyConstraint("workout_id"),
    )
    op.create_index(
        op.f("ix_workouts_projection_user_id"),
        "workouts_projection",
        ["user_id"],
        unique=False,
    )

    # Sets projection
    op.create_table(
        "sets_projection",
        sa.Column("set_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("workout_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("exercise_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("reps", sa.Integer(), nullable=True),
        sa.Column("weight", sa.Float(), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["workout_id"],
            ["workouts_projection.workout_id"],
        ),
        sa.PrimaryKeyConstraint("set_id"),
    )
    op.create_index(
        op.f("ix_sets_projection_workout_id"),
        "sets_projection",
        ["workout_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_sets_projection_exercise_id"),
        "sets_projection",
        ["exercise_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_sets_projection_exercise_id"), table_name="sets_projection")
    op.drop_index(op.f("ix_sets_projection_workout_id"), table_name="sets_projection")
    op.drop_table("sets_projection")
    op.drop_index(
        op.f("ix_workouts_projection_user_id"), table_name="workouts_projection"
    )
    op.drop_table("workouts_projection")
