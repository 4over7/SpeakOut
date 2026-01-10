#!/bin/bash
# Linus Style Test Runner
# Runs flutter analyze and unit tests.

echo "--- 1. Static Analysis ---"
flutter analyze
if [ $? -ne 0 ]; then
  echo "Analysis Failed!"
  exit 1
fi

echo "--- 2. Unit Tests ---"
flutter test test/core_engine_test.dart
if [ $? -ne 0 ]; then
  echo "Unit Tests Failed!"
  exit 1
fi

echo "--- 3. Integration Walkthrough ---"
echo "To verify audio and ASR (which requires native libs and mic),"
echo "please run the app manually: flutter run -d macos"
echo "Success."
exit 0
