#!/bin/bash
set -e

APP_NAME="SpeakOut"
SOURCE_APP="build/macos/Build/Products/Release/${APP_NAME}.app"
DEST_DIR="/Applications"
DEST_APP="${DEST_DIR}/${APP_NAME}.app"
SIGN_IDENTITY="Apple Development: 4over7@gmail.com (G6X3766L63)"

# Build first
echo "🔨 Building ${APP_NAME} (Release)..."
flutter build macos --release
if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

# Check if source exists
if [ ! -d "$SOURCE_APP" ]; then
    echo "Error: Source app not found at $SOURCE_APP"
    echo "Please build the app first."
    exit 1
fi

# Verify signing identity exists
if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "⚠️  Signing identity not found: $SIGN_IDENTITY"
    echo "   Falling back to ad-hoc signing (permissions will reset on reinstall)"
    SIGN_IDENTITY="-"
fi

# Check if running and kill
if pgrep -x "$APP_NAME" > /dev/null; then
    echo "⚠️  $APP_NAME is running. Quitting it now..."
    killall "$APP_NAME" || true
    sleep 2 # Wait for it to close
fi

# Inject Native Lib (Fix White Screen Crash)
NATIVE_LIB_SRC="native_lib/libnative_input.dylib"
NATIVE_LIB_DEST="$SOURCE_APP/Contents/MacOS/native_lib"

if [ -f "$NATIVE_LIB_SRC" ]; then
    echo "Injecting native library into Bundle..."
    mkdir -p "$NATIVE_LIB_DEST"
    cp "$NATIVE_LIB_SRC" "$NATIVE_LIB_DEST/"
else
    echo "⚠️ Warning: Native library not found at $NATIVE_LIB_SRC"
fi

# Code sign: inner components first, then the app bundle
# This ensures TCC (permission database) recognizes the same identity across reinstalls
echo "Signing with: $SIGN_IDENTITY"
codesign -f -s "$SIGN_IDENTITY" "$NATIVE_LIB_DEST/libnative_input.dylib"
codesign -f --deep -s "$SIGN_IDENTITY" "$SOURCE_APP"

echo "Installing ${APP_NAME} to ${DEST_DIR}..."

# Remove existing app
if [ -d "$DEST_APP" ]; then
    echo "Removing existing version..."
    rm -rf "${DEST_APP}"
fi

# Copy new app
echo "Copying to Applications..."
cp -R "$SOURCE_APP" "$DEST_DIR/"

echo "✅ Success! ${APP_NAME} has been installed to /Applications."
echo "You can launch it via Spotlight or Launchpad."
