"""
Body measurement service.

Handles CRUD operations for body measurements and automatic body fat calculation.
"""

from uuid import UUID
from datetime import datetime
from typing import Optional, List
from sqlalchemy.orm import Session
from sqlalchemy import and_, desc

from app.models.body_measurement import BodyMeasurement
from app.models.user import User
from app.services.body_fat_calculator import BodyFatCalculator


class BodyMeasurementService:
    """Service for managing body measurements."""

    def __init__(self, db: Session):
        self.db = db
        self.calculator = BodyFatCalculator()

    def create_measurement(
        self,
        user_id: UUID,
        measured_at: datetime,
        height_cm: float,
        weight_kg: float,
        neck_cm: float,
        waist_cm: float,
        hip_cm: Optional[float] = None,
        chest_cm: Optional[float] = None,
        shoulder_cm: Optional[float] = None,
        bicep_cm: Optional[float] = None,
        forearm_cm: Optional[float] = None,
        thigh_cm: Optional[float] = None,
        calf_cm: Optional[float] = None,
    ) -> BodyMeasurement:
        """
        Create a new body measurement with automatic body fat calculation.

        Args:
            user_id: User ID
            measured_at: Date/time of measurement
            height_cm: Height in centimeters
            weight_kg: Weight in kilograms
            neck_cm: Neck circumference in centimeters
            waist_cm: Waist circumference in centimeters
            hip_cm: Hip circumference (required for women)
            chest_cm: Chest circumference (optional)
            shoulder_cm: Shoulder circumference (optional)
            bicep_cm: Bicep circumference (optional)
            forearm_cm: Forearm circumference (optional)
            thigh_cm: Thigh circumference (optional)
            calf_cm: Calf circumference (optional)

        Returns:
            Created BodyMeasurement object

        Raises:
            ValueError: If user not found, invalid gender, or missing required measurements
        """
        # Get user to check gender (required for body fat calculation)
        # Body fat calculation uses different formulas for men vs women
        user = self.db.query(User).filter(User.user_id == user_id).first()
        if not user:
            raise ValueError(f"User {user_id} not found")

        if not user.gender:
            raise ValueError("User gender must be set before creating measurements")

        # Validate required measurements
        # All measurements must be positive values for valid calculations
        if height_cm <= 0 or weight_kg <= 0 or neck_cm <= 0 or waist_cm <= 0:
            raise ValueError("Height, weight, neck, and waist must be positive values")

        # Sanity check: waist should be larger than neck
        # This prevents invalid measurements that would produce incorrect body fat %
        if waist_cm <= neck_cm:
            raise ValueError("Waist must be greater than neck circumference")

        # For women, hip is required
        if user.gender == "female" and hip_cm is None:
            raise ValueError("Hip measurement is required for women")

        if user.gender == "female" and hip_cm is not None:
            if hip_cm <= waist_cm:
                raise ValueError("Hip must be greater than waist circumference")

        # Calculate body fat percentage
        body_fat_percentage = self.calculator.calculate_navy_body_fat(
            gender=user.gender,
            height_cm=height_cm,
            waist_cm=waist_cm,
            neck_cm=neck_cm,
            hip_cm=hip_cm,
        )

        # Calculate fat mass and lean mass
        fat_mass_kg = self.calculator.calculate_fat_mass(weight_kg, body_fat_percentage)
        lean_mass_kg = self.calculator.calculate_lean_mass(
            weight_kg, body_fat_percentage
        )

        # Create measurement
        measurement = BodyMeasurement(
            user_id=user_id,
            measured_at=measured_at,
            height_cm=height_cm,
            weight_kg=weight_kg,
            neck_cm=neck_cm,
            waist_cm=waist_cm,
            hip_cm=hip_cm,
            chest_cm=chest_cm,
            shoulder_cm=shoulder_cm,
            bicep_cm=bicep_cm,
            forearm_cm=forearm_cm,
            thigh_cm=thigh_cm,
            calf_cm=calf_cm,
            body_fat_percentage=body_fat_percentage,
            fat_mass_kg=fat_mass_kg,
            lean_mass_kg=lean_mass_kg,
        )

        self.db.add(measurement)
        self.db.commit()
        self.db.refresh(measurement)

        return measurement

    def get_measurements(
        self, user_id: UUID, limit: Optional[int] = None
    ) -> List[BodyMeasurement]:
        """
        Get user's measurement history, ordered by date (newest first).

        Args:
            user_id: User ID
            limit: Optional limit on number of results

        Returns:
            List of BodyMeasurement objects
        """
        query = (
            self.db.query(BodyMeasurement)
            .filter(BodyMeasurement.user_id == user_id)
            .order_by(desc(BodyMeasurement.measured_at))
        )

        if limit:
            query = query.limit(limit)

        return query.all()

    def get_latest_measurement(self, user_id: UUID) -> Optional[BodyMeasurement]:
        """
        Get user's most recent measurement.

        Args:
            user_id: User ID

        Returns:
            Most recent BodyMeasurement or None if no measurements exist
        """
        return (
            self.db.query(BodyMeasurement)
            .filter(BodyMeasurement.user_id == user_id)
            .order_by(desc(BodyMeasurement.measured_at))
            .first()
        )

    def get_measurement(
        self, measurement_id: UUID, user_id: UUID
    ) -> Optional[BodyMeasurement]:
        """
        Get a specific measurement by ID.

        Args:
            measurement_id: Measurement ID
            user_id: User ID (for authorization)

        Returns:
            BodyMeasurement or None if not found
        """
        return (
            self.db.query(BodyMeasurement)
            .filter(
                and_(
                    BodyMeasurement.measurement_id == measurement_id,
                    BodyMeasurement.user_id == user_id,
                )
            )
            .first()
        )

    def update_measurement(
        self,
        measurement_id: UUID,
        user_id: UUID,
        measured_at: Optional[datetime] = None,
        height_cm: Optional[float] = None,
        weight_kg: Optional[float] = None,
        neck_cm: Optional[float] = None,
        waist_cm: Optional[float] = None,
        hip_cm: Optional[float] = None,
        chest_cm: Optional[float] = None,
        shoulder_cm: Optional[float] = None,
        bicep_cm: Optional[float] = None,
        forearm_cm: Optional[float] = None,
        thigh_cm: Optional[float] = None,
        calf_cm: Optional[float] = None,
    ) -> BodyMeasurement:
        """
        Update an existing measurement and recalculate body fat.

        Args:
            measurement_id: Measurement ID
            user_id: User ID (for authorization)
            measured_at: New measurement date/time (optional)
            height_cm: New height (optional)
            weight_kg: New weight (optional)
            neck_cm: New neck measurement (optional)
            waist_cm: New waist measurement (optional)
            hip_cm: New hip measurement (optional)
            chest_cm: New chest measurement (optional)
            shoulder_cm: New shoulder measurement (optional)
            bicep_cm: New bicep measurement (optional)
            forearm_cm: New forearm measurement (optional)
            thigh_cm: New thigh measurement (optional)
            calf_cm: New calf measurement (optional)

        Returns:
            Updated BodyMeasurement object

        Raises:
            ValueError: If measurement not found or invalid data
        """
        measurement = self.get_measurement(measurement_id, user_id)
        if not measurement:
            raise ValueError(f"Measurement {measurement_id} not found")

        # Get user for gender
        user = self.db.query(User).filter(User.user_id == user_id).first()
        if not user or not user.gender:
            raise ValueError("User gender must be set")

        # Update fields if provided
        if measured_at is not None:
            measurement.measured_at = measured_at
        if height_cm is not None:
            measurement.height_cm = height_cm
        if weight_kg is not None:
            measurement.weight_kg = weight_kg
        if neck_cm is not None:
            measurement.neck_cm = neck_cm
        if waist_cm is not None:
            measurement.waist_cm = waist_cm
        if hip_cm is not None:
            measurement.hip_cm = hip_cm
        if chest_cm is not None:
            measurement.chest_cm = chest_cm
        if shoulder_cm is not None:
            measurement.shoulder_cm = shoulder_cm
        if bicep_cm is not None:
            measurement.bicep_cm = bicep_cm
        if forearm_cm is not None:
            measurement.forearm_cm = forearm_cm
        if thigh_cm is not None:
            measurement.thigh_cm = thigh_cm
        if calf_cm is not None:
            measurement.calf_cm = calf_cm

        # Recalculate body fat with updated values
        body_fat_percentage = self.calculator.calculate_navy_body_fat(
            gender=user.gender,
            height_cm=measurement.height_cm,
            waist_cm=measurement.waist_cm,
            neck_cm=measurement.neck_cm,
            hip_cm=measurement.hip_cm,
        )

        measurement.body_fat_percentage = body_fat_percentage
        measurement.fat_mass_kg = self.calculator.calculate_fat_mass(
            measurement.weight_kg, body_fat_percentage
        )
        measurement.lean_mass_kg = self.calculator.calculate_lean_mass(
            measurement.weight_kg, body_fat_percentage
        )

        self.db.commit()
        self.db.refresh(measurement)

        return measurement

    def delete_measurement(self, measurement_id: UUID, user_id: UUID) -> bool:
        """
        Delete a measurement.

        Args:
            measurement_id: Measurement ID
            user_id: User ID (for authorization)

        Returns:
            True if deleted, False if not found

        Raises:
            ValueError: If measurement doesn't belong to user
        """
        measurement = self.get_measurement(measurement_id, user_id)
        if not measurement:
            return False

        self.db.delete(measurement)
        self.db.commit()

        return True
