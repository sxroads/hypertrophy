"""
AI report generation service.

Generates weekly workout reports using AI.
"""

from uuid import UUID
from datetime import date, datetime, timedelta
from typing import Optional, List
from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from app.models.projections import (
    WeeklyMetrics,
    WeeklyReport,
    WorkoutProjection,
)
from app.services.ai_agent_service import (
    get_week_start,
    get_weekly_report_agent,
    format_workout_data_for_ai,
)
from upsonic import Task


class AIReportService:
    """Service for generating AI-powered weekly workout reports."""

    def __init__(self, db: Session):
        self.db = db

    def generate_weekly_report(
        self, user_id: UUID, week_start: Optional[date] = None
    ) -> WeeklyReport:
        """
        Generate an AI weekly report for a user.

        Args:
            user_id: User ID
            week_start: Monday date of the week (defaults to current week)

        Returns:
            WeeklyReport object
        """
        if week_start is None:
            week_start = get_week_start(datetime.now())

        # Check if report already exists
        existing_report = (
            self.db.query(WeeklyReport)
            .filter(
                and_(
                    WeeklyReport.user_id == user_id,
                    WeeklyReport.week_start == week_start,
                )
            )
            .first()
        )

        if existing_report:
            return existing_report

        # Get weekly metrics
        metrics = (
            self.db.query(WeeklyMetrics)
            .filter(
                and_(
                    WeeklyMetrics.user_id == user_id,
                    WeeklyMetrics.week_start == week_start,
                )
            )
            .first()
        )

        # Get workout details for context
        week_end = week_start + timedelta(days=6)
        workouts = (
            self.db.query(WorkoutProjection)
            .filter(
                and_(
                    WorkoutProjection.user_id == user_id,
                    WorkoutProjection.status == "completed",
                    func.date(WorkoutProjection.started_at) >= week_start,
                    func.date(WorkoutProjection.started_at) <= week_end,
                )
            )
            .order_by(WorkoutProjection.started_at)
            .all()
        )

        # Generate report using AI agent
        try:
            report_text = self._generate_report_text_with_ai(
                user_id, metrics, workouts, week_start
            )
        except Exception as e:
            # Fallback to template-based report if AI fails
            import traceback

            error_details = traceback.format_exc()
            print(
                f"[AI_REPORT] WARNING: AI generation failed: {e}\n"
                f"Traceback: {error_details}\n"
                f"Falling back to template-based report"
            )
            report_text = self._generate_report_text_template(
                metrics, workouts, week_start
            )

        # Create report
        report = WeeklyReport(
            user_id=user_id,
            week_start=week_start,
            report_text=report_text,
        )
        self.db.add(report)
        self.db.commit()

        return report

    def _generate_report_text_with_ai(
        self,
        user_id: UUID,
        metrics: Optional[WeeklyMetrics],
        workouts: List[WorkoutProjection],
        week_start: date,
    ) -> str:
        """
        Generate report text using upsonic AI agent.

        Args:
            user_id: User ID
            metrics: Weekly metrics (optional)
            workouts: List of workouts for the week
            week_start: Monday date of the week

        Returns:
            AI-generated report text
        """
        if not metrics or len(workouts) == 0:
            return f"Week of {week_start.strftime('%B %d, %Y')}\n\nNo workouts completed this week. Keep pushing! 💪"

        # Format workout data for AI
        workout_data_text = format_workout_data_for_ai(
            self.db, user_id, week_start, workouts
        )

        # Create prompt with metrics summary
        metrics_summary = (
            f"Week Summary:\n"
            f"- Workouts Completed: {metrics.total_workouts}\n"
            f"- Total Volume: {metrics.total_volume:.1f} kg\n"
            f"- Unique Exercises: {metrics.exercises_count}\n"
        )

        if metrics.total_workouts > 0:
            avg_volume = metrics.total_volume / metrics.total_workouts
            metrics_summary += f"- Average Volume per Workout: {avg_volume:.1f} kg\n"

        prompt = (
            f"User's past week workout data:\n{workout_data_text}\n\n"
            f"{metrics_summary}\n\n"
            "Please analyze this data and generate a weekly progress report for the user. "
            "Highlight strengths, any improvements or declines, and give suggestions for next week. "
            "IMPORTANT: Do not use markdown formatting in your report. Do not use ** for bold text or ### for titles. "
            "Write in plain text format only."
        )

        # Get agent and generate report
        agent = get_weekly_report_agent(user_id, week_start)
        task = Task(prompt)
        result = agent.do(task)

        return str(result)

    def _generate_report_text_template(
        self,
        metrics: Optional[WeeklyMetrics],
        workouts: List[WorkoutProjection],
        week_start: date,
    ) -> str:
        """
        Generate template-based report text (fallback).

        This is used when AI generation fails.
        """
        if not metrics or len(workouts) == 0:
            return f"Week of {week_start.strftime('%B %d, %Y')}\n\nNo workouts completed this week. Keep pushing! 💪"

        # Generate report
        report_lines = [
            f"📊 Weekly Report - Week of {week_start.strftime('%B %d, %Y')}\n",
            f"🏋️ Workouts Completed: {metrics.total_workouts}",
            f"💪 Total Volume: {metrics.total_volume:.1f} kg",
            f"🎯 Unique Exercises: {metrics.exercises_count}\n",
        ]

        if metrics.total_workouts > 0:
            avg_volume_per_workout = metrics.total_volume / metrics.total_workouts
            report_lines.append(
                f"📈 Average Volume per Workout: {avg_volume_per_workout:.1f} kg\n"
            )

        # Add insights
        report_lines.append("💡 Insights:\n")

        if metrics.total_workouts >= 4:
            report_lines.append(
                "✅ Excellent consistency! You're hitting the gym regularly."
            )
        elif metrics.total_workouts >= 2:
            report_lines.append(
                "👍 Good effort! Consider adding more workouts for better results."
            )
        else:
            report_lines.append(
                "💪 Every  counts! Try to increase frequency next week."
            )

        if metrics.total_volume > 0:
            report_lines.append(
                f"🔥 You lifted {metrics.total_volume:.1f} kg total this week - impressive!"
            )

        return "\n".join(report_lines)

    def get_weekly_report(
        self, user_id: UUID, week_start: Optional[date] = None
    ) -> Optional[WeeklyReport]:
        """
        Get weekly report for a user.

        Args:
            user_id: User ID
            week_start: Monday date of the week (defaults to current week)

        Returns:
            WeeklyReport or None if not found
        """
        if week_start is None:
            week_start = get_week_start(datetime.now())

        return (
            self.db.query(WeeklyReport)
            .filter(
                and_(
                    WeeklyReport.user_id == user_id,
                    WeeklyReport.week_start == week_start,
                )
            )
            .first()
        )
