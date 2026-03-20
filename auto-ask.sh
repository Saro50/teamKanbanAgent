#!/usr/bin/env bash
# auto-ask.sh — 双 Agent CLI 对比评估脚本
#
# 用法：
#   ./auto-ask.sh -t src/tests/batch_01_basic.csv   # 运行指定批次
#   ./auto-ask.sh --all                              # 顺序运行 src/tests/ 下所有批次

set -euo pipefail

# ─────────────────────────────────────────────
# 0. 路径定位
# ─────────────────────────────────────────────
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD_FILE="$PROJECT_ROOT/src/cmd.conf"
TESTS_DIR="$PROJECT_ROOT/src/tests"
RESULTS_DIR="$PROJECT_ROOT/results"

# ─────────────────────────────────────────────
# 1-pre. 解析命令行参数
# ─────────────────────────────────────────────
QUESTIONS_FILES=()
RUN_ALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--test)
      QUESTIONS_FILES+=("$2"); shift 2 ;;
    --all)
      RUN_ALL=true; shift ;;
    *)
      echo "❌ 未知参数：$1" >&2
      echo "用法：$0 [-t <测试文件>] [--all]" >&2
      exit 1 ;;
  esac
done

# --all：按文件名排序加载 src/tests/*.csv
if $RUN_ALL; then
  while IFS= read -r f; do
    QUESTIONS_FILES+=("$f")
  done < <(find "$TESTS_DIR" -maxdepth 1 -name "*.csv" | sort)
fi

