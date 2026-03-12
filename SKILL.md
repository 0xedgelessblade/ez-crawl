---
name: ez-crawl
description: |
  Cloudflare /crawl API 網站爬取工具。當使用者想要爬取、擷取、抓取一個網站的內容時，
  用 Cloudflare Browser Rendering 的 /crawl REST API 來完成，而不是用瀏覽器手動操作。
  觸發時機：使用者說「/ez」、「ez crawl」、「用 Cloudflare 爬」、「CF crawl」、
  「用 /crawl API」、「幫我爬這個網站」、「抓這個站的內容」、「crawl this site」、
  「把這個網站的內容都抓下來」、「爬完整站」、「抓整站 markdown」等。
  也適用於使用者提到想把某個文件站、部落格、產品頁批量轉成 markdown 或 JSON，
  或者需要建 RAG knowledge base、訓練資料集時想批量抓網頁內容。
  只要涉及「用 API 批量爬網站」的場景都應觸發，即使使用者沒有明確說 Cloudflare。
  不適用於單一頁面的簡單抓取（那用 WebFetch 就好）或需要登入互動的瀏覽器操作。
---

# ez-crawl — Cloudflare /crawl API 網站爬取工具

> **快速觸發指令：** `/ez` 或 `ez crawl`

## 這個 skill 做什麼

用 Cloudflare 的 `/crawl` REST API 爬取整個網站。一個 HTTP 請求發出去，Cloudflare 的 headless browser 會自動發現子頁面（從 sitemap + 頁面連結），渲染 JavaScript 動態內容，回傳 HTML / Markdown / JSON。

核心流程：發起 crawl → polling 等完成 → 取回結果 → 存檔處理。

## 前置條件檢查

每次觸發時，先檢查 credentials 是否就位：

1. 找 `.env` 檔案：在使用者的工作目錄或專案目錄中尋找

2. 需要的環境變數：
   - `CF_ACCOUNT_ID` — Cloudflare Account ID（32 字元 hex）
   - `CF_API_TOKEN` — 有 Browser Rendering - Edit 權限的 API Token

3. 如果找不到 → 進入「初次設定」流程（見下方）

## 初次設定流程

如果沒有 credentials，引導使用者完成設定：

### Step 1：確認 Cloudflare 帳號
問使用者是否已有帳號。沒有的話，請他到 https://dash.cloudflare.com 註冊（免費帳號即可）。

### Step 2：取得 Account ID
引導使用者到 Dashboard 首頁，右邊欄找到 Account ID（32 字元 hex 字串）。
或到 Workers & Pages → Overview 右邊欄。

### Step 3：建立 API Token
引導使用者到 https://dash.cloudflare.com/profile/api-tokens：
1. Create Token → Create Custom Token
2. Token name: `browser-rendering`（或任意名稱）
3. Permissions: Account → **Browser Rendering** → **Edit**
4. Account Resources: Include → 使用者的帳號
5. Continue to summary → Create Token → 複製（只顯示一次！）

### Step 4：存到 .env
在專案目錄建立 `.env` 檔案：
```
CF_ACCOUNT_ID=你的AccountID
CF_API_TOKEN=你的Token
```

拿到 credentials 後，用一個簡單的 API 呼叫驗證連線：
```bash
source .env
curl -s "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/browser-rendering" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" | jq '.success'
```
回傳 `true` 就代表設定成功。

## 爬取流程

### 1. 分析目標

根據使用者提供的 URL，決定最佳策略：

| 網站類型 | render | 理由 |
|---------|--------|------|
| 靜態文件站（docs、blog、wiki） | `false` | 內容在原始 HTML 裡，不跑 JS 更快，beta 期間不計瀏覽器時間 |
| SPA / React / Vue / Next.js | `true` | 需要 JS 渲染才能拿到內容 |
| 不確定 | `true` | 預設安全選擇 |

### 2. 組裝請求參數

基本模板：
```json
{
  "url": "目標 URL",
  "limit": 50,
  "formats": ["markdown"],
  "render": false
}
```

根據需求加入可選參數：

- **控制範圍**：`depth`（連結深度）、`options.includePatterns` / `excludePatterns`（URL 過濾）
- **跨域**：`options.includeSubdomains`、`options.includeExternalLinks`
- **發現方式**：`source`（`all` | `sitemaps` | `links`）
- **快取**：`maxAge`（秒，預設 86400）、`modifiedSince`（Unix timestamp）
- **加速**：`rejectResourceTypes`（擋掉 `image`、`media`、`font`、`stylesheet`）
- **等待動態內容**：`gotoOptions.waitUntil`、`waitForSelector`
- **AI 結構化擷取**：`formats: ["json"]` + `jsonOptions`（需要 Workers AI）

### 3. 執行 crawl

