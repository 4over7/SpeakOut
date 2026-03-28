#!/bin/bash
set -e

APP_NAME="SpeakOut"

# Auto-increment build number
CURRENT_BUILD=$(grep 'version:' pubspec.yaml | sed 's/.*+//')
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/+${CURRENT_BUILD}/+${NEW_BUILD}/" pubspec.yaml
echo "📦 Build number: ${CURRENT_BUILD} → ${NEW_BUILD}"

# Sync version to Gateway
VERSION=$(grep 'version:' pubspec.yaml | sed 's/version: //' | sed 's/+.*//')
# 只替换 /version 端点的版本号（第一个匹配），不影响支付宝等其他 version 字段
sed -i '' "0,/version: '.*'/s/version: '.*'/version: '${VERSION}'/" gateway/src/index.js
sed -i '' "s/build: [0-9]*/build: ${NEW_BUILD}/" gateway/src/index.js
sed -i '' "s|download/v[0-9.]*/SpeakOut.dmg|download/v${VERSION}/SpeakOut.dmg|" gateway/src/index.js
echo "🔄 Gateway synced: v${VERSION}+${NEW_BUILD}"

# Build
echo "🔨 Building ${APP_NAME} (Release)..."
flutter build macos --release
if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

DMG_NAME="SpeakOut.dmg"
DMG_TEMP="SpeakOut_temp.dmg"
VOLUME_NAME="SpeakOut"
STAGING_DIR="build/dmg_staging"
SIGN_IDENTITY="Developer ID Application: Lindan Wang (UB9D55S724)"

PWD=$(pwd)
DMG_TEMP_PATH="${PWD}/${DMG_TEMP}"
DMG_FINAL_PATH="${PWD}/${DMG_NAME}"

# 1. Cleanup — close Finder windows and eject ALL mounted SpeakOut volumes
echo "Cleaning up..."
osascript -e 'tell application "Finder" to close (every window whose name contains "SpeakOut")' 2>/dev/null || true
for vol in /Volumes/SpeakOut*; do
  [ -d "$vol" ] && hdiutil detach "$vol" -force >/dev/null 2>&1 || true
done
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

# 2.5. Code Sign (Developer ID + Hardened Runtime + Timestamp for notarization)
ENTITLEMENTS="macos/Runner/Release.entitlements"

sign_binary() {
    codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime "$@"
}

if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "Signing with: $SIGN_IDENTITY"
    APP_BUNDLE="${STAGING_DIR}/${APP_NAME}.app"

    # Step 1: Sign all loose dylibs in Frameworks/ (not inside .framework bundles)
    find "$APP_BUNDLE/Contents/Frameworks" -maxdepth 1 -name "*.dylib" 2>/dev/null | while read -r lib; do
        sign_binary "$lib"
    done

    # Step 2: Sign embedded dylibs inside App.framework (flutter_assets/native_lib)
    find "$APP_BUNDLE/Contents/Frameworks/App.framework" -name "*.dylib" 2>/dev/null | while read -r lib; do
        sign_binary "$lib"
    done

    # Step 3: Sign all .framework bundles (they contain the executables already)
    find "$APP_BUNDLE/Contents/Frameworks" -maxdepth 1 -name "*.framework" -type d 2>/dev/null | while read -r fw; do
        sign_binary "$fw"
    done

    # Step 4: Sign native_input dylib in MacOS/
    sign_binary "$APP_BUNDLE/Contents/MacOS/native_lib/libnative_input.dylib"

    # Step 5: Sign the main app bundle last (with entitlements + hardened runtime)
    sign_binary --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

    echo "✅ All binaries signed with Developer ID + hardened runtime + timestamp"
else
    echo "⚠️  Signing identity not found, using ad-hoc signing"
    codesign -f -s "-" "${STAGING_DIR}/${APP_NAME}.app/Contents/MacOS/native_lib/libnative_input.dylib"
    codesign -f -s "-" --entitlements "$ENTITLEMENTS" "${STAGING_DIR}/${APP_NAME}.app"
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

# 5.5. Notarize (requires keychain profile: xcrun notarytool store-credentials "notarytool-profile")
echo "🔏 Submitting for notarization..."
NOTARIZE_OUTPUT=$(xcrun notarytool submit "${DMG_FINAL_PATH}" --keychain-profile "notarytool-profile" --wait 2>&1)
echo "$NOTARIZE_OUTPUT"

if echo "$NOTARIZE_OUTPUT" | grep -q "status: Accepted"; then
    echo "✅ Notarization accepted, stapling ticket..."
    xcrun stapler staple "${DMG_FINAL_PATH}"
else
    echo "⚠️  Notarization not accepted — check log with:"
    SUBMISSION_ID=$(echo "$NOTARIZE_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
    echo "   xcrun notarytool log $SUBMISSION_ID --keychain-profile notarytool-profile"
fi

# 6. Close old Finder windows, eject all SpeakOut volumes, then mount new DMG
echo "Ejecting old DMG..."
osascript -e 'tell application "Finder" to close (every window whose name contains "SpeakOut")' 2>/dev/null || true
for vol in /Volumes/SpeakOut*; do
  [ -d "$vol" ] && hdiutil detach "$vol" -force >/dev/null 2>&1 || true
done
echo "Mounting DMG..."
hdiutil attach "${DMG_FINAL_PATH}" -noautoopen
open "/Volumes/${VOLUME_NAME}"

echo "Done: ${DMG_FINAL_PATH}"