# 默认：无参数时提示
if [[ ${#QUESTIONS_FILES[@]} -eq 0 ]]; then
  echo "用法：$0 -t <测试文件>  或  $0 --all" >&2
  echo "可用批次：" >&2
  find "$TESTS_DIR" -maxdepth 1 -name "*.csv" | sort | sed "s|$PROJECT_ROOT/||" | while read -r f; do
    echo "  $f" >&2
  done
  exit 1
fi

# ─────────────────────────────────────────────
# 1. 读取 cmd.conf
# 格式：<基础命令> | <workspace 参数> | <继续对话参数> | <提示词参数>
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
  # 取第一个管道符后、第二个管道符前的内容作为 workspace 参数
  # 只去掉首尾空白，保留内部空格（如 -w /path/to/dir）
  if [[ "$1" == *"|"* ]]; then
    local rest="${1#*|}"
    local val="${rest%%|*}"
    # trim leading/trailing whitespace
    val="$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    echo "$val"
  else
    echo ""
  fi
}
parse_contflag() {
  # 取第二个管道符之后的内容作为继续对话参数；默认 -c
  local count
  count=$(echo "$1" | tr -cd '|' | wc -c | tr -d '[:space:]')
  if [[ "$count" -ge 2 ]]; then
    local val
    val=$(echo "$1" | awk -F'|' '{print $3}' | tr -d '[:space:]')
    if [[ -n "$val" ]]; then
      echo "$val"
    else
      echo "-c"
    fi
  else
    echo "-c"
  fi
}
parse_promptflag() {
  # 取第三个管道符之后的内容作为提示词参数；默认 -p
  local count
  count=$(echo "$1" | tr -cd '|' | wc -c | tr -d '[:space:]')
  if [[ "$count" -ge 3 ]]; then
    local val
    val=$(echo "$1" | awk -F'|' '{print $4}' | tr -d '[:space:]')
    if [[ -n "$val" ]]; then
      echo "$val"
    else
      echo "-p"
    fi
  else
    echo "-p"
  fi
}

CMD_A=$(parse_cmd  "${CMDS[0]}")
CMD_B=$(parse_cmd  "${CMDS[1]}")
WSFLAG_A=$(parse_wsflag "${CMDS[0]}")
WSFLAG_B=$(parse_wsflag "${CMDS[1]}")
CONTFLAG_A=$(parse_contflag "${CMDS[0]}")
CONTFLAG_B=$(parse_contflag "${CMDS[1]}")
PROMPTFLAG_A=$(parse_promptflag "${CMDS[0]}")
PROMPTFLAG_B=$(parse_promptflag "${CMDS[1]}")

echo "📌 Agent A：$CMD_A  (workspace：${WSFLAG_A:-无}, 继续对话：${CONTFLAG_A}, 提示词：${PROMPTFLAG_A})"
echo "📌 Agent B：$CMD_B  (workspace：${WSFLAG_B:-无}, 继续对话：${CONTFLAG_B}, 提示词：${PROMPTFLAG_B})"

# ─────────────────────────────────────────────
# 1-post. workspace 注入——仅当 cmd.conf 第2列有值时生效
# 若值只有参数名（如 -w），则 mktemp 创建临时目录
# 若值含路径（如 -w /path/dir），则直接使用
# ─────────────────────────────────────────────
EXTRA_A=""
EXTRA_B=""
WS_A=""
WS_B=""
TMP_A=""
TMP_B=""

# 统一清理函数，脚本退出时一次性清理所有临时资源
cleanup() {
  [[ -n "$TMP_A" && -f "$TMP_A" ]] && rm -f "$TMP_A"
  [[ -n "$TMP_B" && -f "$TMP_B" ]] && rm -f "$TMP_B"
  [[ -n "$WS_A"  && -d "$WS_A"  ]] && rm -rf "$WS_A"
  [[ -n "$WS_B"  && -d "$WS_B"  ]] && rm -rf "$WS_B"
}
trap cleanup EXIT

if [[ -n "$WSFLAG_A" ]]; then
  # 检查是否只有参数名（单词）还是包含路径
  local_words=($WSFLAG_A)
  if [[ ${#local_words[@]} -eq 1 ]]; then
    # 只有 flag 如 -w，需要创建临时目录
    WS_A=$(mktemp -d /tmp/agent-a-workspace-XXXXXX)
    EXTRA_A="$WSFLAG_A $WS_A"
    echo "🗂  Agent A workspace（临时）：$WS_A"
  else
    # 已包含路径如 "-w /path/dir"，直接使用，不需清理
    EXTRA_A="$WSFLAG_A"
    echo "🗂  Agent A workspace：${WSFLAG_A#* }"
  fi
fi
if [[ -n "$WSFLAG_B" ]]; then
  local_words=($WSFLAG_B)
  if [[ ${#local_words[@]} -eq 1 ]]; then
    WS_B=$(mktemp -d /tmp/agent-b-workspace-XXXXXX)
    EXTRA_B="$WSFLAG_B $WS_B"
    echo "🗂  Agent B workspace（临时）：$WS_B"
  else
    EXTRA_B="$WSFLAG_B"
    echo "🗂  Agent B workspace：${WSFLAG_B#* }"
  fi
fi

# ─────────────────────────────────────────────
# 主函数：对单个测试文件执行完整评估流程
# ─────────────────────────────────────────────
run_batch() {
  local QUESTIONS_FILE="$1"
  local BATCH_NAME
  BATCH_NAME=$(basename "$QUESTIONS_FILE" .csv)

  # ── 2. 读取问题文件（格式：`N,"问题内容"`，# 开头为描述注释）──
  if [[ ! -f "$QUESTIONS_FILE" ]]; then
    echo "❌ 找不到测试文件：$QUESTIONS_FILE" >&2
    return 1
  fi

  # 提取注释行作为批次描述（去掉 "# " 前缀，多行合并为 " | " 分隔）
  local BATCH_DESC
  BATCH_DESC=$(grep '^\s*#' "$QUESTIONS_FILE" | sed 's/^\s*#\s*//' | sed 's/\r//' | tr '\n' '|' | sed 's/|$//' | sed 's/|/ | /g')

  local questions=()
  while IFS=',' read -r _num question; do
    question="${question#\"}"
    question="${question%\"}"
    question="${question//[$'\r']/}"
    [[ -n "$question" ]] && questions+=("$question")
  done < "$QUESTIONS_FILE"

  local TOTAL=${#questions[@]}
  if [[ $TOTAL -eq 0 ]]; then
    echo "❌ $QUESTIONS_FILE 中未解析到任何问题" >&2
    return 1
  fi

  # ── 3. 创建报告文件（按批次分目录） ──
  local BATCH_RECORDS_DIR="$RESULTS_DIR/$BATCH_NAME/records"
  mkdir -p "$BATCH_RECORDS_DIR"
  local TIMESTAMP
  TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
  local REPORT="$BATCH_RECORDS_DIR/${TIMESTAMP}.md"

  TMP_A=$(mktemp -t agent_a.XXXXXX)
  TMP_B=$(mktemp -t agent_b.XXXXXX)

  # ── 4. 写入报告头部 ──
  local DATETIME
  DATETIME=$(date '+%Y-%m-%d %H:%M:%S')
  cat > "$REPORT" <<EOF
# Agent 对比评估报告

- **生成时间**：$DATETIME
- **批次文件**：$QUESTIONS_FILE
- **批次描述**：${BATCH_DESC:-无}
- **Agent A 命令**：\`$CMD_A${EXTRA_A:+ $EXTRA_A}\`
- **Agent B 命令**：\`$CMD_B${EXTRA_B:+ $EXTRA_B}\`
- **测试题数**：$TOTAL
- **会话模式**：累积上下文连续执行

---
EOF

  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  批次：${BATCH_NAME}（${TOTAL} 道题）"
  [[ -n "$BATCH_DESC" ]] && echo "  描述：$BATCH_DESC"
  echo "  报告：$REPORT"
  echo "═══════════════════════════════════════════════════"
  echo ""

  # ── 5. 逐题执行 ──
  for i in "${!questions[@]}"; do
    local QNUM=$((i + 1))
    local QUESTION="${questions[$i]}"

    # 第一题不带继续参数（新建会话），后续题目追加继续参数（续接上下文）
    local CONTINUE_FLAG_A=""
    local CONTINUE_FLAG_B=""
    if [[ $i -gt 0 ]]; then
      CONTINUE_FLAG_A="$CONTFLAG_A"
      CONTINUE_FLAG_B="$CONTFLAG_B"
    fi

    echo "───────────────────────────────────────────────────"
    echo "🔢 问题 $QNUM / ${TOTAL}：$QUESTION"
    echo "───────────────────────────────────────────────────"

    # ── Agent A ──
    echo ""
    echo "▶ 正在执行 Agent A（${CMD_A}）..."
    echo "  $ $CMD_A${CONTINUE_FLAG_A:+ $CONTINUE_FLAG_A}${EXTRA_A:+ $EXTRA_A} $PROMPTFLAG_A \"$QUESTION\""
    echo ""
    local -a ARGS_A=()
    read -ra ARGS_A <<< "$CMD_A"
    [[ -n "$CONTINUE_FLAG_A" ]] && ARGS_A+=("$CONTINUE_FLAG_A")
    if [[ -n "$EXTRA_A" ]]; then
      local -a EA=()
      read -ra EA <<< "$EXTRA_A"
      ARGS_A+=("${EA[@]}")
    fi
    ARGS_A+=("$PROMPTFLAG_A" "$QUESTION")
    env -u CLAUDECODE "${ARGS_A[@]}" 2>&1 | tee "$TMP_A" || true
    local RESPONSE_A
    RESPONSE_A=$(cat "$TMP_A")

    echo ""
    echo "▶ 正在执行 Agent B（${CMD_B}）..."
    echo "  $ $CMD_B${CONTINUE_FLAG_B:+ $CONTINUE_FLAG_B}${EXTRA_B:+ $EXTRA_B} $PROMPTFLAG_B \"$QUESTION\""
    echo ""

    # ── Agent B ──
    local -a ARGS_B=()
    read -ra ARGS_B <<< "$CMD_B"
    [[ -n "$CONTINUE_FLAG_B" ]] && ARGS_B+=("$CONTINUE_FLAG_B")
    if [[ -n "$EXTRA_B" ]]; then
      local -a EB=()
      read -ra EB <<< "$EXTRA_B"
      ARGS_B+=("${EB[@]}")
    fi
    ARGS_B+=("$PROMPTFLAG_B" "$QUESTION")
    env -u CLAUDECODE "${ARGS_B[@]}" 2>&1 | tee "$TMP_B" || true
    local RESPONSE_B
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

  echo "═══════════════════════════════════════════════════"
  echo "  🎉 批次完成！共 $TOTAL 道题"
  echo "  📄 报告文件：$REPORT"
  echo "═══════════════════════════════════════════════════"
  echo ""

  # ── 评估阶段：调用独立评估脚本 ──
  local EVAL_SCRIPT="$PROJECT_ROOT/evaluate.sh"
  if [[ -x "$EVAL_SCRIPT" ]]; then
    "$EVAL_SCRIPT" -r "$REPORT"
  else
    echo "  ⚠️  未找到 evaluate.sh，跳过自动评估" >&2
  fi
}

# ─────────────────────────────────────────────
# 6. 依次运行所有指定批次
# ─────────────────────────────────────────────
for qfile in "${QUESTIONS_FILES[@]}"; do
  run_batch "$qfile"
done
