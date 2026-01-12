"""
Unit tests for BodyFatCalculator service.

Tests all calculation methods and edge cases.
"""

import pytest
from app.services.body_fat_calculator import BodyFatCalculator


class TestNavyBodyFatCalculation:
    """Tests for Navy body fat percentage calculation."""

    def test_calculate_navy_body_fat_male_valid(self):
        """Valid male measurements return correct BFP."""
        bfp = BodyFatCalculator.calculate_navy_body_fat(
            gender="male",
            height_cm=180.0,
            waist_cm=90.0,
            neck_cm=40.0,
        )
        assert isinstance(bfp, float)
        assert 0 <= bfp <= 50  # Clamped range
        assert bfp > 0  # Should be positive for realistic measurements

    def test_calculate_navy_body_fat_female_valid(self):
        """Valid female measurements with hip return correct BFP."""
        bfp = BodyFatCalculator.calculate_navy_body_fat(
            gender="female",
            height_cm=165.0,
            waist_cm=75.0,
            neck_cm=35.0,
            hip_cm=95.0,
        )
        assert isinstance(bfp, float)
        assert 0 <= bfp <= 50  # Clamped range
        assert bfp > 0  # Should be positive for realistic measurements

    def test_calculate_navy_body_fat_invalid_gender(self):
        """Raises ValueError for invalid gender."""
        with pytest.raises(ValueError, match="Gender must be 'male' or 'female'"):
            BodyFatCalculator.calculate_navy_body_fat(
                gender="invalid",
                height_cm=180.0,
                waist_cm=90.0,
                neck_cm=40.0,
            )

    def test_calculate_navy_body_fat_negative_values(self):
        """Raises ValueError for negative measurements."""
        with pytest.raises(ValueError, match="must be positive"):
            BodyFatCalculator.calculate_navy_body_fat(
                gender="male",
                height_cm=-180.0,
                waist_cm=90.0,
                neck_cm=40.0,
            )

        with pytest.raises(ValueError, match="must be positive"):
            BodyFatCalculator.calculate_navy_body_fat(
                gender="male",
                height_cm=180.0,
                waist_cm=-90.0,
                neck_cm=40.0,
            )

        with pytest.raises(ValueError, match="must be positive"):
            BodyFatCalculator.calculate_navy_body_fat(
                gender="male",
                height_cm=180.0,
                waist_cm=90.0,
                neck_cm=-40.0,
            )

    def test_calculate_navy_body_fat_zero_values(self):
        """Raises ValueError for zero measurements."""
        with pytest.raises(ValueError, match="must be positive"):
            BodyFatCalculator.calculate_navy_body_fat(
                gender="male",
                height_cm=0.0,
                waist_cm=90.0,
                neck_cm=40.0,
            )

    def test_calculate_navy_body_fat_waist_less_than_neck(self):
        """Raises ValueError when waist <= neck."""
        with pytest.raises(ValueError, match="Waist must be greater than neck"):
            BodyFatCalculator.calculate_navy_body_fat(
                gender="male",
                height_cm=180.0,
                waist_cm=40.0,
                neck_cm=40.0,
            )

        with pytest.raises(ValueError, match="Waist must be greater than neck"):
            BodyFatCalculator.calculate_navy_body_fat(
                gender="male",
                height_cm=180.0,
                waist_cm=35.0,
                neck_cm=40.0,
            )

    def test_calculate_navy_body_fat_female_missing_hip(self):
        """Raises ValueError when female missing hip."""
        with pytest.raises(ValueError, match="Hip measurement is required for women"):
            BodyFatCalculator.calculate_navy_body_fat(
                gender="female",
                height_cm=165.0,
                waist_cm=75.0,
                neck_cm=35.0,
                hip_cm=None,
            )

    def test_calculate_navy_body_fat_female_hip_less_than_waist(self):
        """Raises ValueError when hip <= waist."""
        with pytest.raises(ValueError, match="Hip must be greater than waist"):
            BodyFatCalculator.calculate_navy_body_fat(
                gender="female",
                height_cm=165.0,
                waist_cm=75.0,
                neck_cm=35.0,
                hip_cm=75.0,
            )

        with pytest.raises(ValueError, match="Hip must be greater than waist"):
            BodyFatCalculator.calculate_navy_body_fat(
                gender="female",
                height_cm=165.0,
                waist_cm=75.0,
                neck_cm=35.0,
                hip_cm=70.0,
            )

    def test_calculate_navy_body_fat_female_negative_hip(self):
        """Raises ValueError for negative hip measurement."""
        with pytest.raises(ValueError, match="Hip must be a positive value"):
            BodyFatCalculator.calculate_navy_body_fat(
                gender="female",
                height_cm=165.0,
                waist_cm=75.0,
                neck_cm=35.0,
                hip_cm=-95.0,
            )

    def test_calculate_navy_body_fat_clamping(self):
        """Results clamped to 0-50% range."""
        # Test with extreme values that would produce out-of-range results
        # Very low body fat scenario
        bfp_low = BodyFatCalculator.calculate_navy_body_fat(
            gender="male",
            height_cm=190.0,
            waist_cm=70.0,
            neck_cm=38.0,
        )
        assert 0 <= bfp_low <= 50

        # Very high body fat scenario
        bfp_high = BodyFatCalculator.calculate_navy_body_fat(
            gender="male",
            height_cm=170.0,
            waist_cm=120.0,
            neck_cm=45.0,
        )
        assert 0 <= bfp_high <= 50

    def test_calculate_navy_body_fat_precision(self):
        """Results are rounded to 2 decimal places."""
        bfp = BodyFatCalculator.calculate_navy_body_fat(
            gender="male",
            height_cm=180.0,
            waist_cm=90.0,
            neck_cm=40.0,
        )
        # Check that result has at most 2 decimal places
        decimal_places = str(bfp).split(".")[-1] if "." in str(bfp) else ""
        assert len(decimal_places) <= 2


