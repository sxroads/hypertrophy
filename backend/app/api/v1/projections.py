"""
Projection rebuild endpoint.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.services.projection_service import WorkoutProjectionBuilder


router = APIRouter()


@router.post("/projections/rebuild", status_code=status.HTTP_200_OK)
async def rebuild_projections(
    db: Session = Depends(get_db),
):
    """
    Rebuild all projections from events.
    
    Drops existing projections and replays full event log
    to produce identical projection state.
    """
    try:
        builder = WorkoutProjectionBuilder(db)
        builder.rebuild_projections()
        return {"message": "Projections rebuilt successfully"}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to rebuild projections: {str(e)}",
        )

