#!/bin/bash
# 一键运行全部测试: 静态分析 + 单元测试 + 覆盖率摘要
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "════════════════════════════════════════"
echo "  SpeakOut 测试套件"
echo "════════════════════════════════════════"
echo ""

# 1. 静态分析
echo "▶ Step 1/3: flutter analyze"
flutter analyze
echo "✅ 静态分析通过"
echo ""

# 2. 运行测试 + 覆盖率
echo "▶ Step 2/3: flutter test --coverage"
flutter test --coverage
echo "✅ 全部测试通过"
echo ""

# 3. 覆盖率摘要
echo "▶ Step 3/3: 覆盖率摘要"
if [ -f coverage/lcov.info ]; then
  # 统计总行数和命中行数
  TOTAL_LINES=$(grep -c "^DA:" coverage/lcov.info 2>/dev/null || echo "0")
  HIT_LINES=$(grep "^DA:" coverage/lcov.info | grep -v ",0$" | wc -l | tr -d ' ')
  if [ "$TOTAL_LINES" -gt 0 ]; then
    PERCENT=$((HIT_LINES * 100 / TOTAL_LINES))
    echo "  总行数: $TOTAL_LINES"
    echo "  命中行: $HIT_LINES"
    echo "  覆盖率: ${PERCENT}%"
  else
    echo "  覆盖率文件为空"
  fi

  # 按文件列出覆盖率 (前 20 个最低覆盖率文件)
  echo ""
  echo "  各文件覆盖率 (最低 20):"
  awk '
    /^SF:/ { file=$0; sub(/^SF:/, "", file); total=0; hit=0; }
    /^DA:/ { total++; split($0, a, ","); if (a[2]+0 > 0) hit++; }
    /^end_of_record/ {
      if (total > 0) {
        pct = int(hit * 100 / total);
        printf "    %3d%% %s\n", pct, file;
      }
    }
  ' coverage/lcov.info | sort -n | head -20
else
  echo "  ⚠️  coverage/lcov.info 未生成"
fi

echo ""
echo "════════════════════════════════════════"
echo "  完成"
echo "════════════════════════════════════════"
