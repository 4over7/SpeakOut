#!/bin/bash
set -e

APP_NAME="SpeakOut"
SOURCE_APP="build/macos/Build/Products/Release/${APP_NAME}.app"
DEST_DIR="/Applications"
DEST_APP="${DEST_DIR}/${APP_NAME}.app"

# Check if source exists
if [ ! -d "$SOURCE_APP" ]; then
    echo "Error: Source app not found at $SOURCE_APP"
    echo "Please build the app first."
    exit 1
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
    # Ad-hoc sign the library to satisfy hardened runtime/gatekeeper
    codesign -f -s - "$NATIVE_LIB_DEST/libnative_input.dylib"
else
    echo "⚠️ Warning: Native library not found at $NATIVE_LIB_SRC"
fi

echo "Installing ${APP_NAME} to ${DEST_DIR}..."

# Remove existing app
if [ -d "$DEST_APP" ]; then
    echo "Removing existing version..."
    rm -rf "${DEST_APP}"
fi

# Copy new app
echo "Copying to Applications..."
cp -R "$SOURCE_APP" "$DEST_DIR/"

# Optional: Clear quarantine if needed (usually not for local builds, but good practice)
# xattr -cr "$DEST_APP"

echo "✅ Success! ${APP_NAME} has been installed to /Applications."
echo "You can launch it via Spotlight or Launchpad."
