"""
AI Q&A endpoints.
"""

from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.services.qa_service import QAService
from app.services.workout_exercise_service import WorkoutExerciseService
from app.utils.auth import get_current_user_id

router = APIRouter()


class ChatRequest(BaseModel):
    """Chat request model."""

    question: str = Field(
        ..., description="User's question about workouts, form, or injuries"
    )


class ChatResponse(BaseModel):
    """Chat response model."""

    answer: str
    session_id: str


class WorkoutExerciseChatRequest(BaseModel):
    """Workout exercise chat request model."""

    exercise_id: UUID = Field(..., description="Exercise ID")
    exercise_name: str = Field(..., description="Exercise name")
    question: str = Field(..., description="User's question about the exercise")


@router.post(
    "/ai/chat",
    response_model=ChatResponse,
    status_code=status.HTTP_200_OK,
)
async def chat(
    request: ChatRequest,
    current_user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Answer a user's workout-related question using AI.

    Requires authentication. The AI agent has access to the user's workout history
    to provide personalized advice.

    Args:
        request: Chat request with question
        current_user_id: Authenticated user ID from JWT
        db: Database session

    Returns:
        AI-generated answer
    """
    if not request.question or not request.question.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Question cannot be empty",
        )

    try:
        qa_service = QAService(db)
        answer = qa_service.answer_question(current_user_id, request.question.strip())

        # Session ID is based on user_id for Q&A agent
        session_id = f"qa_{current_user_id}"

        return ChatResponse(
            answer=answer,
            session_id=session_id,
        )
    except Exception as e:
        print(f"[AI_CHAT] ERROR: Failed to generate answer: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate answer: {str(e)}",
        )


@router.post(
    "/ai/workout-exercise/chat",
    response_model=ChatResponse,
    status_code=status.HTTP_200_OK,
)
async def workout_exercise_chat(
    request: WorkoutExerciseChatRequest,
    current_user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Answer a user's question about a specific exercise during an active workout.

    Requires authentication. The AI agent has access to the user's workout history
    for the specific exercise to provide personalized, real-time advice.

    Args:
        request: Workout exercise chat request with exercise_id, exercise_name, and question
        current_user_id: Authenticated user ID from JWT
        db: Database session

    Returns:
        AI-generated answer
    """
    if not request.question or not request.question.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Question cannot be empty",
        )

    if not request.exercise_name or not request.exercise_name.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Exercise name cannot be empty",
        )

    try:
        workout_exercise_service = WorkoutExerciseService(db)
        answer = workout_exercise_service.answer_exercise_question(
            current_user_id,
            request.exercise_id,
            request.exercise_name.strip(),
            request.question.strip(),
        )

        # Session ID is based on user_id and exercise_id for workout exercise agent
        session_id = f"workout_exercise_{current_user_id}_{request.exercise_id}"

        return ChatResponse(
            answer=answer,
            session_id=session_id,
        )
    except Exception as e:
        print(f"[WORKOUT_EXERCISE_CHAT] ERROR: Failed to generate answer: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate answer: {str(e)}",
        )
