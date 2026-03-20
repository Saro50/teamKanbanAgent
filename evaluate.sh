#!/usr/bin/env bash
# evaluate.sh — 独立评估脚本
#
# 用法：
#   ./evaluate.sh -r results/batch_01_basic/records/20260319_150503.md   # 评估指定记录
#   ./evaluate.sh --batch batch_01_basic                                 # 评估该批次最新一份记录
#   ./evaluate.sh --all                                                  # 评估所有批次各自最新的记录

set -euo pipefail

# ─────────────────────────────────────────────
# 0. 路径定位
# ─────────────────────────────────────────────
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$PROJECT_ROOT/src/tests"
RESULTS_DIR="$PROJECT_ROOT/results"

# ─────────────────────────────────────────────
# 1. 读取 .env 中的评估命令模板
# ─────────────────────────────────────────────
load_eval_cmd() {
  local ENV_FILE="$PROJECT_ROOT/.env"
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ 未找到 .env 文件" >&2
    exit 1
  fi
  EVAL_CMD_TEMPLATE=$(grep '^\s*EVALUTION_CMD=' "$ENV_FILE" | head -1 | sed 's/^\s*EVALUTION_CMD=//' | sed 's/\r//')
  if [[ -z "$EVAL_CMD_TEMPLATE" ]]; then
    echo "❌ .env 中未找到 EVALUTION_CMD" >&2
    exit 1
  fi
}

# ─────────────────────────────────────────────
# 2. 核心评估函数
#    参数：$1 = 记录文件路径（如 results/batch_01_basic/records/20260319_150503.md）
# ─────────────────────────────────────────────
run_eval() {
  local RECORD_FILE="$1"

  if [[ ! -f "$RECORD_FILE" ]]; then
    echo "❌ 找不到记录文件：$RECORD_FILE" >&2
    return 1
  fi

  # 从路径推导批次名：results/<batch_name>/records/<timestamp>.md
  local BATCH_NAME
  BATCH_NAME=$(basename "$(dirname "$(dirname "$RECORD_FILE")")")
  local RECORD_BASENAME
  RECORD_BASENAME=$(basename "$RECORD_FILE" .md)

  # 查找对应的评分模板
  local TEMPLATE_FILE="$TESTS_DIR/${BATCH_NAME}.template.md"
  if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "⚠️  未找到模板文件：$TEMPLATE_FILE，跳过 $RECORD_FILE" >&2
    return 0
  fi

  # 评估输出目录
  local EVALS_DIR
  EVALS_DIR="$(dirname "$(dirname "$RECORD_FILE")")/evals"
  mkdir -p "$EVALS_DIR"
  local EVAL_REPORT="$EVALS_DIR/${RECORD_BASENAME}.md"

  # 检查是否已评估过
  if [[ -f "$EVAL_REPORT" ]]; then
    local EXISTING_SIZE
    EXISTING_SIZE=$(wc -c < "$EVAL_REPORT" | tr -d ' ')
    if [[ "$EXISTING_SIZE" -gt 512 ]]; then
      echo "  ⏭  已存在有效评估，跳过：$EVAL_REPORT"
      return 0
    fi
  fi

  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  📐 评估批次：$BATCH_NAME"
  echo "  📄 记录文件：$RECORD_FILE"
  echo "  📋 评分模板：$TEMPLATE_FILE"
  echo "  📊 输出文件：$EVAL_REPORT"
  echo "═══════════════════════════════════════════════════"
  echo ""

  # 构造评估 prompt
  local COMPARISON_CONTENT
  COMPARISON_CONTENT=$(cat "$RECORD_FILE")
  local EVAL_PROMPT
  EVAL_PROMPT="你是一个 AI 输出质量评估专家。请根据系统提示中提供的【评估模板】，对以下【对比报告】中两个 Agent 的输出逐题打分，最终生成结构化的 Markdown 评估报告，包含：
1. 逐题评分表（Agent A / Agent B 各维度分数 + 简评）
2. 综合评分汇总表
3. 总体评价与使用场景建议

# 对比报告

${COMPARISON_CONTENT}"

  # 替换 {SystemPrompts}；{Prompts} 作为独立参数传递
  local EVAL_CMD_PREFIX
  EVAL_CMD_PREFIX="${EVAL_CMD_TEMPLATE/\{SystemPrompts\}/$TEMPLATE_FILE}"
  EVAL_CMD_PREFIX="${EVAL_CMD_PREFIX/\{Prompts\}/}"

  echo "  $ ${EVAL_CMD_PREFIX} \"<prompt: ${#EVAL_PROMPT} chars>\""
  echo ""

  read -ra EVAL_CMD_ARGS <<< "$EVAL_CMD_PREFIX"
  env -u CLAUDECODE "${EVAL_CMD_ARGS[@]}" "$EVAL_PROMPT" 2>&1 | tee "$EVAL_REPORT" || true

  echo ""
  echo "  ✅ 评估完成：$EVAL_REPORT"
  echo ""
}

