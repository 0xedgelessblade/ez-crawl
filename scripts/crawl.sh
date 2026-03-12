#!/usr/bin/env bash
# crawl.sh — Cloudflare /crawl API 一鍵爬站腳本
#
# 用法:
#   ./scripts/crawl.sh <url> [options]
#
# 範例:
#   ./scripts/crawl.sh https://docs.example.com
#   ./scripts/crawl.sh https://docs.example.com --limit 50 --render false
#   ./scripts/crawl.sh https://react.dev --limit 100 --render true --include "/reference/**"
#
# 環境變數 (從 .env 讀取):
#   CF_ACCOUNT_ID  — Cloudflare Account ID
#   CF_API_TOKEN   — API Token (Browser Rendering - Edit)

set -euo pipefail

# ─── 顏色 ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ─── 讀取 .env ───
ENV_FILE="${ENV_FILE:-.env}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

# ─── 驗證必要變數 ───
if [[ -z "${CF_ACCOUNT_ID:-}" ]] || [[ -z "${CF_API_TOKEN:-}" ]]; then
  echo -e "${RED}錯誤: 找不到 CF_ACCOUNT_ID 或 CF_API_TOKEN${NC}"
  echo ""
  echo "請先設定 .env 檔案（參考 .env.example）:"
  echo "  cp .env.example .env"
  echo "  # 然後填入你的 Account ID 和 API Token"
  exit 1
fi

# ─── 驗證必要工具 ───
for cmd in curl jq; do
  if ! command -v "$cmd" &> /dev/null; then
    echo -e "${RED}錯誤: 需要 $cmd，請先安裝${NC}"
    exit 1
  fi
done

# ─── 預設參數 ───
URL=""
LIMIT=10
RENDER="false"
FORMATS='["markdown"]'
INCLUDE_PATTERN=""
EXCLUDE_PATTERN=""
OUTPUT_DIR="results"
POLL_INTERVAL=5

# ─── 解析參數 ───
usage() {
  echo "用法: $0 <url> [options]"
  echo ""
  echo "選項:"
  echo "  --limit N          最多爬幾頁 (預設: 10, 免費方案上限: 100)"
  echo "  --render BOOL      是否渲染 JS (預設: false, SPA 需要 true)"
  echo "  --formats JSON     輸出格式 (預設: [\"markdown\"])"
  echo "  --include PATTERN  只爬符合的 URL pattern"
  echo "  --exclude PATTERN  排除符合的 URL pattern"
  echo "  --output DIR       結果存放目錄 (預設: results)"
  echo "  --poll N           polling 間隔秒數 (預設: 5)"
  echo "  -h, --help         顯示此說明"
  exit 0
}

if [[ $# -lt 1 ]]; then
  usage
fi

URL="$1"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMIT="$2"; shift 2 ;;
    --render) RENDER="$2"; shift 2 ;;
    --formats) FORMATS="$2"; shift 2 ;;
    --include) INCLUDE_PATTERN="$2"; shift 2 ;;
    --exclude) EXCLUDE_PATTERN="$2"; shift 2 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --poll) POLL_INTERVAL="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo -e "${RED}未知選項: $1${NC}"; usage ;;
  esac
done

# ─── 建立輸出目錄 ───
mkdir -p "$OUTPUT_DIR"

# ─── 組裝 JSON payload ───
PAYLOAD=$(jq -n \
  --arg url "$URL" \
  --argjson limit "$LIMIT" \
  --argjson render "$RENDER" \
  --argjson formats "$FORMATS" \
  '{url: $url, limit: $limit, render: $render, formats: $formats, rejectResourceTypes: ["image", "media", "font"]}')

# 加入 includePatterns
if [[ -n "$INCLUDE_PATTERN" ]]; then
  PAYLOAD=$(echo "$PAYLOAD" | jq --arg p "$INCLUDE_PATTERN" '. + {options: {includePatterns: [$p]}}')
fi

# 加入 excludePatterns
if [[ -n "$EXCLUDE_PATTERN" ]]; then
  if echo "$PAYLOAD" | jq -e '.options' > /dev/null 2>&1; then
    PAYLOAD=$(echo "$PAYLOAD" | jq --arg p "$EXCLUDE_PATTERN" '.options.excludePatterns = [$p]')
  else
    PAYLOAD=$(echo "$PAYLOAD" | jq --arg p "$EXCLUDE_PATTERN" '. + {options: {excludePatterns: [$p]}}')
  fi
