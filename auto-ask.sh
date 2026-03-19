#!/usr/bin/env bash
# auto-ask.sh — 双 Agent CLI 对比评估脚本
#
# 用法：./auto-ask.sh
# workspace 注入完全由 cmd.conf 右侧是否有值决定：
#   kode -c -p | --workspace   → 自动创建临时目录并注入
#   kode -c -p |               → 不注入任何 workspace 参数

set -euo pipefail

# ─────────────────────────────────────────────
# 0. 路径定位
# ─────────────────────────────────────────────
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD_FILE="$PROJECT_ROOT/src/cmd.conf"
QUESTIONS_FILE="$PROJECT_ROOT/src/test_words.csv"
RESULTS_DIR="$PROJECT_ROOT/results"

# ─────────────────────────────────────────────
# 1. 读取 cmd.conf
# 格式：<命令及基础参数> | <workspace 参数名>
# ─────────────────────────────────────────────
if [[ ! -f "$CMD_FILE" ]]; then
  echo "❌ 找不到 cmd.conf：$CMD_FILE" >&2
  exit 1
fi

# 按行读取，过滤空行和注释行，兼容 macOS bash 3.x
CMDS=()
while IFS= read -r line; do
  CMDS+=("$line")
done < <(grep -v '^\s*#' "$CMD_FILE" | grep -v '^\s*$' | sed 's/\r//')

