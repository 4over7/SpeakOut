#!/bin/bash
# SpeakOut 完整数据清理脚本
# 用于测试 FTUE (First Time User Experience)

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
    echo "   • 全部用户配置（快捷键 / 云账户凭证 / 词典）"
    echo "   • Application Support 下已下载的模型"
    echo "   注：随包内置的默认模型在 app bundle 内，不受影响，清理后仍可直接使用"
    echo ""
    printf "确认请输入 yes: "
    read -r _ans
    if [ "$_ans" != "yes" ]; then
        echo "已取消。"
        exit 0
    fi
fi

echo "🧹 正在清理 SpeakOut 数据..."

# 1. 旧版模型位置（当前版本的模型在 Application Support 下，由第 2 步一并清理）
echo "  [1/5] 清理旧版模型目录..."
rm -rf ~/Documents/speakout_models

# 2. SharedPreferences (plist)
echo "  [3/5] 清理用户偏好设置..."
rm -f ~/Library/Preferences/com.speakout.speakout.plist

# 3. Application Support 目录 (可能有缓存)
echo "  [2/5] 清理 Application Support（含模型）..."
rm -rf ~/Library/Application\ Support/com.speakout.speakout

# 4. Caches 目录
echo "  [4/5] 清理缓存..."
rm -rf ~/Library/Caches/com.speakout.speakout

# 5. Keychain 条目
# 注：当前版本凭证实际存于 SharedPreferences，未迁 Keychain。
# 以下命令对历史版本残留仍有意义，失败即忽略。
echo "  [5/5] 清理 Keychain 残留（如有）..."
security delete-generic-password -s "com.speakout.speakout" -a "aliyun_ak_id" 2>/dev/null || true
security delete-generic-password -s "com.speakout.speakout" -a "aliyun_ak_secret" 2>/dev/null || true
security delete-generic-password -s "com.speakout.speakout" -a "aliyun_app_key" 2>/dev/null || true
security delete-generic-password -s "com.speakout.speakout" -a "llm_api_key" 2>/dev/null || true

# 6. 强制刷新 defaults (macOS 会缓存 plist)
echo "  [4/5] 刷新系统缓存..."
defaults delete com.speakout.speakout 2>/dev/null || true
killall cfprefsd 2>/dev/null || true

echo "✅ 清理完成！请重新打开 SpeakOut 测试 FTUE。"
