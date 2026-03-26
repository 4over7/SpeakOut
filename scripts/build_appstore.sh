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
