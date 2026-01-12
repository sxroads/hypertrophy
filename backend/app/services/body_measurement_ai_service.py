"""
AI report generation service for body measurements.

Generates personalized analysis reports comparing new measurements to previous ones.
"""

from uuid import UUID
from typing import List
from sqlalchemy.orm import Session

from app.models.body_measurement import BodyMeasurement
from app.models.user import User
from app.services.body_measurement_service import BodyMeasurementService
from app.services.ai_agent_service import get_body_measurement_agent
from upsonic import Task


class BodyMeasurementAIService:
    """Service for generating AI reports for body measurements."""

    def __init__(self, db: Session):
        self.db = db
        self.measurement_service = BodyMeasurementService(db)

    def generate_measurement_report(self, user_id: UUID, measurement_id: UUID) -> str:
        """
        Generate an AI report analyzing a body measurement.

        Compares the measurement to previous measurements and provides insights.

        Args:
            user_id: User ID
            measurement_id: Measurement ID to analyze

        Returns:
            AI-generated report text
        """
        # Get the current measurement
        current_measurement = self.measurement_service.get_measurement(
            measurement_id, user_id
        )
        if not current_measurement:
            raise ValueError(f"Measurement {measurement_id} not found")

        # Get user info
        user = self.db.query(User).filter(User.user_id == user_id).first()
        if not user:
            raise ValueError(f"User {user_id} not found")

        # Get previous measurements for comparison
        all_measurements = self.measurement_service.get_measurements(user_id, limit=10)
        previous_measurements = [
            m for m in all_measurements if m.measurement_id != measurement_id
        ]

        # Format measurement data for AI
        measurement_data = self._format_measurement_data_for_ai(
            current_measurement, previous_measurements, user
        )

        # Create prompt
        prompt = (
            f"User's body measurement data:\n{measurement_data}\n\n"
            "Please analyze this data and generate a detailed body composition report. "
            "Compare the current measurement to previous measurements, highlighting changes in: "
            "- Body fat percentage (increase/decrease and what it means) "
            "- Fat mass and lean mass changes "
            "- Circumference measurements (waist, hip, chest, etc.) "
            "- Overall body composition trends "
            "Provide actionable insights and recommendations based on the data. "
            "Be encouraging and supportive while being honest about the results. "
            "IMPORTANT: Do not use markdown formatting in your report. Do not use ** for bold text or ### for titles. "
            "Write in plain text format only."
            "If the user has no previous measurements, say so and that this is the user's first measurement."
            "Additionally, avoid generic or vague advice such as 'just keep working out' or 'keep it up.'"
            "Instead, offer specific feedback based on the user's body part measurements."
            "For example, if some measurements (like arms, upper body, or legs) are improving while others are lagging behind,"
            "mention this in your report. Suggest that the user might want to adjust their routine to address areas that are not progressing as well."
            "Help identify strengths and weaknesses for different body sections and recommend targeted improvements."
        )

        # Get agent and generate report
        agent = get_body_measurement_agent(user_id)
        task = Task(prompt)
        result = agent.do(task)

        return str(result)

    def _format_measurement_data_for_ai(
        self,
        current: BodyMeasurement,
        previous: List[BodyMeasurement],
        user: User,
    ) -> str:
        """
        Format measurement data for AI agent prompt.

        Args:
            current: Current measurement
            previous: List of previous measurements
            user: User object

        Returns:
            Formatted string with measurement data
        """
        lines = []

        # User info
        lines.append("User Profile:")
        lines.append(f"  Gender: {user.gender}")
        if user.age:
            lines.append(f"  Age: {user.age} years")
        lines.append("")

        # Current measurement
        lines.append(
            f"Current Measurement (Date: {current.measured_at.strftime('%Y-%m-%d')}):"
        )
        lines.append(f"  Height: {current.height_cm} cm")
        lines.append(f"  Weight: {current.weight_kg} kg")
        lines.append(f"  Body Fat %: {current.body_fat_percentage}%")
        lines.append(f"  Fat Mass: {current.fat_mass_kg} kg")
        lines.append(f"  Lean Mass: {current.lean_mass_kg} kg")
        lines.append(f"  Neck: {current.neck_cm} cm")
        lines.append(f"  Waist: {current.waist_cm} cm")
        if current.hip_cm:
            lines.append(f"  Hip: {current.hip_cm} cm")
        if current.chest_cm:
            lines.append(f"  Chest: {current.chest_cm} cm")
        if current.shoulder_cm:
            lines.append(f"  Shoulder: {current.shoulder_cm} cm")
        if current.bicep_cm:
            lines.append(f"  Bicep: {current.bicep_cm} cm")
        if current.forearm_cm:
            lines.append(f"  Forearm: {current.forearm_cm} cm")
        if current.thigh_cm:
            lines.append(f"  Thigh: {current.thigh_cm} cm")
        if current.calf_cm:
            lines.append(f"  Calf: {current.calf_cm} cm")
        lines.append("")

        # Previous measurements for comparison
        if previous:
            lines.append("Previous Measurements (for comparison):")
            for prev in previous[:3]:  # Show up to 3 previous measurements
                lines.append(
                    f"  {prev.measured_at.strftime('%Y-%m-%d')}: "
                    f"Weight {prev.weight_kg} kg, "
                    f"Body Fat {prev.body_fat_percentage}%, "
                    f"Fat Mass {prev.fat_mass_kg} kg, "
                    f"Lean Mass {prev.lean_mass_kg} kg"
                )

            # Calculate changes from most recent previous measurement
            if len(previous) > 0:
                most_recent = previous[0]
                lines.append("")
                lines.append("Changes from Previous Measurement:")
                weight_change = current.weight_kg - most_recent.weight_kg
                bfp_change = (
                    current.body_fat_percentage - most_recent.body_fat_percentage
                )
                fat_mass_change = current.fat_mass_kg - most_recent.fat_mass_kg
                lean_mass_change = current.lean_mass_kg - most_recent.lean_mass_kg

                lines.append(f"  Weight: {weight_change:+.2f} kg")
                lines.append(f"  Body Fat %: {bfp_change:+.2f}%")
                lines.append(f"  Fat Mass: {fat_mass_change:+.2f} kg")
                lines.append(f"  Lean Mass: {lean_mass_change:+.2f} kg")

                if current.waist_cm and most_recent.waist_cm:
                    waist_change = current.waist_cm - most_recent.waist_cm
                    lines.append(f"  Waist: {waist_change:+.2f} cm")
                if current.hip_cm and most_recent.hip_cm:
                    hip_change = current.hip_cm - most_recent.hip_cm
                    lines.append(f"  Hip: {hip_change:+.2f} cm")
        else:
            lines.append(
                "This is the user's first measurement - no previous data for comparison."
            )

        return "\n".join(lines)
