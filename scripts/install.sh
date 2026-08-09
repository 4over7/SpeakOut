#!/bin/bash
set -e

APP_NAME="SpeakOut"
SOURCE_APP="build/macos/Build/Products/Release/${APP_NAME}.app"
DEST_DIR="/Applications"
DEST_APP="${DEST_DIR}/${APP_NAME}.app"
SIGN_IDENTITY="Developer ID Application: Lindan Wang (UB9D55S724)"

# 注意：此脚本仅用于日常开发实测，不升 build 号、不同步 gateway。
# 发版打包走 ./scripts/create_styled_dmg.sh，那里才做版本号自增 + gateway sync。
# 原因：install.sh 每次 +1 会让本地 build 超过线上 release，无法复现自动更新流程，
#      还会污染 git 工作区（每次 install 都留下 pubspec/gateway 修改）。
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')
echo "📦 Building current version: ${VERSION} (build number NOT auto-incremented)"

# Build
echo "🔨 Building ${APP_NAME} (Release)..."
# set -e 已保证构建失败即退出，无需再判 $?
flutter build macos --release

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

# 热替换：不杀进程，直接替换文件
# Unix 特性：运行中的进程持有 vnode 引用，rm 只删除目录项，旧进程不受影响
# 用户关闭后下次打开就是新版本
if pgrep -x "$APP_NAME" > /dev/null; then
    echo "ℹ️  $APP_NAME 正在运行，热替换中（不中断当前使用）..."
fi

# Fix App Icon: Flutter actool only generates 4 sizes, override with full icns
FULL_ICNS="macos/Runner/Resources/AppIcon.icns"
if [ -f "$FULL_ICNS" ]; then
    cp "$FULL_ICNS" "$SOURCE_APP/Contents/Resources/AppIcon.icns"
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

# Inject bundled ASR model（与 DMG/App Store 渠道保持一致）
# 开发脚本不强制下载：缓存不存在就跳过，装出来的包走原下载流程。
# 想在本机验证「内置模型」路径，先跑一次 ./scripts/create_styled_dmg.sh 生成缓存即可。
BUNDLED_MODEL_DIR="sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17"
BUNDLED_MODEL_CACHE="build/bundled-models/${BUNDLED_MODEL_DIR}"
if [ -f "${BUNDLED_MODEL_CACHE}/model.int8.onnx" ] && [ -f "${BUNDLED_MODEL_CACHE}/tokens.txt" ]; then
    MODEL_DEST="${SOURCE_APP:?}/Contents/Resources/models/${BUNDLED_MODEL_DIR}"
    rm -rf "${SOURCE_APP:?}/Contents/Resources/models"
    mkdir -p "$MODEL_DEST"
    cp "${BUNDLED_MODEL_CACHE}/model.int8.onnx" "${BUNDLED_MODEL_CACHE}/tokens.txt" "$MODEL_DEST/"
    echo "📦 已内置模型: $(du -sh "$MODEL_DEST" | cut -f1)"
else
    echo "ℹ️  未找到内置模型缓存，本次安装不含内置模型（首启将走下载流程）"
fi

# Code sign: inner components first, then the app bundle
# This ensures TCC (permission database) recognizes the same identity across reinstalls
ENTITLEMENTS="macos/Runner/Release.entitlements"
echo "Signing with: $SIGN_IDENTITY"
codesign -f -s "$SIGN_IDENTITY" "$NATIVE_LIB_DEST/libnative_input.dylib"
codesign -f -s "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$SOURCE_APP"

echo "Installing ${APP_NAME} to ${DEST_DIR}..."

# Remove existing app
if [ -d "$DEST_APP" ]; then
    echo "Removing existing version..."
    rm -rf "${DEST_APP:?}"
fi

# Copy new app
echo "Copying to Applications..."
cp -R "$SOURCE_APP" "$DEST_DIR/"

echo "✅ Success! ${APP_NAME} has been installed to /Applications."
echo "You can launch it via Spotlight or Launchpad."
