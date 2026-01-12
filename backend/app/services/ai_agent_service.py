"""
AI Agent Manager Service.

Manages upsonic agents for weekly reports and Q&A, including memory storage
and exercise name lookups.
"""

import os
from pathlib import Path
from uuid import UUID
from datetime import date, datetime, timedelta
from typing import Dict, Optional, List
from sqlalchemy.orm import Session

from upsonic import Agent
from upsonic.storage.providers.sqlite import SqliteStorage
from upsonic.storage import Memory

from app.models.projections import Exercise, WorkoutProjection, SetProjection


# Get storage path from environment or use default
def get_storage_path() -> str:
    """Get SQLite storage path from environment or default."""
    default_path = os.path.join(
        os.path.dirname(__file__), "..", "..", "data", "agent_memory.db"
    )
    storage_path = os.getenv("AI_MEMORY_DB_PATH", default_path)

    # Ensure directory exists
    Path(storage_path).parent.mkdir(parents=True, exist_ok=True)

    return storage_path


# Initialize storage singleton
_storage: Optional[SqliteStorage] = None


def get_storage() -> SqliteStorage:
    """Get or create SQLite storage singleton."""
    global _storage
    if _storage is None:
        storage_path = get_storage_path()
        _storage = SqliteStorage(
            db_file=storage_path,
            sessions_table_name="sessions",
            profiles_table_name="profiles",
        )
    return _storage


def get_week_start(dt: datetime) -> date:
    """Get the Monday of the week for a given date."""
    days_since_monday = dt.weekday()
    monday = dt.date() - timedelta(days=days_since_monday)
    return monday


def get_exercise_name_map(db: Session, exercise_ids: List[UUID]) -> Dict[UUID, str]:
    """
    Get exercise name mapping for given exercise IDs.

    Args:
        db: Database session
        exercise_ids: List of exercise IDs to look up

    Returns:
        Dictionary mapping exercise_id to exercise name
    """
    if not exercise_ids:
        return {}

    exercises = db.query(Exercise).filter(Exercise.exercise_id.in_(exercise_ids)).all()

    return {ex.exercise_id: ex.name for ex in exercises}


def format_workout_data_for_ai(
    db: Session,
    user_id: UUID,
    week_start: date,
    workouts: List[WorkoutProjection],
) -> str:
    """
    Format workout data for AI agent prompt.

    Args:
        db: Database session
        user_id: User ID
        week_start: Monday date of the week
        workouts: List of workout projections for the week

    Returns:
        Formatted string with workout data
    """
    if not workouts:
        return f"Week of {week_start.strftime('%B %d, %Y')}\n\nNo workouts completed this week."

    # Get all sets for these workouts
    workout_ids = [w.workout_id for w in workouts]
    sets = (
        db.query(SetProjection)
        .filter(SetProjection.workout_id.in_(workout_ids))
        .order_by(SetProjection.completed_at)
        .all()
    )

    # Get exercise names
    exercise_ids = list(set(s.exercise_id for s in sets))
    exercise_map = get_exercise_name_map(db, exercise_ids)

    # Group sets by workout and exercise
    workout_data = {}
    for workout in workouts:
        workout_sets = [s for s in sets if s.workout_id == workout.workout_id]

        # Group by exercise
        exercise_groups = {}
        for s in workout_sets:
            if s.exercise_id not in exercise_groups:
                exercise_groups[s.exercise_id] = []
            exercise_groups[s.exercise_id].append(s)

        workout_data[workout.workout_id] = {
            "date": workout.started_at.date(),
            "exercises": exercise_groups,
        }

    # Format as text
    lines = [f"Week of {week_start.strftime('%B %d, %Y')}\n"]

    for workout_id, data in sorted(workout_data.items(), key=lambda x: x[1]["date"]):
        date_str = data["date"].strftime("%Y-%m-%d")
        lines.append(f"\n{date_str}:")

        for exercise_id, exercise_sets in data["exercises"].items():
            exercise_name = exercise_map.get(exercise_id, f"Exercise {exercise_id}")
            reps_weights = []
            for s in exercise_sets:
                reps = s.reps or 0
                weight = s.weight or 0
                reps_weights.append(f"{reps} reps x {weight} kg")

            sets_count = len(exercise_sets)
            sets_info = ", ".join(reps_weights)
            lines.append(f"  - {exercise_name}: {sets_count} sets ({sets_info})")

    return "\n".join(lines)


def get_weekly_report_agent(user_id: UUID, week_start: date) -> Agent:
    """
    Get or create Weekly Progress Report Agent.

    Args:
        user_id: User ID
        week_start: Monday date of the week

    Returns:
        Configured Agent instance
    """
    storage = get_storage()
    session_id = f"weekly_{user_id}_{week_start}"

    memory = Memory(
        storage=storage,
        session_id=session_id,
        user_id=str(user_id),
        full_session_memory=True,
        summary_memory=True,
        user_analysis_memory=True,
        model="openai/gpt-4o-mini",
    )

    agent = Agent(
        name="WeeklyProgressAgent",
        role="Certified Fitness Coach and Personal Trainer",
        goal="Analyze the user's weekly workout data and provide a detailed progress report",
        instructions=(
            "You are a personal trainer AI that reviews a week's worth of workouts and writes a helpful report. "
            "Include achievements (e.g. increased weights or reps), note any missed sessions or regressions, "
            "and give practical suggestions for improvement. Keep the tone positive and motivational. "
            "IMPORTANT: Do not use markdown formatting in your reports. Do not use ** for bold text or ### for titles. "
            "Write in plain text format only."
        ),
        model="openai/gpt-4o",
        memory=memory,
        debug=True,
    )

    return agent