```bash
# 讀取 credentials
source .env

# 發起 crawl
JOB_ID=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/browser-rendering/crawl" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '<JSON payload>' \
  | jq -r '.result')

echo "Job ID: ${JOB_ID}"
```

### 4. Polling 等完成

```bash
while true; do
  STATUS=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/browser-rendering/crawl/${JOB_ID}?limit=1" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    | jq -r '.result.status')

  echo "狀態: ${STATUS}"

  case "${STATUS}" in
    "completed") break ;;
    "running") sleep 5 ;;
    *) echo "異常狀態: ${STATUS}"; break ;;
  esac
done
```

狀態值：
- `running` — 進行中
- `completed` — 完成
- `errored` — 出錯
- `cancelled_due_to_timeout` — 超過 7 天
- `cancelled_due_to_limits` — 帳號額度用完
- `cancelled_by_user` — 手動取消

### 5. 取回結果

```bash
curl -s -X GET \
  "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/browser-rendering/crawl/${JOB_ID}" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  > crawl-result.json
```

如果結果超過 10 MB，會有 `cursor` 分頁，需要用 `?cursor=X&limit=N` 逐頁取。

也可以用 `?status=completed` 只拿成功的、`?status=skipped` 查看被跳過的 URL。

### 6. 結果處理

回傳的 JSON 結構：
```json
{
  "result": {
    "id": "job-id",
    "status": "completed",
    "browserSecondsUsed": 134.7,
    "total": 50,
    "finished": 50,
    "records": [
      {
        "url": "https://...",
        "status": "completed",
        "markdown": "# Page Title\n...",
        "metadata": { "status": 200, "title": "Page Title" }
      }
    ]
  }
}
```

常見的後處理：

**拆成個別 Markdown 檔案：**
```bash
jq -r '.result.records[] | select(.status=="completed") |
  "\(.metadata.title // .url)\n---\n\(.markdown)"' crawl-result.json
```

或用 Python 腳本把每頁存成獨立 `.md` 檔。

**統計摘要：**
```bash
echo "總頁數: $(jq '.result.total' crawl-result.json)"
echo "完成: $(jq '[.result.records[] | select(.status=="completed")] | length' crawl-result.json)"
echo "跳過: $(jq '[.result.records[] | select(.status=="skipped")] | length' crawl-result.json)"
echo "瀏覽器時間: $(jq '.result.browserSecondsUsed' crawl-result.json) 秒"
```

## 免費方案限制

使用者如果是 Workers Free 方案，要注意：

| 項目 | 限制 |
|------|------|
| 瀏覽器時間 | 每天 10 分鐘 |
| REST API 請求 | 每分鐘 6 次（每 10 秒 1 次） |
| crawl 工作數 | 每天 5 個 |
| 每個 crawl 最大頁數 | 100 頁 |

省時間策略：
- 靜態站用 `render: false`（beta 期間不計瀏覽器時間）
- 用 `rejectResourceTypes` 擋掉圖片/字型
- 用 `maxAge` 利用快取避免重複爬
- 用 `includePatterns` 精準控制範圍，不浪費頁數配額

付費方案（$5/月 Workers Paid）：crawl job 數無限制，每 job 最多 100,000 頁。

## 取消 crawl

```bash
curl -X DELETE \
  "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/browser-rendering/crawl/${JOB_ID}" \
  -H "Authorization: Bearer ${CF_API_TOKEN}"
```

## 疑難排解

| 問題 | 原因 | 解法 |
|------|------|------|
| 結果為空或全部 skipped | robots.txt 擋了 `CloudflareBrowserRenderingCrawler/1.0` | 先不帶 pattern 試爬，確認 URL 可發現 |
| 全部 disallowed | 網站 robots.txt 禁止爬取 | 檢查目標站的 robots.txt，考慮是否有權限 |
| cancelled_due_to_limits | 帳號額度用完（免費方案 10 分鐘/天） | 升級付費方案，或用 `render: false` |
| 爬很慢 | JS 重的頁面渲染慢 | 用 `render: false`、`rejectResourceTypes`、縮小 `limit` |
| 被 bot 防護擋 | Cloudflare WAF / Turnstile | /crawl 無法繞過防護，只能對自己的站加白名單 |
| JSON 格式結果為 null | prompt 不夠明確 | 給更具體的 `jsonOptions.prompt` 和 `response_format` |

## 參考資料

- [/crawl endpoint 官方文件](https://developers.cloudflare.com/browser-rendering/rest-api/crawl-endpoint/)
- [Browser Rendering 限制](https://developers.cloudflare.com/browser-rendering/limits/)
- [Browser Rendering 定價](https://developers.cloudflare.com/browser-rendering/platform/pricing/)
- [REST API 入門](https://developers.cloudflare.com/browser-rendering/get-started/)
