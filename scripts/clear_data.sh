#!/bin/bash
# SpeakOut 完整数据清理脚本
# 用于测试 FTUE (First Time User Experience)

echo "🧹 正在清理 SpeakOut 数据..."

# 1. 模型下载目录 (Application Support/Models)
echo "  [1/6] 清理模型目录..."
rm -rf ~/Library/Application\ Support/com.speakout.speakout/Models
# 旧位置也清理
rm -rf ~/Documents/speakout_models

# 2. SharedPreferences (plist)
echo "  [2/5] 清理用户偏好设置..."
rm -f ~/Library/Preferences/com.speakout.speakout.plist

# 3. Application Support 目录 (可能有缓存)
echo "  [3/5] 清理 Application Support..."
rm -rf ~/Library/Application\ Support/com.speakout.speakout

# 4. Caches 目录
echo "  [4/5] 清理缓存..."
rm -rf ~/Library/Caches/com.speakout.speakout

# 5. Keychain 条目
echo "  [5/6] 清理 Keychain 条目..."
security delete-generic-password -s "com.speakout.speakout" -a "aliyun_ak_id" 2>/dev/null || true
security delete-generic-password -s "com.speakout.speakout" -a "aliyun_ak_secret" 2>/dev/null || true
security delete-generic-password -s "com.speakout.speakout" -a "aliyun_app_key" 2>/dev/null || true
security delete-generic-password -s "com.speakout.speakout" -a "llm_api_key" 2>/dev/null || true

# 6. 强制刷新 defaults (macOS 会缓存 plist)
echo "  [6/6] 刷新系统缓存..."
defaults delete com.speakout.speakout 2>/dev/null || true
killall cfprefsd 2>/dev/null || true

echo "✅ 清理完成！请重新打开 SpeakOut 测试 FTUE。"
