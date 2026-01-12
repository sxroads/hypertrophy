"""
Body measurement endpoints.

Handles CRUD operations for body measurements and AI report generation.
"""

from uuid import UUID
from datetime import datetime
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, status, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.services.body_measurement_service import BodyMeasurementService
from app.services.body_measurement_ai_service import BodyMeasurementAIService
from app.utils.auth import get_current_user_id, get_optional_user_id

router = APIRouter()


class MeasurementCreateRequest(BaseModel):
    """Request model for creating a measurement."""

    measured_at: datetime = Field(..., description="Date/time of measurement")
    height_cm: float = Field(..., gt=0, description="Height in centimeters")
    weight_kg: float = Field(..., gt=0, description="Weight in kilograms")
    neck_cm: float = Field(..., gt=0, description="Neck circumference in centimeters")
    waist_cm: float = Field(..., gt=0, description="Waist circumference in centimeters")
    hip_cm: Optional[float] = Field(
        None, gt=0, description="Hip circumference (required for women)"
    )
    chest_cm: Optional[float] = Field(None, gt=0, description="Chest circumference")
    shoulder_cm: Optional[float] = Field(
        None, gt=0, description="Shoulder circumference"
    )
    bicep_cm: Optional[float] = Field(None, gt=0, description="Bicep circumference")
    forearm_cm: Optional[float] = Field(None, gt=0, description="Forearm circumference")
    thigh_cm: Optional[float] = Field(None, gt=0, description="Thigh circumference")
    calf_cm: Optional[float] = Field(None, gt=0, description="Calf circumference")


class MeasurementUpdateRequest(BaseModel):
    """Request model for updating a measurement."""

    measured_at: Optional[datetime] = None
    height_cm: Optional[float] = Field(None, gt=0)
    weight_kg: Optional[float] = Field(None, gt=0)
    neck_cm: Optional[float] = Field(None, gt=0)
    waist_cm: Optional[float] = Field(None, gt=0)
    hip_cm: Optional[float] = Field(None, gt=0)
    chest_cm: Optional[float] = Field(None, gt=0)
    shoulder_cm: Optional[float] = Field(None, gt=0)
    bicep_cm: Optional[float] = Field(None, gt=0)
    forearm_cm: Optional[float] = Field(None, gt=0)
    thigh_cm: Optional[float] = Field(None, gt=0)
    calf_cm: Optional[float] = Field(None, gt=0)


class MeasurementResponse(BaseModel):
    """Response model for a measurement."""

    measurement_id: UUID
    user_id: UUID
    measured_at: datetime
    height_cm: float
    weight_kg: float
    neck_cm: float
    waist_cm: float
    hip_cm: Optional[float]
    chest_cm: Optional[float]
    shoulder_cm: Optional[float]
    bicep_cm: Optional[float]
    forearm_cm: Optional[float]
    thigh_cm: Optional[float]
    calf_cm: Optional[float]
    body_fat_percentage: Optional[float]
    fat_mass_kg: Optional[float]
    lean_mass_kg: Optional[float]
    created_at: datetime

    class Config:
        from_attributes = True


class MeasurementReportResponse(BaseModel):
    """Response model for AI measurement report."""

    measurement_id: UUID
    report_text: str


