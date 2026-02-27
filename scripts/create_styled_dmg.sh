#!/bin/bash
set -e

APP_NAME="SpeakOut"
DMG_NAME="SpeakOut.dmg"
DMG_TEMP="SpeakOut_temp.dmg"
VOLUME_NAME="SpeakOut"
STAGING_DIR="build/dmg_staging"
SIGN_IDENTITY="Apple Development: 4over7@gmail.com (G6X3766L63)"

PWD=$(pwd)
DMG_TEMP_PATH="${PWD}/${DMG_TEMP}"
DMG_FINAL_PATH="${PWD}/${DMG_NAME}"

# 1. Cleanup
echo "Cleaning up..."
hdiutil detach "/Volumes/${VOLUME_NAME}" -force >/dev/null 2>&1 || true
rm -f "${DMG_TEMP_PATH}" "${DMG_FINAL_PATH}"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

# 2. Prepare Staging
echo "Preparing files..."
cp -R "build/macos/Build/Products/Release/${APP_NAME}.app" "${STAGING_DIR}/"
# Injection: Copy Dylib to App Bundle
mkdir -p "${STAGING_DIR}/${APP_NAME}.app/Contents/MacOS/native_lib"
cp "native_lib/libnative_input.dylib" "${STAGING_DIR}/${APP_NAME}.app/Contents/MacOS/native_lib/"

ln -s /Applications "${STAGING_DIR}/Applications"

# 2.5. Code Sign
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "Signing with: $SIGN_IDENTITY"
    codesign -f -s "$SIGN_IDENTITY" "${STAGING_DIR}/${APP_NAME}.app/Contents/MacOS/native_lib/libnative_input.dylib"
    codesign -f --deep -s "$SIGN_IDENTITY" "${STAGING_DIR}/${APP_NAME}.app"
else
    echo "⚠️  Signing identity not found, using ad-hoc signing"
    codesign -f -s "-" "${STAGING_DIR}/${APP_NAME}.app/Contents/MacOS/native_lib/libnative_input.dylib"
    codesign -f --deep -s "-" "${STAGING_DIR}/${APP_NAME}.app"
fi

# 3. Create Temp DMG
echo "Creating temp DMG..."
hdiutil create -volname "${VOLUME_NAME}" -srcfolder "${STAGING_DIR}" -format UDRW -ov "${DMG_TEMP_PATH}"
sleep 2

# 4. Attach & Style
echo "Styling..."
hdiutil attach -readwrite -noverify "${DMG_TEMP_PATH}"
sleep 2

osascript <<EOF
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 100, 960, 500}
        delay 1
        
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 144
        set background color of viewOptions to {55000, 55000, 55000}
        
        set position of item "${APP_NAME}.app" to {180, 200}
        set position of item "Applications" to {420, 200}
        
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

sync
sleep 2

echo "Detaching..."
hdiutil detach "/Volumes/${VOLUME_NAME}" -force

# 5. Convert
echo "Finalizing..."
hdiutil convert "${DMG_TEMP_PATH}" -format UDZO -o "${DMG_FINAL_PATH}"
rm -f "${DMG_TEMP_PATH}"

echo "Done: ${DMG_FINAL_PATH}"
