"""Add weekly metrics and reports

Revision ID: 003_add_weekly_metrics
Revises: 002_add_workouts_projection

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "003_add_weekly_metrics"
down_revision: Union[str, None] = "002_add_workouts_projection"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Weekly metrics
    op.create_table(
        "weekly_metrics",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("week_start", sa.Date(), nullable=False),
        sa.Column("total_workouts", sa.Integer(), server_default="0", nullable=False),
        sa.Column("total_volume", sa.Float(), server_default="0.0", nullable=False),
        sa.Column("exercises_count", sa.Integer(), server_default="0", nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_weekly_metrics_user_id"), "weekly_metrics", ["user_id"], unique=False
    )

    # Weekly reports
    op.create_table(
        "weekly_reports",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("week_start", sa.Date(), nullable=False),
        sa.Column("report_text", sa.String(), nullable=False),
        sa.Column(
            "generated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_weekly_reports_user_id"), "weekly_reports", ["user_id"], unique=False
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_weekly_reports_user_id"), table_name="weekly_reports")
    op.drop_table("weekly_reports")
    op.drop_index(op.f("ix_weekly_metrics_user_id"), table_name="weekly_metrics")
    op.drop_table("weekly_metrics")