if [[ ${#CMDS[@]} -lt 2 ]]; then
  echo "❌ cmd.conf 至少需要两行，当前只有 ${#CMDS[@]} 行" >&2
  exit 1
fi

# 拆解管道符两侧：左侧=命令，右侧=workspace 参数名
parse_cmd()  { echo "${1%%|*}" | sed 's/[[:space:]]*$//'; }
parse_wsflag() {
  # 有管道符才取右侧，再去掉所有空白；若为空则返回空字符串
  if [[ "$1" == *"|"* ]]; then
    echo "${1#*|}" | tr -d '[:space:]'
  else
    echo ""
  fi
}

CMD_A=$(parse_cmd  "${CMDS[0]}")
CMD_B=$(parse_cmd  "${CMDS[1]}")
WSFLAG_A=$(parse_wsflag "${CMDS[0]}")
WSFLAG_B=$(parse_wsflag "${CMDS[1]}")

echo "📌 Agent A：$CMD_A  (workspace 参数：${WSFLAG_A:-无})"
echo "📌 Agent B：$CMD_B  (workspace 参数：${WSFLAG_B:-无})"

# ─────────────────────────────────────────────
# 1-post. workspace 注入——仅当 cmd.conf 右侧有值时生效
# ─────────────────────────────────────────────
EXTRA_A=""
EXTRA_B=""

if [[ -n "$WSFLAG_A" ]]; then
  WS_A=$(mktemp -d /tmp/agent-a-workspace-XXXXXX)
  EXTRA_A="$WSFLAG_A $WS_A"
  echo "🗂  Agent A workspace：$WS_A"
  trap 'rm -rf "$WS_A"' EXIT
fi
if [[ -n "$WSFLAG_B" ]]; then
  WS_B=$(mktemp -d /tmp/agent-b-workspace-XXXXXX)
  EXTRA_B="$WSFLAG_B $WS_B"
  echo "🗂  Agent B workspace：$WS_B"
  trap 'rm -rf "$WS_B"' EXIT
fi

# ─────────────────────────────────────────────
# 2. 读取 test_words.csv（格式：`N,"问题内容"`）
# ─────────────────────────────────────────────
if [[ ! -f "$QUESTIONS_FILE" ]]; then
  echo "❌ 找不到 test_words.csv：$QUESTIONS_FILE" >&2
  exit 1
fi

questions=()
while IFS=',' read -r _num question; do
  question="${question#\"}"
  question="${question%\"}"
  question="${question//[$'\r']/}"
  [[ -n "$question" ]] && questions+=("$question")
done < "$QUESTIONS_FILE"

TOTAL=${#questions[@]}
if [[ $TOTAL -eq 0 ]]; then
  echo "❌ test_words.csv 中未解析到任何问题" >&2
  exit 1
fi
echo "📋 共读取到 $TOTAL 道题"

# ─────────────────────────────────────────────
# 3. 创建 results 目录，生成报告文件路径
# ─────────────────────────────────────────────
mkdir -p "$RESULTS_DIR"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
REPORT="$RESULTS_DIR/comparison_${TIMESTAMP}.md"

TMP_A=$(mktemp /tmp/agent_a_XXXXXX.txt)
TMP_B=$(mktemp /tmp/agent_b_XXXXXX.txt)
trap 'rm -f "$TMP_A" "$TMP_B"' EXIT

# ─────────────────────────────────────────────
# 4. 写入报告头部
# ─────────────────────────────────────────────
DATETIME=$(date '+%Y-%m-%d %H:%M:%S')
cat > "$REPORT" <<EOF
# Agent 对比评估报告

- **生成时间**：$DATETIME
- **Agent A 命令**：\`$CMD_A${EXTRA_A:+ $EXTRA_A}\`
- **Agent B 命令**：\`$CMD_B${EXTRA_B:+ $EXTRA_B}\`
- **测试题数**：$TOTAL
- **会话模式**：累积上下文连续执行

---
EOF

echo ""
echo "═══════════════════════════════════════════════════"
echo "  开始评估，报告将保存至："
echo "  $REPORT"
echo "═══════════════════════════════════════════════════"
echo ""

# ─────────────────────────────────────────────
# 5. 逐题执行两个 Agent，实时输出 + 捕获结果
# ─────────────────────────────────────────────
for i in "${!questions[@]}"; do
  QNUM=$((i + 1))
  QUESTION="${questions[$i]}"

  # 第一题不带 -c（新建会话），后续题目追加 -c（续接上下文）
  CONTINUE_FLAG=""
  [[ $i -gt 0 ]] && CONTINUE_FLAG="-c"

  echo "───────────────────────────────────────────────────"
  echo "🔢 问题 $QNUM / ${TOTAL}：$QUESTION"
  echo "───────────────────────────────────────────────────"

  # ── Agent A ──
  echo ""
  echo "▶ 正在执行 Agent A（${CMD_A}）..."
  echo "  $ $CMD_A${CONTINUE_FLAG:+ $CONTINUE_FLAG}${EXTRA_A:+ $EXTRA_A} \"$QUESTION\""
  echo ""
  read -ra CMD_A_ARGS <<< "$CMD_A"
  read -ra EXTRA_A_ARGS <<< "${EXTRA_A:-}"
  env -u CLAUDECODE "${CMD_A_ARGS[@]}" ${CONTINUE_FLAG:+"$CONTINUE_FLAG"} "${EXTRA_A_ARGS[@]:+${EXTRA_A_ARGS[@]}}" "$QUESTION" 2>&1 | tee "$TMP_A" || true
  RESPONSE_A=$(cat "$TMP_A")

  echo ""
  echo "▶ 正在执行 Agent B（${CMD_B}）..."
  echo "  $ $CMD_B${CONTINUE_FLAG:+ $CONTINUE_FLAG}${EXTRA_B:+ $EXTRA_B} \"$QUESTION\""
  echo ""

  # ── Agent B ──
  read -ra CMD_B_ARGS <<< "$CMD_B"
  read -ra EXTRA_B_ARGS <<< "${EXTRA_B:-}"
  env -u CLAUDECODE "${CMD_B_ARGS[@]}" ${CONTINUE_FLAG:+"$CONTINUE_FLAG"} "${EXTRA_B_ARGS[@]:+${EXTRA_B_ARGS[@]}}" "$QUESTION" 2>&1 | tee "$TMP_B" || true
  RESPONSE_B=$(cat "$TMP_B")

  # ── 追加写入 Markdown ──
  {
    echo ""
    echo "## 问题 ${QNUM}：${QUESTION}"
    echo ""
    echo "### 🅰 Agent A (\`$CMD_A${EXTRA_A:+ $EXTRA_A}\`)"
    echo ""
    echo '```'
    echo "$RESPONSE_A"
    echo '```'
    echo ""
    echo "### 🅱 Agent B (\`$CMD_B${EXTRA_B:+ $EXTRA_B}\`)"
    echo ""
    echo '```'
    echo "$RESPONSE_B"
    echo '```'
  } >> "$REPORT"

  echo ""
  echo "✅ 问题 $QNUM 已记录到报告"
  echo ""
done

# ─────────────────────────────────────────────
# 6. 收尾
# ─────────────────────────────────────────────
echo "═══════════════════════════════════════════════════"
echo "  🎉 评估完成！共 $TOTAL 道题"
echo "  📄 报告文件：$REPORT"
echo "═══════════════════════════════════════════════════"
