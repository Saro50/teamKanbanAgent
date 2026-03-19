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
  WS_A=$(mktemp -d /tmp/agent-a-workspace-XXXXXX)
  EXTRA_A="$WSFLAG_A $WS_A"
  echo "🗂  Agent A workspace：$WS_A"
fi
if [[ -n "$WSFLAG_B" ]]; then
  WS_B=$(mktemp -d /tmp/agent-b-workspace-XXXXXX)
  EXTRA_B="$WSFLAG_B $WS_B"
  echo "🗂  Agent B workspace：$WS_B"
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

  # ── 3. 创建报告文件 ──
  mkdir -p "$RESULTS_DIR"
  local TIMESTAMP
  TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
  local REPORT="$RESULTS_DIR/${BATCH_NAME}_${TIMESTAMP}.md"

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

    # 第一题不带 -c（新建会话），后续题目追加 -c（续接上下文）
    local CONTINUE_FLAG=""
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
    local RESPONSE_A
    RESPONSE_A=$(cat "$TMP_A")

    echo ""
    echo "▶ 正在执行 Agent B（${CMD_B}）..."
    echo "  $ $CMD_B${CONTINUE_FLAG:+ $CONTINUE_FLAG}${EXTRA_B:+ $EXTRA_B} \"$QUESTION\""
    echo ""

    # ── Agent B ──
    read -ra CMD_B_ARGS <<< "$CMD_B"
    read -ra EXTRA_B_ARGS <<< "${EXTRA_B:-}"
    env -u CLAUDECODE "${CMD_B_ARGS[@]}" ${CONTINUE_FLAG:+"$CONTINUE_FLAG"} "${EXTRA_B_ARGS[@]:+${EXTRA_B_ARGS[@]}}" "$QUESTION" 2>&1 | tee "$TMP_B" || true
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

  # ── 评估阶段：检测同名模板文件并自动评估 ──
  local TEMPLATE_FILE="${QUESTIONS_FILE%.csv}.template.md"
  if [[ -f "$TEMPLATE_FILE" ]]; then
    echo "📐 发现模板文件：$TEMPLATE_FILE"

    # 从 .env 读取评估命令
    local ENV_FILE="$PROJECT_ROOT/.env"
    if [[ ! -f "$ENV_FILE" ]]; then
      echo "⚠️  未找到 .env 文件，跳过自动评估" >&2
      return 0
    fi
    local EVAL_CMD_TEMPLATE
    EVAL_CMD_TEMPLATE=$(grep '^\s*EVALUTION_CMD=' "$ENV_FILE" | head -1 | sed 's/^\s*EVALUTION_CMD=//' | sed 's/\r//')
    if [[ -z "$EVAL_CMD_TEMPLATE" ]]; then
      echo "⚠️  .env 中未找到 EVALUTION_CMD，跳过自动评估" >&2
      return 0
    fi

    echo "🔍 正在生成评估报告..."
    local EVAL_REPORT="$RESULTS_DIR/${BATCH_NAME}_eval_${TIMESTAMP}.md"

    # 构造评估 prompt（对比报告内容）
    local COMPARISON_CONTENT
    COMPARISON_CONTENT=$(cat "$REPORT")
    local EVAL_PROMPT
    EVAL_PROMPT="你是一个 AI 输出质量评估专家。请根据系统提示中提供的【评估模板】，对以下【对比报告】中两个 Agent 的输出逐题打分，最终生成结构化的 Markdown 评估报告，包含：
1. 逐题评分表（Agent A / Agent B 各维度分数 + 简评）
2. 综合评分汇总表
3. 总体评价与使用场景建议

# 对比报告

${COMPARISON_CONTENT}"

    # 替换 {SystemPrompts} 和 {Prompts}，构造最终评估命令
    local EVAL_CMD
    EVAL_CMD="${EVAL_CMD_TEMPLATE/\{SystemPrompts\}/$TEMPLATE_FILE}"
    EVAL_CMD="${EVAL_CMD/\{Prompts\}/$EVAL_PROMPT}"

    echo "  $ $EVAL_CMD"
    echo ""

    # 执行评估命令
    read -ra EVAL_CMD_ARGS <<< "$EVAL_CMD"
    env -u CLAUDECODE "${EVAL_CMD_ARGS[@]}" 2>&1 | tee "$EVAL_REPORT" || true

    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  📊 评估报告：$EVAL_REPORT"
    echo "═══════════════════════════════════════════════════"
    echo ""
  else
    echo "  （无模板文件，跳过自动评估。如需评估请创建：$TEMPLATE_FILE）"
    echo ""
  fi
}

# ─────────────────────────────────────────────
# 6. 依次运行所有指定批次
# ─────────────────────────────────────────────
for qfile in "${QUESTIONS_FILES[@]}"; do
  run_batch "$qfile"
done