class TestBMIBodyFatCalculation:
    """Tests for BMI-based body fat percentage calculation."""

    def test_calculate_bmi_body_fat_male(self):
        """Valid male BMI calculation."""
        bfp = BodyFatCalculator.calculate_bmi_body_fat(
            gender="male",
            age=30,
            height_cm=180.0,
            weight_kg=80.0,
        )
        assert isinstance(bfp, float)
        assert 0 <= bfp <= 50  # Clamped range

    def test_calculate_bmi_body_fat_female(self):
        """Valid female BMI calculation."""
        bfp = BodyFatCalculator.calculate_bmi_body_fat(
            gender="female",
            age=25,
            height_cm=165.0,
            weight_kg=60.0,
        )
        assert isinstance(bfp, float)
        assert 0 <= bfp <= 50  # Clamped range

    def test_calculate_bmi_body_fat_invalid_gender(self):
        """Raises ValueError for invalid gender."""
        with pytest.raises(ValueError, match="Gender must be 'male' or 'female'"):
            BodyFatCalculator.calculate_bmi_body_fat(
                gender="invalid",
                age=30,
                height_cm=180.0,
                weight_kg=80.0,
            )

    def test_calculate_bmi_body_fat_invalid_inputs(self):
        """Raises ValueError for invalid inputs."""
        with pytest.raises(ValueError, match="must be positive"):
            BodyFatCalculator.calculate_bmi_body_fat(
                gender="male",
                age=-30,
                height_cm=180.0,
                weight_kg=80.0,
            )

        with pytest.raises(ValueError, match="must be positive"):
            BodyFatCalculator.calculate_bmi_body_fat(
                gender="male",
                age=30,
                height_cm=-180.0,
                weight_kg=80.0,
            )

        with pytest.raises(ValueError, match="must be positive"):
            BodyFatCalculator.calculate_bmi_body_fat(
                gender="male",
                age=30,
                height_cm=180.0,
                weight_kg=-80.0,
            )

        with pytest.raises(ValueError, match="must be positive"):
            BodyFatCalculator.calculate_bmi_body_fat(
                gender="male",
                age=0,
                height_cm=180.0,
                weight_kg=80.0,
            )

    def test_calculate_bmi_body_fat_clamping(self):
        """Results clamped to 0-50% range."""
        bfp = BodyFatCalculator.calculate_bmi_body_fat(
            gender="male",
            age=30,
            height_cm=180.0,
            weight_kg=80.0,
        )
        assert 0 <= bfp <= 50

    def test_calculate_bmi_body_fat_precision(self):
        """Results are rounded to 2 decimal places."""
        bfp = BodyFatCalculator.calculate_bmi_body_fat(
            gender="male",
            age=30,
            height_cm=180.0,
            weight_kg=80.0,
        )
        decimal_places = str(bfp).split(".")[-1] if "." in str(bfp) else ""
        assert len(decimal_places) <= 2