def get_qa_agent(user_id: UUID) -> Agent:
    """
    Get or create Workout Q&A Agent.

    Args:
        user_id: User ID

    Returns:
        Configured Agent instance
    """
    storage = get_storage()
    session_id = f"qa_{user_id}"

    memory = Memory(
        storage=storage,
        session_id=session_id,
        user_id=str(user_id),
        full_session_memory=True,
        summary_memory=True,
        user_analysis_memory=True,
        model="openai/gpt-4o-mini",
    )

    agent = Agent(
        name="WorkoutAdvisorAgent",
        role="Experienced Personal Trainer and Sports Physiotherapist",
        goal="Answer the user's questions about exercises, form, and injuries with personalized advice",
        instructions=(
            "You are a helpful fitness coach AI. Answer the user's workout and form questions in detail. "
            "Always address potential causes of any pain or issues they mention, and suggest how to fix or improve. "
            "If the user has a relevant workout history (e.g., recent lifts or injuries), consider that in your answer. "
            "Keep responses clear and encouraging, and caution the user to prioritize safety."
        ),
        model="openai/gpt-4o",
        memory=memory,
        debug=True,
    )

    return agent


def get_workout_exercise_agent(
    user_id: UUID, exercise_id: UUID, exercise_name: str
) -> Agent:
    """
    Get or create Real-time Workout Exercise Agent.

    This agent is optimized for immediate feedback during active workouts,
    providing quick, actionable advice about specific exercises.
    Instructions:
    - Provide quick, concise, and actionable advice.
    - Focus on immediate concerns like form corrections, pain or discomfort, technique issues, or safety warnings.
    - Keep responses brief but helpful.
    - If the user mentions pain or discomfort, prioritize safety and suggest modifications or stopping if needed.
    - Be encouraging and supportive while maintaining focus on proper form and safety.

    Args:
        user_id: User ID
        exercise_id: Exercise ID
        exercise_name: Exercise name

    Returns:
        Configured Agent instance
    """
    storage = get_storage()
    session_id = f"workout_exercise_{user_id}_{exercise_id}"

    memory = Memory(
        storage=storage,
        session_id=session_id,
        user_id=str(user_id),
        full_session_memory=True,
        summary_memory=True,
        user_analysis_memory=True,
        model="openai/gpt-4o-mini",
    )

    agent = Agent(
        name="RealTimeWorkoutCoachAgent",
        role="Real-time Workout Coach and Exercise Form Specialist",
        goal="Provide immediate, actionable feedback about exercises during active workouts",
        instructions=(
            "You are a real-time workout coach AI helping users during their active workout session. "
            "The user is currently performing the exercise: {exercise_name}. "
            "Provide quick, concise, and actionable advice. Focus on immediate concerns like form corrections, "
            "pain or discomfort, technique issues, or safety warnings. Keep responses brief but helpful. "
            "If the user mentions pain or discomfort, prioritize safety and suggest modifications or stopping if needed. "
            "Be encouraging and supportive while maintaining focus on proper form and safety."
        ).format(exercise_name=exercise_name),
        model="openai/gpt-4o",
        memory=memory,
        debug=True,
    )

    return agent


def get_body_measurement_agent(user_id: UUID) -> Agent:
    """
    Get or create Body Measurement Analysis Agent.

    Args:
        user_id: User ID

    Returns:
        Configured Agent instance
    """
    storage = get_storage()
    session_id = f"body_measurement_{user_id}"

    memory = Memory(
        storage=storage,
        session_id=session_id,
        user_id=str(user_id),
        full_session_memory=True,
        summary_memory=True,
        user_analysis_memory=True,
        model="openai/gpt-4o-mini",
    )

    agent = Agent(
        name="BodyCompositionAnalystAgent",
        role="Fitness and Body Composition Analyst",
        goal="Analyze body measurement changes and provide personalized insights and recommendations",
        instructions=(
            "You are a fitness and body composition analyst AI. Analyze the user's body measurement data, "
            "comparing current measurements to previous ones. Highlight significant changes in body fat percentage, "
            "muscle mass, fat mass, and circumference measurements. Provide actionable insights about what these changes "
            "mean for their fitness journey. Be encouraging and supportive while providing honest, data-driven analysis. "
            "If measurements show positive trends (e.g., increased lean mass, decreased body fat), celebrate those wins. "
            "If there are concerning trends, provide constructive feedback and suggestions for improvement. "
            "Always consider the user's gender and age in your analysis. "
            "IMPORTANT: Do not use markdown formatting in your reports. Do not use ** for bold text or ### for titles. "
            "Write in plain text format only."
        ),
        model="openai/gpt-4o",
        memory=memory,
        debug=True,
    )

    return agent
