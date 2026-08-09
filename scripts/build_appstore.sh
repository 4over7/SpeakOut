#!/bin/bash
set -e

APP_NAME="SpeakOut"
SOURCE_APP="build/macos/Build/Products/Release/${APP_NAME}.app"
ENTITLEMENTS="macos/Runner/AppStore.entitlements"
NATIVE_LIB="native_lib/libnative_input.dylib"
SIGN_IDENTITY="Apple Distribution: Lindan Wang (UB9D55S724)"
INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Lindan Wang (UB9D55S724)"

echo "=== Building ${APP_NAME} for App Store ==="

# 1. Build with App Store flag
echo "Building Flutter macOS (App Store)..."
flutter build macos --release --dart-define=DISTRIBUTION=appstore

# 2. Inject native library
echo "Injecting native library..."
NATIVE_LIB_DEST="$SOURCE_APP/Contents/MacOS/native_lib"
mkdir -p "$NATIVE_LIB_DEST"
cp "$NATIVE_LIB" "$NATIVE_LIB_DEST/"

# 2.5 Inject bundled ASR model（与 DMG 渠道保持一致：装完即用，无需首启下载）
# 必须在 codesign 之前，否则签名不覆盖新文件。
BUNDLED_MODEL_DIR="sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17"
BUNDLED_MODEL_CACHE="build/bundled-models/${BUNDLED_MODEL_DIR}"
MODEL_MIN_BYTES=200000000
if [ ! -f "${BUNDLED_MODEL_CACHE}/model.int8.onnx" ] || \
   [ "$(stat -f%z "${BUNDLED_MODEL_CACHE}/model.int8.onnx" 2>/dev/null || echo 0)" -lt "$MODEL_MIN_BYTES" ]; then
    echo "❌ 内置模型缓存缺失或不完整：先跑一次 ./scripts/create_styled_dmg.sh 生成 build/bundled-models 缓存"
    exit 1
fi
# 先清空 models 目录：flutter build 是增量的，不会清掉上一次注入的残留
# （换模型版本时会留下两份，包体积翻倍）
rm -rf "${SOURCE_APP:?}/Contents/Resources/models"
MODEL_DEST="$SOURCE_APP/Contents/Resources/models/${BUNDLED_MODEL_DIR}"
mkdir -p "$MODEL_DEST"
cp "${BUNDLED_MODEL_CACHE}/model.int8.onnx" "${BUNDLED_MODEL_CACHE}/tokens.txt" "$MODEL_DEST/"
echo "📦 已内置模型: $(du -sh "$MODEL_DEST" | cut -f1)"

# 3. Sign
echo "Signing with: $SIGN_IDENTITY"
codesign -f -s "$SIGN_IDENTITY" "$NATIVE_LIB_DEST/libnative_input.dylib"
codesign -f -s "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$SOURCE_APP"

# 4. Create .pkg for App Store upload
echo "Creating .pkg with: $INSTALLER_IDENTITY"
productbuild --component "$SOURCE_APP" /Applications --sign "$INSTALLER_IDENTITY" "SpeakOut-AppStore.pkg"

echo ""
echo "✅ Done: SpeakOut-AppStore.pkg"
echo "   上传方式: 打开 Transporter.app → 拖入 .pkg → 点击交付"
