#!/bin/bash
# Backend test runner with coverage reporting

cd backend || exit 1

echo "Running backend tests with coverage..."
pytest --cov=app --cov-report=term-missing --cov-report=html --cov-report=xml

echo ""
echo "Coverage reports generated:"
echo "  - Terminal: See above"
echo "  - HTML: backend/htmlcov/index.html"
echo "  - XML: backend/coverage.xml"

