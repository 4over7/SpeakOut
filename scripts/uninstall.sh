#!/bin/bash
# SpeakOut 完全卸载脚本
# 删除 .app + 所有用户数据，用于彻底重装

APP_NAME="SpeakOut"
APP_PATH="/Applications/${APP_NAME}.app"

echo "🗑️  开始卸载 ${APP_NAME}..."

# 1. 如果正在运行，先退出
if pgrep -x "$APP_NAME" > /dev/null; then
    echo "  [1] 正在关闭 ${APP_NAME}..."
    killall "$APP_NAME" 2>/dev/null || true
    sleep 2
else
    echo "  [1] ${APP_NAME} 未运行，跳过"
fi

# 2. 删除 .app
if [ -d "$APP_PATH" ]; then
    echo "  [2] 删除 ${APP_PATH}..."
    rm -rf "$APP_PATH"
else
    echo "  [2] 未找到 ${APP_PATH}，跳过"
fi

# 3. 清理 SharedPreferences (plist)
echo "  [3] 清理用户偏好设置..."
rm -f ~/Library/Preferences/com.speakout.speakout.plist

# 4. 清理 Application Support（含模型）
echo "  [4] 清理 Application Support（含模型）..."
rm -rf ~/Library/Application\ Support/com.speakout.speakout
# 旧版模型位置
rm -rf ~/Documents/speakout_models

# 5. 清理 Caches
echo "  [5] 清理缓存..."
rm -rf ~/Library/Caches/com.speakout.speakout

# 6. 清理 Keychain
echo "  [6] 清理 Keychain 条目..."
security delete-generic-password -s "com.speakout.speakout" -a "aliyun_ak_id"     2>/dev/null || true
security delete-generic-password -s "com.speakout.speakout" -a "aliyun_ak_secret" 2>/dev/null || true
security delete-generic-password -s "com.speakout.speakout" -a "aliyun_app_key"   2>/dev/null || true
security delete-generic-password -s "com.speakout.speakout" -a "llm_api_key"      2>/dev/null || true

# 7. 刷新系统 defaults 缓存
echo "  [7] 刷新系统缓存..."
defaults delete com.speakout.speakout 2>/dev/null || true
killall cfprefsd 2>/dev/null || true

echo ""
echo "✅ 卸载完成！重新安装请双击 DMG 文件。"