@router.post(
    "/measurements",
    response_model=MeasurementResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_measurement(
    request: MeasurementCreateRequest,
    current_user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Create a new body measurement.

    Automatically calculates body fat percentage, fat mass, and lean mass.
    Generates an AI report automatically.

    Requires authentication.
    """
    service = BodyMeasurementService(db)

    try:
        measurement = service.create_measurement(
            user_id=current_user_id,
            measured_at=request.measured_at,
            height_cm=request.height_cm,
            weight_kg=request.weight_kg,
            neck_cm=request.neck_cm,
            waist_cm=request.waist_cm,
            hip_cm=request.hip_cm,
            chest_cm=request.chest_cm,
            shoulder_cm=request.shoulder_cm,
            bicep_cm=request.bicep_cm,
            forearm_cm=request.forearm_cm,
            thigh_cm=request.thigh_cm,
            calf_cm=request.calf_cm,
        )

        return MeasurementResponse.from_orm(measurement)

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create measurement: {str(e)}",
        )


@router.get(
    "/measurements",
    response_model=List[MeasurementResponse],
    status_code=status.HTTP_200_OK,
)
async def get_measurements(
    user_id: UUID = Query(..., description="User ID"),
    limit: Optional[int] = Query(
        None, ge=1, le=100, description="Maximum number of results"
    ),
    authenticated_user_id: Optional[UUID] = Depends(get_optional_user_id),
    db: Session = Depends(get_db),
):
    """
    Get user's measurement history.

    Supports both authenticated and anonymous users.
    If authenticated, user_id must match authenticated user.
    """
    # Ownership validation
    if authenticated_user_id is not None:
        if user_id != authenticated_user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="user_id does not match authenticated user",
            )

    try:
        service = BodyMeasurementService(db)
        measurements = service.get_measurements(user_id, limit=limit)

        return [MeasurementResponse.from_orm(m) for m in measurements]
    except HTTPException:
        raise
    except Exception as e:
        import traceback

        print(f"[ERROR] get_measurements failed: {e}")
        print(traceback.format_exc())
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get measurements: {str(e)}. Please ensure database migration 006_add_body_measurements has been run.",
        )


@router.get(
    "/measurements/latest",
    response_model=MeasurementResponse,
    status_code=status.HTTP_200_OK,
)
async def get_latest_measurement(
    user_id: UUID = Query(..., description="User ID"),
    authenticated_user_id: Optional[UUID] = Depends(get_optional_user_id),
    db: Session = Depends(get_db),
):
    """
    Get user's most recent measurement.

    Returns 404 if no measurements exist.
    """
    try:
        # Ownership validation
        if authenticated_user_id is not None:
            if user_id != authenticated_user_id:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="user_id does not match authenticated user",
                )

        service = BodyMeasurementService(db)
        measurement = service.get_latest_measurement(user_id)

        if not measurement:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No measurements found for user",
            )

        return MeasurementResponse.from_orm(measurement)
    except HTTPException:
        raise
    except Exception as e:
        import traceback

        print(f"[ERROR] get_latest_measurement failed: {e}")
        print(traceback.format_exc())
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get latest measurement: {str(e)}. Please ensure database migration 006_add_body_measurements has been run.",
        )


@router.get(
    "/measurements/{measurement_id}",
    response_model=MeasurementResponse,
    status_code=status.HTTP_200_OK,
)
async def get_measurement(
    measurement_id: UUID,
    current_user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Get a specific measurement by ID.

    Requires authentication. User can only access their own measurements.
    """
    service = BodyMeasurementService(db)
    measurement = service.get_measurement(measurement_id, current_user_id)

    if not measurement:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Measurement not found",
        )

    return MeasurementResponse.from_orm(measurement)


@router.put(
    "/measurements/{measurement_id}",
    response_model=MeasurementResponse,
    status_code=status.HTTP_200_OK,
)
async def update_measurement(
    measurement_id: UUID,
    request: MeasurementUpdateRequest,
    current_user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Update an existing measurement.

    Recalculates body fat percentage and related metrics automatically.
    Requires authentication.
    """
    service = BodyMeasurementService(db)

    try:
        measurement = service.update_measurement(
            measurement_id=measurement_id,
            user_id=current_user_id,
            measured_at=request.measured_at,
            height_cm=request.height_cm,
            weight_kg=request.weight_kg,
            neck_cm=request.neck_cm,
            waist_cm=request.waist_cm,
            hip_cm=request.hip_cm,
            chest_cm=request.chest_cm,
            shoulder_cm=request.shoulder_cm,
            bicep_cm=request.bicep_cm,
            forearm_cm=request.forearm_cm,
            thigh_cm=request.thigh_cm,
            calf_cm=request.calf_cm,
        )

        return MeasurementResponse.from_orm(measurement)

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update measurement: {str(e)}",
        )


@router.delete(
    "/measurements/{measurement_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_measurement(
    measurement_id: UUID,
    current_user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Delete a measurement.

    Requires authentication.
    """
    service = BodyMeasurementService(db)
    deleted = service.delete_measurement(measurement_id, current_user_id)

    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Measurement not found",
        )


@router.get(
    "/measurements/{measurement_id}/report",
    response_model=MeasurementReportResponse,
    status_code=status.HTTP_200_OK,
)
async def get_measurement_report(
    measurement_id: UUID,
    current_user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Get AI-generated report for a measurement.

    Compares the measurement to previous measurements and provides insights.
    Requires authentication.
    """
    ai_service = BodyMeasurementAIService(db)

    try:
        report_text = ai_service.generate_measurement_report(
            current_user_id, measurement_id
        )

        return MeasurementReportResponse(
            measurement_id=measurement_id,
            report_text=report_text,
        )

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate report: {str(e)}",
        )
