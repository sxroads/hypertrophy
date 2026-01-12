#!/bin/bash
# Frontend test runner with coverage reporting

echo "Running Flutter tests with coverage..."
flutter test --coverage

echo ""
echo "Coverage report generated:"
echo "  - LCOV: coverage/lcov.info"
echo "  - HTML: coverage/index.html (if generated)"