fi

# ─── Step 1: 發起 crawl ───
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
echo -e "${CYAN}=== Cloudflare /crawl ===${NC}"
echo -e "目標:   ${URL}"
echo -e "上限:   ${LIMIT} 頁"
echo -e "渲染:   render=${RENDER}"
echo ""

echo -e "${YELLOW}▶ 發起 crawl...${NC}"

RESPONSE=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/browser-rendering/crawl" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
if [[ "$SUCCESS" != "true" ]]; then
  echo -e "${RED}發起失敗:${NC}"
  echo "$RESPONSE" | jq .
  exit 1
fi

JOB_ID=$(echo "$RESPONSE" | jq -r '.result')
echo -e "${GREEN}✓ Job ID: ${JOB_ID}${NC}"

# ─── Step 2: Polling ───
echo -e "${YELLOW}▶ 等待完成...${NC}"

ATTEMPTS=0
MAX_ATTEMPTS=360  # 30 分鐘 (5s × 360)

while true; do
  STATUS_RESPONSE=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/browser-rendering/crawl/${JOB_ID}?limit=1" \
    -H "Authorization: Bearer ${CF_API_TOKEN}")

  STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.result.status')
  TOTAL=$(echo "$STATUS_RESPONSE" | jq -r '.result.total // 0')
  FINISHED=$(echo "$STATUS_RESPONSE" | jq -r '.result.finished // 0')

  echo -ne "\r  狀態: ${STATUS} | 完成: ${FINISHED}/${TOTAL}    "

  if [[ "$STATUS" != "running" ]]; then
    echo ""
    break
  fi

  ATTEMPTS=$((ATTEMPTS + 1))
  if [[ $ATTEMPTS -ge $MAX_ATTEMPTS ]]; then
    echo ""
    echo -e "${RED}逾時：超過 30 分鐘${NC}"
    exit 1
  fi

  sleep "$POLL_INTERVAL"
done

# ─── Step 3: 取回結果 ───
if [[ "$STATUS" != "completed" ]]; then
  echo -e "${RED}Crawl 未完成，狀態: ${STATUS}${NC}"
  echo "$STATUS_RESPONSE" | jq .
  exit 1
fi

RESULT_FILE="${OUTPUT_DIR}/crawl-${TIMESTAMP}.json"
echo -e "${YELLOW}▶ 下載結果...${NC}"

curl -s -X GET \
  "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/browser-rendering/crawl/${JOB_ID}" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  > "$RESULT_FILE"

# 處理分頁
CURSOR=$(jq -r '.result.cursor // empty' "$RESULT_FILE")
PAGE=1
while [[ -n "${CURSOR:-}" ]]; do
  PAGE=$((PAGE + 1))
  PAGE_FILE="${OUTPUT_DIR}/crawl-${TIMESTAMP}-page${PAGE}.json"
  echo "  取得第 ${PAGE} 頁..."
  curl -s -X GET \
    "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/browser-rendering/crawl/${JOB_ID}?cursor=${CURSOR}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    > "$PAGE_FILE"
  CURSOR=$(jq -r '.result.cursor // empty' "$PAGE_FILE")
done

# ─── 統計 ───
echo ""
echo -e "${GREEN}=== 完成 ===${NC}"
echo -e "  結果檔案:     ${RESULT_FILE}"
echo -e "  總頁數:       $(jq '.result.total' "$RESULT_FILE")"
echo -e "  成功:         $(jq '[.result.records[] | select(.status=="completed")] | length' "$RESULT_FILE")"
echo -e "  跳過:         $(jq '[.result.records[] | select(.status=="skipped")] | length' "$RESULT_FILE")"
echo -e "  不允許:       $(jq '[.result.records[] | select(.status=="disallowed")] | length' "$RESULT_FILE")"
echo -e "  瀏覽器時間:   $(jq '.result.browserSecondsUsed' "$RESULT_FILE") 秒"
echo ""
echo -e "下一步: 用 ${CYAN}python scripts/split-results.py ${RESULT_FILE}${NC} 拆成個別 Markdown 檔案"