# ─────────────────────────────────────────────
# 3. 辅助：获取某批次最新记录文件
# ─────────────────────────────────────────────
latest_record() {
  local BATCH_NAME="$1"
  local RECORDS_DIR="$RESULTS_DIR/$BATCH_NAME/records"
  if [[ ! -d "$RECORDS_DIR" ]]; then
    echo ""
    return
  fi
  # 按文件名排序（时间戳命名，字典序即时间序）
  find "$RECORDS_DIR" -maxdepth 1 -name "*.md" | sort | tail -1
}

# ─────────────────────────────────────────────
# 4. 解析命令行参数
# ─────────────────────────────────────────────
RECORD_FILES=()
BATCH_NAMES=()
EVAL_ALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--record)
      RECORD_FILES+=("$2"); shift 2 ;;
    -b|--batch)
      BATCH_NAMES+=("$2"); shift 2 ;;
    --all)
      EVAL_ALL=true; shift ;;
    -h|--help)
      echo "用法："
      echo "  $0 -r <记录文件>        评估指定记录文件"
      echo "  $0 -b <批次名>          评估该批次最新记录"
      echo "  $0 --all                评估所有批次最新记录"
      echo ""
      echo "示例："
      echo "  $0 -r results/batch_01_basic/records/20260319_150503.md"
      echo "  $0 -b batch_01_basic"
      echo "  $0 --all"
      exit 0 ;;
    *)
      echo "❌ 未知参数：$1" >&2
      echo "用法：$0 [-r <记录文件>] [-b <批次名>] [--all]" >&2
      exit 1 ;;
  esac
done

# --all：扫描所有批次目录
if $EVAL_ALL; then
  while IFS= read -r d; do
    bname=$(basename "$d")
    BATCH_NAMES+=("$bname")
  done < <(find "$RESULTS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
fi

# 将批次名解析为最新记录文件
if [[ ${#BATCH_NAMES[@]} -gt 0 ]]; then
  for bname in "${BATCH_NAMES[@]}"; do
    latest=$(latest_record "$bname")
    if [[ -n "$latest" ]]; then
      RECORD_FILES+=("$latest")
    else
      echo "⚠️  批次 $bname 没有记录文件，跳过" >&2
    fi
  done
fi

if [[ ${#RECORD_FILES[@]} -eq 0 ]]; then
  echo "用法：$0 -r <记录文件>  或  $0 -b <批次名>  或  $0 --all" >&2
  echo ""
  echo "可用批次：" >&2
  find "$RESULTS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | while read -r d; do
    bname=$(basename "$d")
    latest=$(latest_record "$bname")
    if [[ -n "$latest" ]]; then
      echo "  $bname  →  $(basename "$latest")" >&2
    fi
  done
  exit 1
fi

# ─────────────────────────────────────────────
# 5. 执行评估
# ─────────────────────────────────────────────
load_eval_cmd

echo "🔍 待评估记录：${#RECORD_FILES[@]} 份"
for rf in "${RECORD_FILES[@]}"; do
  run_eval "$rf"
done

echo "═══════════════════════════════════════════════════"
echo "  🎉 全部评估完成"
echo "═══════════════════════════════════════════════════"
