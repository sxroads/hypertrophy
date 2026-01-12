"""Add body measurements table and user profile fields

Revision ID: 006_add_body_measurements
Revises: 005_add_exercises_table

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "006_add_body_measurements"
down_revision: Union[str, None] = "005_add_exercises_table"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add gender and age to users table
    op.add_column("users", sa.Column("gender", sa.String(), nullable=True))
    op.add_column("users", sa.Column("age", sa.Integer(), nullable=True))

    # Create body_measurements table
    op.create_table(
        "body_measurements",
        sa.Column("measurement_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("measured_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("height_cm", sa.Float(), nullable=False),
        sa.Column("weight_kg", sa.Float(), nullable=False),
        sa.Column("neck_cm", sa.Float(), nullable=False),
        sa.Column("waist_cm", sa.Float(), nullable=False),
        sa.Column("hip_cm", sa.Float(), nullable=True),
        sa.Column("chest_cm", sa.Float(), nullable=True),
        sa.Column("shoulder_cm", sa.Float(), nullable=True),
        sa.Column("bicep_cm", sa.Float(), nullable=True),
        sa.Column("forearm_cm", sa.Float(), nullable=True),
        sa.Column("thigh_cm", sa.Float(), nullable=True),
        sa.Column("calf_cm", sa.Float(), nullable=True),
        sa.Column("body_fat_percentage", sa.Float(), nullable=True),
        sa.Column("fat_mass_kg", sa.Float(), nullable=True),
        sa.Column("lean_mass_kg", sa.Float(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("measurement_id"),
    )
    op.create_index(
        op.f("ix_body_measurements_user_id"),
        "body_measurements",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_body_measurements_measured_at"),
        "body_measurements",
        ["measured_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_body_measurements_measured_at"), table_name="body_measurements"
    )
    op.drop_index(op.f("ix_body_measurements_user_id"), table_name="body_measurements")
    op.drop_table("body_measurements")
    op.drop_column("users", "age")
    op.drop_column("users", "gender")
