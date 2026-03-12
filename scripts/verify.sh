#!/usr/bin/env bash
# verify.sh — 驗證 Cloudflare credentials 是否正確
#
# 用法: ./scripts/verify.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ENV_FILE="${ENV_FILE:-.env}"

echo "=== Cloudflare /crawl API 環境檢查 ==="
echo ""

# 1. 檢查 .env
if [[ -f "$ENV_FILE" ]]; then
  echo -e "${GREEN}✓${NC} .env 檔案存在"
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo -e "${RED}✗${NC} 找不到 .env 檔案"
  echo "  請先: cp .env.example .env && 填入你的 credentials"
  exit 1
fi

# 2. 檢查變數
if [[ -n "${CF_ACCOUNT_ID:-}" ]]; then
  echo -e "${GREEN}✓${NC} CF_ACCOUNT_ID 已設定 (${CF_ACCOUNT_ID:0:8}...)"
else
  echo -e "${RED}✗${NC} CF_ACCOUNT_ID 未設定"
  exit 1
fi

if [[ -n "${CF_API_TOKEN:-}" ]]; then
  echo -e "${GREEN}✓${NC} CF_API_TOKEN 已設定 (${CF_API_TOKEN:0:8}...)"
else
  echo -e "${RED}✗${NC} CF_API_TOKEN 未設定"
  exit 1
fi

# 3. 檢查工具
for cmd in curl jq; do
  if command -v "$cmd" &> /dev/null; then
    echo -e "${GREEN}✓${NC} $cmd 已安裝"
  else
    echo -e "${RED}✗${NC} $cmd 未安裝"
    exit 1
  fi
done

# 4. 測試 API 連線
echo ""
echo -e "${YELLOW}▶ 測試 API 連線...${NC}"

RESPONSE=$(curl -s -w "\n%{http_code}" \
  "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer ${CF_API_TOKEN}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" == "200" ]]; then
  echo -e "${GREEN}✓${NC} API Token 有效"
else
  echo -e "${RED}✗${NC} API Token 無效 (HTTP ${HTTP_CODE})"
  echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
  exit 1
fi

# 5. 測試 Browser Rendering 權限
echo -e "${YELLOW}▶ 測試 Browser Rendering 權限...${NC}"

BR_RESPONSE=$(curl -s -w "\n%{http_code}" \
  "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/browser-rendering/screenshot" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}' \
  -o /dev/null)

BR_CODE=$(echo "$BR_RESPONSE" | tail -1)

if [[ "$BR_CODE" == "200" ]] || [[ "$BR_CODE" == "400" ]] || [[ "$BR_CODE" == "429" ]]; then
  echo -e "${GREEN}✓${NC} Browser Rendering 權限正常"
else
  echo -e "${RED}✗${NC} Browser Rendering 權限有問題 (HTTP ${BR_CODE})"
  echo "  請確認 API Token 有 Account → Browser Rendering → Edit 權限"
  exit 1
fi

echo ""
echo -e "${GREEN}=== 全部通過！可以開始爬了 ===${NC}"
echo ""
echo "試試看:"
echo "  ./scripts/crawl.sh https://example.com --limit 5"
