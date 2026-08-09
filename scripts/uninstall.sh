#!/bin/bash
# SpeakOut 完全卸载脚本
# 删除 .app + 所有用户数据，用于彻底重装

APP_NAME="SpeakOut"
APP_PATH="/Applications/${APP_NAME}.app"

# --- 安全确认 ---
# install.sh 与 uninstall.sh 只差两个字母，Tab 补全打错的代价是不可恢复的数据丢失。
# 自动化场景用 -y / --yes 跳过。
case "${1:-}" in
  -y|--yes) FORCE=1 ;;
  *)        FORCE=0 ;;
esac

if [ "$FORCE" -ne 1 ]; then
    echo ""
    echo "⚠️  即将删除（不可恢复）："
    echo "   • /Applications/SpeakOut.app"
    echo "   • 全部用户配置（快捷键 / 云账户凭证 / 词典）"
    echo "   • Application Support 下已下载的模型"
    echo ""
    printf "确认请输入 yes: "
    read -r _ans
    if [ "$_ans" != "yes" ]; then
        echo "已取消。"
        exit 0
    fi
fi

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
