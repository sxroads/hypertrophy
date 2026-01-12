"""
Body fat calculator service.

Implements U.S. Navy body fat percentage formulas and BMI-based estimates.
All calculations use metric units (cm, kg).
"""

import math
from typing import Optional


class BodyFatCalculator:
    """Service for calculating body fat percentage using various methods."""

    @staticmethod
    def calculate_navy_body_fat(
        gender: str,
        height_cm: float,
        waist_cm: float,
        neck_cm: float,
        hip_cm: Optional[float] = None,
    ) -> float:
        """
        Calculate body fat percentage using U.S. Navy method.

        Args:
            gender: "male" or "female"
            height_cm: Height in centimeters
            waist_cm: Waist circumference in centimeters
            neck_cm: Neck circumference in centimeters
            hip_cm: Hip circumference in centimeters (required for women)

        Returns:
            Body fat percentage (0-100)

        Raises:
            ValueError: If inputs are invalid or missing required measurements
        """
        if gender not in ["male", "female"]:
            raise ValueError("Gender must be 'male' or 'female'")

        if height_cm <= 0 or waist_cm <= 0 or neck_cm <= 0:
            raise ValueError("Height, waist, and neck must be positive values")

        if waist_cm <= neck_cm:
            raise ValueError("Waist must be greater than neck circumference")

        if gender == "female":
            if hip_cm is None:
                raise ValueError("Hip measurement is required for women")
            if hip_cm <= 0:
                raise ValueError("Hip must be a positive value")
            if hip_cm <= waist_cm:
                raise ValueError("Hip must be greater than waist circumference")

        # Convert cm to inches for Navy formula
        height_in = height_cm / 2.54
        waist_in = waist_cm / 2.54
        neck_in = neck_cm / 2.54

        if gender == "male":
            # Navy formula for men: BFP = 86.010×log10(waist - neck) - 70.041×log10(height) + 36.76
            bfp = (
                86.010 * math.log10(waist_in - neck_in)
                - 70.041 * math.log10(height_in)
                + 36.76
            )
        else:  # female
            # Convert hip to inches
            hip_in = hip_cm / 2.54
            # Navy formula for women: BFP = 163.205×log10(waist + hip - neck) - 97.684×log10(height) - 78.387
            bfp = (
                163.205 * math.log10(waist_in + hip_in - neck_in)
                - 97.684 * math.log10(height_in)
                - 78.387
            )

        # Clamp to reasonable range (0-50% for realistic values)
        bfp = max(0.0, min(50.0, bfp))

        return round(bfp, 2)

    @staticmethod
    def calculate_bmi_body_fat(
        gender: str, age: int, height_cm: float, weight_kg: float
    ) -> float:
        """
        Calculate body fat percentage using BMI-based formula.

        Args:
            gender: "male" or "female"
            age: Age in years
            height_cm: Height in centimeters
            weight_kg: Weight in kilograms

        Returns:
            Body fat percentage (0-100)

        Raises:
            ValueError: If inputs are invalid
        """
        if gender not in ["male", "female"]:
            raise ValueError("Gender must be 'male' or 'female'")

        if height_cm <= 0 or weight_kg <= 0 or age <= 0:
            raise ValueError("Height, weight, and age must be positive values")

        # Calculate BMI: weight (kg) / height (m)²
        height_m = height_cm / 100.0
        bmi = weight_kg / (height_m * height_m)

        # BMI-based body fat formula
        if gender == "male":
            bfp = 1.20 * bmi + 0.23 * age - 16.2
        else:  # female
            bfp = 1.20 * bmi + 0.23 * age - 5.4

        # Clamp to reasonable range
        bfp = max(0.0, min(50.0, bfp))

        return round(bfp, 2)

    @staticmethod
    def calculate_fat_mass(weight_kg: float, body_fat_percentage: float) -> float:
        """
        Calculate fat mass from total weight and body fat percentage.

        Args:
            weight_kg: Total weight in kilograms
            body_fat_percentage: Body fat percentage (0-100)

        Returns:
            Fat mass in kilograms
        """
        if weight_kg <= 0:
            raise ValueError("Weight must be positive")
        if body_fat_percentage < 0 or body_fat_percentage > 100:
            raise ValueError("Body fat percentage must be between 0 and 100")

        fat_mass = weight_kg * (body_fat_percentage / 100.0)
        return round(fat_mass, 2)

    @staticmethod
    def calculate_lean_mass(weight_kg: float, body_fat_percentage: float) -> float:
        """
        Calculate lean body mass from total weight and body fat percentage.

        Args:
            weight_kg: Total weight in kilograms
            body_fat_percentage: Body fat percentage (0-100)

        Returns:
            Lean body mass in kilograms
        """
        if weight_kg <= 0:
            raise ValueError("Weight must be positive")
        if body_fat_percentage < 0 or body_fat_percentage > 100:
            raise ValueError("Body fat percentage must be between 0 and 100")

        fat_mass = BodyFatCalculator.calculate_fat_mass(weight_kg, body_fat_percentage)
        lean_mass = weight_kg - fat_mass
        return round(lean_mass, 2)
