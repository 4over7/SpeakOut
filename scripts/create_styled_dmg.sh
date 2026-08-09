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
sed -i '' "s|version: '[^']*', // @speakout-version|version: '${VERSION}', // @speakout-version|" gateway/src/index.js
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

# Injection: 内置默认 ASR 模型（装完即用，省掉首启 229MB 下载）
# 模型不入 git（228MB 会让仓库永久膨胀），首次打包时下载到 build/ 缓存，后续复用。
# 必须在 codesign 之前注入，否则签名不覆盖新文件 → 公证失败。
BUNDLED_MODEL_DIR="sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17"
BUNDLED_MODEL_CACHE="build/bundled-models/${BUNDLED_MODEL_DIR}"
BUNDLED_MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${BUNDLED_MODEL_DIR}.tar.bz2"

# 校验缓存完整性：只判存在会让「半截下载」被打进包，用户拿到坏包。
# 判据是「两个必需文件都在且 onnx 非空」，不用绝对大小阈值 ——
# 否则将来换成小模型（如 77MB 的 Dolphin）会永远判定不完整、每次重下。
MODEL_MIN_BYTES=10000000   # 仅用于排除 0 字节/截断文件，不是模型实际大小
CACHE_OK=0
if [ -f "${BUNDLED_MODEL_CACHE}/model.int8.onnx" ] && [ -f "${BUNDLED_MODEL_CACHE}/tokens.txt" ]; then
    CACHE_SIZE=$(stat -f%z "${BUNDLED_MODEL_CACHE}/model.int8.onnx")
    [ "$CACHE_SIZE" -ge "$MODEL_MIN_BYTES" ] && CACHE_OK=1 || echo "⚠️  缓存模型疑似截断（${CACHE_SIZE} bytes），重新下载"
fi

if [ "$CACHE_OK" -eq 0 ]; then
    echo "📥 首次打包：下载内置模型 ${BUNDLED_MODEL_DIR}..."
    mkdir -p build/bundled-models
    curl -L --fail -o "build/bundled-models/model.tar.bz2" "${BUNDLED_MODEL_URL}" || {
        echo "❌ 内置模型下载失败，中止打包（避免产出无模型的包）"; exit 1; }
    tar xjf "build/bundled-models/model.tar.bz2" -C build/bundled-models
    rm -f "build/bundled-models/model.tar.bz2"
    DL_SIZE=$(stat -f%z "${BUNDLED_MODEL_CACHE}/model.int8.onnx" 2>/dev/null || echo 0)
    if [ "$DL_SIZE" -lt "$MODEL_MIN_BYTES" ]; then
        echo "❌ 下载后模型仍不完整（${DL_SIZE} bytes），中止打包"; exit 1
    fi
fi

# 只装 sherpa 真正需要的两个文件，省掉 README / test_wavs（约 1MB 冗余）
# 先清空 models 目录：flutter build 是增量的，不会清掉上一次注入的残留
# （换模型版本时会留下两份，包体积翻倍）
rm -rf "${STAGING_DIR:?}/${APP_NAME:?}.app/Contents/Resources/models"
MODEL_DEST="${STAGING_DIR}/${APP_NAME}.app/Contents/Resources/models/${BUNDLED_MODEL_DIR}"
mkdir -p "${MODEL_DEST}"
cp "${BUNDLED_MODEL_CACHE}/model.int8.onnx" "${MODEL_DEST}/"
cp "${BUNDLED_MODEL_CACHE}/tokens.txt" "${MODEL_DEST}/"
echo "📦 已内置模型: $(du -sh "${MODEL_DEST}" | cut -f1)"

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