class TestFatMassCalculation:
    """Tests for fat mass calculation."""

    def test_calculate_fat_mass_valid(self):
        """Calculates fat mass correctly."""
        fat_mass = BodyFatCalculator.calculate_fat_mass(
            weight_kg=80.0,
            body_fat_percentage=20.0,
        )
        expected = 80.0 * (20.0 / 100.0)  # 16.0 kg
        assert fat_mass == expected
        assert isinstance(fat_mass, float)

    def test_calculate_fat_mass_zero_percentage(self):
        """Handles 0% body fat."""
        fat_mass = BodyFatCalculator.calculate_fat_mass(
            weight_kg=80.0,
            body_fat_percentage=0.0,
        )
        assert fat_mass == 0.0

    def test_calculate_fat_mass_100_percentage(self):
        """Handles 100% body fat."""
        fat_mass = BodyFatCalculator.calculate_fat_mass(
            weight_kg=80.0,
            body_fat_percentage=100.0,
        )
        assert fat_mass == 80.0

    def test_calculate_fat_mass_invalid_weight(self):
        """Raises ValueError for invalid weight."""
        with pytest.raises(ValueError, match="Weight must be positive"):
            BodyFatCalculator.calculate_fat_mass(
                weight_kg=-80.0,
                body_fat_percentage=20.0,
            )

        with pytest.raises(ValueError, match="Weight must be positive"):
            BodyFatCalculator.calculate_fat_mass(
                weight_kg=0.0,
                body_fat_percentage=20.0,
            )

    def test_calculate_fat_mass_invalid_percentage(self):
        """Raises ValueError for invalid percentage."""
        with pytest.raises(
            ValueError, match="Body fat percentage must be between 0 and 100"
        ):
            BodyFatCalculator.calculate_fat_mass(
                weight_kg=80.0,
                body_fat_percentage=-10.0,
            )

        with pytest.raises(
            ValueError, match="Body fat percentage must be between 0 and 100"
        ):
            BodyFatCalculator.calculate_fat_mass(
                weight_kg=80.0,
                body_fat_percentage=150.0,
            )

    def test_calculate_fat_mass_precision(self):
        """Results are rounded to 2 decimal places."""
        fat_mass = BodyFatCalculator.calculate_fat_mass(
            weight_kg=80.0,
            body_fat_percentage=20.5,
        )
        decimal_places = str(fat_mass).split(".")[-1] if "." in str(fat_mass) else ""
        assert len(decimal_places) <= 2


class TestLeanMassCalculation:
    """Tests for lean mass calculation."""

    def test_calculate_lean_mass_valid(self):
        """Calculates lean mass correctly."""
        lean_mass = BodyFatCalculator.calculate_lean_mass(
            weight_kg=80.0,
            body_fat_percentage=20.0,
        )
        fat_mass = 80.0 * (20.0 / 100.0)  # 16.0 kg
        expected = 80.0 - fat_mass  # 64.0 kg
        assert lean_mass == expected
        assert isinstance(lean_mass, float)

    def test_calculate_lean_mass_edge_cases(self):
        """Handles edge cases (0% BFP, 100% BFP)."""
        # 0% body fat - all weight is lean mass
        lean_mass_0 = BodyFatCalculator.calculate_lean_mass(
            weight_kg=80.0,
            body_fat_percentage=0.0,
        )
        assert lean_mass_0 == 80.0

        # 100% body fat - no lean mass
        lean_mass_100 = BodyFatCalculator.calculate_lean_mass(
            weight_kg=80.0,
            body_fat_percentage=100.0,
        )
        assert lean_mass_100 == 0.0

    def test_calculate_lean_mass_invalid_weight(self):
        """Raises ValueError for invalid weight."""
        with pytest.raises(ValueError, match="Weight must be positive"):
            BodyFatCalculator.calculate_lean_mass(
                weight_kg=-80.0,
                body_fat_percentage=20.0,
            )

    def test_calculate_lean_mass_invalid_percentage(self):
        """Raises ValueError for invalid percentage."""
        with pytest.raises(
            ValueError, match="Body fat percentage must be between 0 and 100"
        ):
            BodyFatCalculator.calculate_lean_mass(
                weight_kg=80.0,
                body_fat_percentage=-10.0,
            )

    def test_calculate_lean_mass_precision(self):
        """Results are rounded to 2 decimal places."""
        lean_mass = BodyFatCalculator.calculate_lean_mass(
            weight_kg=80.0,
            body_fat_percentage=20.5,
        )
        decimal_places = str(lean_mass).split(".")[-1] if "." in str(lean_mass) else ""
        assert len(decimal_places) <= 2

    def test_calculate_lean_mass_uses_fat_mass(self):
        """Lean mass calculation uses fat mass internally."""
        # Verify that lean mass = weight - fat mass
        weight = 80.0
        bfp = 20.0
        fat_mass = BodyFatCalculator.calculate_fat_mass(weight, bfp)
        lean_mass = BodyFatCalculator.calculate_lean_mass(weight, bfp)
        assert lean_mass == weight - fat_mass
