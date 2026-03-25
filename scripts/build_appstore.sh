#!/bin/bash
set -e

APP_NAME="SpeakOut"
SOURCE_APP="build/macos/Build/Products/Release/${APP_NAME}.app"
ENTITLEMENTS="macos/Runner/AppStore.entitlements"
NATIVE_LIB="native_lib/libnative_input.dylib"

echo "=== Building ${APP_NAME} for App Store ==="

# 1. Build with App Store flag
echo "Building Flutter macOS (App Store)..."
flutter build macos --release --dart-define=DISTRIBUTION=appstore

# 2. Inject native library
echo "Injecting native library..."
NATIVE_LIB_DEST="$SOURCE_APP/Contents/MacOS/native_lib"
mkdir -p "$NATIVE_LIB_DEST"
cp "$NATIVE_LIB" "$NATIVE_LIB_DEST/"

# 3. Sign with App Store certificate
# 查找 "3rd Party Mac Developer Application" 证书（App Store 分发用）
SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "3rd Party Mac Developer Application" | head -1 | sed 's/.*"\(.*\)"/\1/')

if [ -z "$SIGN_IDENTITY" ]; then
    # 回退到 Apple Development 证书
    SIGN_IDENTITY="Apple Development: Lindan Wang (GQ2A45YPF3)"
    echo "⚠️  未找到 App Store 分发证书，使用开发证书: $SIGN_IDENTITY"
    echo "   提交 App Store 需要 '3rd Party Mac Developer Application' 证书"
else
    echo "Signing with: $SIGN_IDENTITY"
fi

codesign -f -s "$SIGN_IDENTITY" "$NATIVE_LIB_DEST/libnative_input.dylib"
codesign -f -s "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$SOURCE_APP"

# 4. Create .pkg for App Store upload
echo "Creating .pkg..."
INSTALLER_IDENTITY=$(security find-identity -v | grep "3rd Party Mac Developer Installer" | head -1 | sed 's/.*"\(.*\)"/\1/')

if [ -n "$INSTALLER_IDENTITY" ]; then
    productbuild --component "$SOURCE_APP" /Applications --sign "$INSTALLER_IDENTITY" "SpeakOut-AppStore.pkg"
    echo ""
    echo "✅ Done: SpeakOut-AppStore.pkg"
    echo "   上传方式: 打开 Transporter.app → 拖入 .pkg → 点击交付"
else
    productbuild --component "$SOURCE_APP" /Applications "SpeakOut-AppStore.pkg"
    echo ""
    echo "⚠️  .pkg 未签名（未找到 Installer 证书）"
    echo "   可通过 Xcode 的 Archive → Distribute App 上传"
    echo "   或安装 '3rd Party Mac Developer Installer' 证书后重新打包"
fi
