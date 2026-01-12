"""Add exercises table

Revision ID: 005_add_exercises_table
Revises: 003_add_weekly_metrics

"""

from typing import Sequence, Union
import uuid

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "005_add_exercises_table"
down_revision: Union[str, None] = "003_add_weekly_metrics"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Create exercises table
    op.create_table(
        "exercises",
        sa.Column("exercise_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("muscle_category", sa.String(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("exercise_id"),
    )
    op.create_index(op.f("ix_exercises_name"), "exercises", ["name"], unique=True)
    op.create_index(
        op.f("ix_exercises_muscle_category"),
        "exercises",
        ["muscle_category"],
        unique=False,
    )

    # Seed exercises with fixed UUIDs for consistency
    exercises_data = [
        # Chest
        (uuid.UUID("00000000-0000-0000-0000-000000000001"), "Bench Press", "chest"),
        (
            uuid.UUID("00000000-0000-0000-0000-000000000002"),
            "Incline Bench Press",
            "chest",
        ),
        (
            uuid.UUID("00000000-0000-0000-0000-000000000003"),
            "Decline Bench Press",
            "chest",
        ),
        (uuid.UUID("00000000-0000-0000-0000-000000000004"), "Dumbbell Flyes", "chest"),
        (uuid.UUID("00000000-0000-0000-0000-000000000005"), "Push-ups", "chest"),
        (uuid.UUID("00000000-0000-0000-0000-000000000006"), "Cable Crossover", "chest"),
        # Back
        (uuid.UUID("00000000-0000-0000-0000-000000000007"), "Deadlift", "back"),
        (uuid.UUID("00000000-0000-0000-0000-000000000008"), "Pull-ups", "back"),
        (uuid.UUID("00000000-0000-0000-0000-000000000009"), "Barbell Row", "back"),
        (uuid.UUID("00000000-0000-0000-0000-00000000000a"), "Lat Pulldown", "back"),
        (uuid.UUID("00000000-0000-0000-0000-00000000000b"), "T-Bar Row", "back"),
        (uuid.UUID("00000000-0000-0000-0000-00000000000c"), "Seated Cable Row", "back"),
        (uuid.UUID("00000000-0000-0000-0000-00000000000d"), "Face Pulls", "back"),
        # Legs
        (uuid.UUID("00000000-0000-0000-0000-00000000000e"), "Squat", "legs"),
        (uuid.UUID("00000000-0000-0000-0000-00000000000f"), "Leg Press", "legs"),
        (
            uuid.UUID("00000000-0000-0000-0000-000000000010"),
            "Romanian Deadlift",
            "legs",
        ),
        (uuid.UUID("00000000-0000-0000-0000-000000000011"), "Leg Curl", "legs"),
        (uuid.UUID("00000000-0000-0000-0000-000000000012"), "Leg Extension", "legs"),
        (uuid.UUID("00000000-0000-0000-0000-000000000013"), "Calf Raises", "legs"),
        (uuid.UUID("00000000-0000-0000-0000-000000000014"), "Lunges", "legs"),
        (
            uuid.UUID("00000000-0000-0000-0000-000000000015"),
            "Bulgarian Split Squat",
            "legs",
        ),
        # Shoulders
        (
            uuid.UUID("00000000-0000-0000-0000-000000000016"),
            "Overhead Press",
            "shoulders",
        ),
        (
            uuid.UUID("00000000-0000-0000-0000-000000000017"),
            "Lateral Raises",
            "shoulders",
        ),
        (
            uuid.UUID("00000000-0000-0000-0000-000000000018"),
            "Front Raises",
            "shoulders",
        ),
        (
            uuid.UUID("00000000-0000-0000-0000-000000000019"),
            "Rear Delt Flyes",
            "shoulders",
        ),
        (uuid.UUID("00000000-0000-0000-0000-00000000001a"), "Upright Row", "shoulders"),
        # Arms
        (uuid.UUID("00000000-0000-0000-0000-00000000001b"), "Bicep Curls", "arms"),
        (uuid.UUID("00000000-0000-0000-0000-00000000001c"), "Hammer Curls", "arms"),
        (uuid.UUID("00000000-0000-0000-0000-00000000001d"), "Tricep Dips", "arms"),
        (uuid.UUID("00000000-0000-0000-0000-00000000001e"), "Tricep Pushdowns", "arms"),
        (
            uuid.UUID("00000000-0000-0000-0000-00000000001f"),
            "Close-Grip Bench Press",
            "arms",
        ),
        # Core
        (uuid.UUID("00000000-0000-0000-0000-000000000020"), "Plank", "core"),
        (uuid.UUID("00000000-0000-0000-0000-000000000021"), "Russian Twists", "core"),
        (uuid.UUID("00000000-0000-0000-0000-000000000022"), "Leg Raises", "core"),
        (uuid.UUID("00000000-0000-0000-0000-000000000023"), "Crunches", "core"),
        (uuid.UUID("00000000-0000-0000-0000-000000000024"), "Cable Crunches", "core"),
    ]

    # Insert seed data
    # Using connection for proper parameter binding
    connection = op.get_bind()
    for exercise_id, name, muscle_category in exercises_data:
        connection.execute(
            sa.text(
                """
                INSERT INTO exercises (exercise_id, name, muscle_category, created_at)
                VALUES (:exercise_id, :name, :muscle_category, now())
                """
            ),
            {
                "exercise_id": str(exercise_id),
                "name": name,
                "muscle_category": muscle_category,
            },
        )
    connection.commit()

    # Optional: Add foreign key constraint (commented out for backward compatibility)
    # op.create_foreign_key(
    #     "fk_sets_projection_exercise_id",
    #     "sets_projection",
    #     "exercises",
    #     ["exercise_id"],
    #     ["exercise_id"],
    # )


def downgrade() -> None:
    # Drop foreign key if it exists
    # op.drop_constraint("fk_sets_projection_exercise_id", "sets_projection", type_="foreignkey")

    op.drop_index(op.f("ix_exercises_muscle_category"), table_name="exercises")
    op.drop_index(op.f("ix_exercises_name"), table_name="exercises")
    op.drop_table("exercises")
