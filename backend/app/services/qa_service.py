"""
Q&A service for workout-related questions.

Uses upsonic AI agent to answer user questions about exercises, form, and injuries.
"""

from uuid import UUID
from typing import Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from app.models.projections import WorkoutProjection, SetProjection, Exercise
from app.services.ai_agent_service import get_qa_agent, get_exercise_name_map
from upsonic import Task


class QAService:
    """Service for answering workout-related questions using AI."""

    def __init__(self, db: Session):
        self.db = db

    def answer_question(self, user_id: UUID, question: str) -> str:
        """
        Answer a user's workout-related question using AI agent.
        
        Args:
            user_id: User ID
            question: User's question
            
        Returns:
            AI-generated answer
        """
        # Get relevant workout history for context
        context = self._get_relevant_context(user_id, question)
        
        # Build prompt with context
        if context:
            prompt = f"{context}\n\nUser: {question}\nAssistant:"
        else:
            prompt = f"User: {question}\nAssistant:"
        
        # Get agent and generate answer
        agent = get_qa_agent(user_id)
        task = Task(prompt)
        result = agent.do(task)
        
        return str(result)

    def _get_relevant_context(self, user_id: UUID, question: str) -> Optional[str]:
        """
        Get relevant workout history context based on question.
        
        This extracts exercise names from the question and retrieves recent
        workout data for those exercises.
        
        Args:
            user_id: User ID
            question: User's question
            
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
            .limit(10)
            .all()
        )
        
        if not recent_workouts:
            return None
        
        # Get all sets for these workouts
        workout_ids = [w.workout_id for w in recent_workouts]
        sets = (
            self.db.query(SetProjection)
            .filter(SetProjection.workout_id.in_(workout_ids))
            .order_by(SetProjection.completed_at.desc())
            .all()
        )
        
        if not sets:
            return None
        
        # Get exercise names
        exercise_ids = list(set(s.exercise_id for s in sets))
        exercise_map = get_exercise_name_map(self.db, exercise_ids)
        
        # Try to find exercises mentioned in question (simple keyword matching)
        question_lower = question.lower()
        relevant_exercises = []
        for exercise_id, exercise_name in exercise_map.items():
            if exercise_name.lower() in question_lower:
                relevant_exercises.append(exercise_id)
        
        # If no specific exercises found, use most recent exercises
        if not relevant_exercises:
            # Get unique exercises from recent sets (most recent first)
            seen_exercises = []
            for s in sets:
                if s.exercise_id not in seen_exercises:
                    seen_exercises.append(s.exercise_id)
                if len(seen_exercises) >= 3:  # Limit to 3 most recent exercises
                    break
            relevant_exercises = seen_exercises
        
        # Build context for relevant exercises
        context_lines = []
        for exercise_id in relevant_exercises[:3]:  # Limit to 3 exercises
            exercise_name = exercise_map.get(exercise_id, f"Exercise {exercise_id}")
            exercise_sets = [s for s in sets if s.exercise_id == exercise_id]
            
            if exercise_sets:
                # Get most recent set
                most_recent = exercise_sets[0]
                reps = most_recent.reps or 0
                weight = most_recent.weight or 0
                date_str = most_recent.completed_at.strftime("%Y-%m-%d")
                
                context_lines.append(
                    f"Note: User's last {exercise_name} – {most_recent.workout_id} on {date_str}, "
                    f"{reps} reps at {weight}kg."
                )
        
        if context_lines:
            return "\n".join(context_lines)
        
        return None

