"""
Workout Exercise service for real-time exercise questions during workouts.

Uses upsonic AI agent to answer user questions about specific exercises
during active workout sessions.
"""

from uuid import UUID
from typing import Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_

from app.models.projections import WorkoutProjection, SetProjection
from app.services.ai_agent_service import get_workout_exercise_agent
from upsonic import Task


class WorkoutExerciseService:
    """Service for answering real-time exercise questions during workouts."""

    def __init__(self, db: Session):
        self.db = db

    def answer_exercise_question(
        self, user_id: UUID, exercise_id: UUID, exercise_name: str, question: str
    ) -> str:
        """
        Answer a user's question about a specific exercise during workout.

        Args:
            user_id: User ID
            exercise_id: Exercise ID
            exercise_name: Exercise name
            question: User's question

        Returns:
            AI-generated answer
        """
        # Get relevant context for this specific exercise
        context = self._get_exercise_context(user_id, exercise_id, exercise_name)

        # Build prompt with exercise context
        # Auto-include exercise name so user can ask naturally
        if context:
            prompt = (
                f"Context: {context}\n\n"
                f"User is currently doing {exercise_name}. User says: {question}\n"
                f"Assistant:"
            )
        else:
            prompt = (
                f"User is currently doing {exercise_name}. User says: {question}\n"
                f"Assistant:"
            )

        # Get agent and generate answer
        agent = get_workout_exercise_agent(user_id, exercise_id, exercise_name)
        task = Task(prompt)
        result = agent.do(task)

        return str(result)

    def _get_exercise_context(
        self, user_id: UUID, exercise_id: UUID, exercise_name: str
    ) -> Optional[str]:
        """
        Get relevant workout history context for the specific exercise.

        Args:
            user_id: User ID
            exercise_id: Exercise ID
            exercise_name: Exercise name

        Returns:
            Formatted context string or None
        """
        # Get recent completed workouts (last 30 days)
        from datetime import datetime, timedelta

        thirty_days_ago = datetime.now() - timedelta(days=30)

        recent_workouts = (
            self.db.query(WorkoutProjection)
            .filter(
                and_(
                    WorkoutProjection.user_id == user_id,
                    WorkoutProjection.status == "completed",
                    WorkoutProjection.started_at >= thirty_days_ago,
                )
            )
            .order_by(WorkoutProjection.started_at.desc())
            .limit(5)
            .all()
        )

        if not recent_workouts:
            return None

        # Get sets for this specific exercise from recent workouts
        workout_ids = [w.workout_id for w in recent_workouts]
        exercise_sets = (
            self.db.query(SetProjection)
            .filter(
                and_(
                    SetProjection.workout_id.in_(workout_ids),
                    SetProjection.exercise_id == exercise_id,
                )
            )
            .order_by(SetProjection.completed_at.desc())
            .limit(5)
            .all()
        )

        if not exercise_sets:
            return None

        # Build context with recent performance for this exercise
        context_lines = [f"User's recent {exercise_name} performance:"]

        for s in exercise_sets[:3]:  # Limit to 3 most recent sets
            reps = s.reps or 0
            weight = s.weight or 0
            date_str = s.completed_at.strftime("%Y-%m-%d")
            context_lines.append(f"- {date_str}: {reps} reps at {weight}kg")

        return "\n".join(context_lines)
