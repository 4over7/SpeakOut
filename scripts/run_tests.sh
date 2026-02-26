#!/bin/bash
set -e

echo "--- 1. Static Analysis ---"
flutter analyze

echo "--- 2. Unit Tests ---"
flutter test

echo "--- 3. Integration Note ---"
echo "Audio/ASR tests require native libs and mic."
echo "Run manually: flutter run -d macos"
echo "All checks passed."
