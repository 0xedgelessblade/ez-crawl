# ez-crawl

> Claude Code / Cowork Skill — 用 Cloudflare `/crawl` API 一鍵爬完整個網站

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-Browser%20Rendering-F38020?logo=cloudflare)](https://developers.cloudflare.com/browser-rendering/)
[![Trigger](https://img.shields.io/badge/trigger-%2Fez_or_ez--crawl-8A2BE2?style=for-the-badge)](SKILL.md)
[![English](https://img.shields.io/badge/📖_English-Quick_Start-white?style=for-the-badge)](#english)

給 Claude 一個網址，它會自動用 Cloudflare 的 headless browser 爬完整站，回傳 Markdown / HTML / JSON。靜態站、SPA、JS 動態渲染都吃得下。

## 目錄

- [功能](#功能)
- [快速開始](#快速開始)
- [專案結構](#專案結構)
- [作為 Skill 使用](#作為-skill-使用)
- [作為獨立腳本使用](#作為獨立腳本使用)
- [範例](#範例)
- [免費方案限制](#免費方案限制)
- [疑難排解](#疑難排解)
- [參考資料](#參考資料)
- [授權](#授權)
- [English](#english)

## 功能

> **快速觸發：** 在 Claude 中輸入 `/ez` 或 `ez crawl` 即可啟動

- **一鍵爬站** — 給一個 URL，自動發現子頁面（sitemap + 連結），回傳整站內容
- **智能判斷** — 自動選擇 `render: true`（SPA）或 `render: false`（靜態站）
- **多種輸出** — Markdown、HTML、JSON（含 AI 結構化擷取）
- **精準控制** — URL pattern 過濾、深度限制、資源阻擋、快取
- **免費方案友好** — 內建省額度策略，教你把免費方案用到極致
- **設定引導** — 第一次用會引導你拿 Account ID 和 API Token

## 快速開始

### 前置需求

- [Cloudflare 帳號](https://dash.cloudflare.com)（免費）
- API Token（需要 **Browser Rendering - Edit** 權限）
- `curl` 和 `jq`
- Python 3.6+（拆分結果用）

### 1. Clone

```bash
git clone https://github.com/0xedgelessblade/ez-crawl.git
cd ez-crawl
```

### 2. 設定 credentials

```bash
cp .env.example .env
# 編輯 .env，填入你的 Account ID 和 API Token
```

> **API Token 怎麼拿？**
> 到 [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens) →
> Create Token → Custom Token → 權限選 Account → Browser Rendering → Edit

### 3. 驗證

```bash
./scripts/verify.sh
```

### 4. 開爬

```bash
# 爬一個文件站（靜態，不跑 JS）
./scripts/crawl.sh https://docs.example.com --limit 50

# 爬 SPA（需要 JS 渲染）
./scripts/crawl.sh https://react.dev --limit 100 --render true --include "/reference/**"

# 拆成個別 Markdown 檔案
python scripts/split-results.py results/crawl-*.json --output-dir pages/
```

## 專案結構

```
ez-crawl/
├── SKILL.md              ← Claude skill 指令（安裝到 Claude 用的）
├── README.md
├── LICENSE
├── CHANGELOG.md
├── .env.example          ← 環境變數範本
├── .gitignore
├── scripts/
│   ├── crawl.sh          ← 一鍵爬站腳本
│   ├── split-results.py  ← 結果拆成個別 Markdown
│   └── verify.sh         ← 驗證 credentials
└── examples/
    ├── static-docs.json  ← 靜態文件站範例
    ├── spa-filtered.json ← SPA + URL 過濾範例
    └── ai-extraction.json← AI 結構化擷取範例
```

## 作為 Skill 使用

安裝到 Claude Code 或 Cowork 後，用自然語言觸發：

```
幫我把 https://docs.astro.build 爬下來轉成 markdown
用 Cloudflare crawl 抓 react.dev 的 API 文件
crawl this site and save as markdown
```

### 安裝方式

**Claude Code:**
```bash
cp -r ez-crawl/ ~/.claude/skills/
```

**Cowork:**
將整個資料夾放到 workspace 的 `.skills/skills/` 目錄下。

## 作為獨立腳本使用

不用 Claude 也能用，`scripts/crawl.sh` 是獨立的 bash 腳本：

```bash
./scripts/crawl.sh <url> [options]
```

| 選項 | 說明 | 預設值 |
|------|------|--------|
| `--limit N` | 最多爬幾頁 | 10 |
| `--render BOOL` | 是否渲染 JS（SPA 設 true） | false |
| `--formats JSON` | 輸出格式 | `["markdown"]` |
| `--include PATTERN` | 只爬符合的 URL | — |
| `--exclude PATTERN` | 排除符合的 URL | — |
| `--output DIR` | 結果目錄 | results/ |
| `--poll N` | polling 間隔秒數 | 5 |

## 範例

### 靜態文件站

```bash
./scripts/crawl.sh https://docs.astro.build/en/getting-started/ \
  --limit 30 --render false --include "**/getting-started/**"
```

`render: false` 不跑 JS，更快，且 beta 期間不計瀏覽器時間。

### SPA + URL 過濾

```bash
./scripts/crawl.sh https://react.dev \
  --limit 100 --render true --include "https://react.dev/reference/react/**"
```

React.dev 是 Next.js SPA，必須 `render: true`。`--include` 確保只爬 API reference。

### AI 結構化擷取

用 `examples/ai-extraction.json` 直接打 API：

```bash
source .env
curl -X POST "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/browser-rendering/crawl" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @examples/ai-extraction.json
```

## 免費方案限制

| 項目 | Workers Free | Workers Paid ($5/月) |
|------|-------------|---------------------|
| 瀏覽器時間 | 10 分鐘/天 | 按用量計費 |
| crawl 工作數 | 5 個/天 | 無限制 |
| 每 job 頁數上限 | 100 頁 | 100,000 頁 |
| API 請求 | 6 次/分鐘 | 600 次/分鐘 |

**省額度技巧：**

- 靜態站用 `render: false`（beta 期間 0 瀏覽器時間）
- 加 `rejectResourceTypes: ["image", "media", "font", "stylesheet"]`
- 用 `includePatterns` 精準控制範圍
- 用 `maxAge` 利用快取

## 疑難排解

| 問題 | 解法 |
|------|------|
| 結果為空 / 全部 skipped | 檢查目標站 robots.txt 是否允許 `CloudflareBrowserRenderingCrawler` |
| `cancelled_due_to_limits` | 免費額度用完，等明天或升級付費方案 |
| 爬很慢 | 改用 `render: false`、加 `rejectResourceTypes` |
| Bot 防護擋住 | /crawl 不繞過 WAF/Turnstile，只能對自己的站加白名單 |
| `verify.sh` 報 Token 無效 | 確認 Token 有 Account → Browser Rendering → Edit 權限 |

## 參考資料

- [/crawl endpoint 官方文件](https://developers.cloudflare.com/browser-rendering/rest-api/crawl-endpoint/)
- [Browser Rendering 限制](https://developers.cloudflare.com/browser-rendering/limits/)
- [Browser Rendering 定價](https://developers.cloudflare.com/browser-rendering/platform/pricing/)
- [REST API 入門](https://developers.cloudflare.com/browser-rendering/get-started/)

## 授權

[MIT](LICENSE)

---

## English

> **Trigger:** Type `/ez` or `ez crawl` in Claude to start crawling.

**ez-crawl** is a Claude Code / Cowork Skill that crawls entire websites using Cloudflare's [`/crawl` REST API](https://developers.cloudflare.com/browser-rendering/rest-api/crawl-endpoint/). Give it a URL — it auto-discovers subpages (via sitemap + links), renders JavaScript if needed, and returns Markdown / HTML / JSON.

### Features

- **One-command crawl** — Give a URL, auto-discover subpages (sitemap + links), return full site content
- **Smart rendering** — Auto-choose `render: true` (SPA) or `render: false` (static sites)
- **Multiple formats** — Markdown, HTML, JSON (with AI structured extraction)
- **Precise control** — URL pattern filtering, depth limits, resource blocking, caching
- **Free-tier friendly** — Built-in quota-saving strategies to maximize your free plan
- **Guided setup** — First-time use walks you through getting Account ID and API Token

### Quick Start

```bash
git clone https://github.com/0xedgelessblade/ez-crawl.git
cd ez-crawl
cp .env.example .env        # fill in CF_ACCOUNT_ID & CF_API_TOKEN
./scripts/verify.sh          # verify credentials
./scripts/crawl.sh https://docs.example.com --limit 50
```

### Get Your Credentials

1. Sign up at [dash.cloudflare.com](https://dash.cloudflare.com) (free)
2. **Account ID** — Dashboard homepage, right sidebar
3. **API Token** — [Create Token](https://dash.cloudflare.com/profile/api-tokens) → Custom Token → Permission: Account → Browser Rendering → Edit

### Use as a Claude Skill

Install into Claude Code or Cowork, then trigger with natural language:

```
crawl this site and save as markdown
use Cloudflare crawl to grab the react.dev API docs
crawl https://docs.astro.build and convert to markdown
```

**Claude Code:** `cp -r ez-crawl/ ~/.claude/skills/`

**Cowork:** Copy the folder to your workspace's `.skills/skills/` directory.

### Use as Standalone Scripts

Works without Claude — `scripts/crawl.sh` is a standalone bash script:

```bash
./scripts/crawl.sh <url> [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--limit N` | Max pages to crawl | 10 |
| `--render BOOL` | Enable JS rendering (set `true` for SPAs) | false |
| `--formats JSON` | Output format | `["markdown"]` |
| `--include PATTERN` | Only crawl matching URLs | — |
| `--exclude PATTERN` | Skip matching URLs | — |
| `--output DIR` | Results directory | results/ |
| `--poll N` | Polling interval in seconds | 5 |

### Examples

**Static docs site** (no JS needed, saves browser time):
```bash
./scripts/crawl.sh https://docs.astro.build/en/getting-started/ \
  --limit 30 --render false --include "**/getting-started/**"
```

**SPA with URL filtering** (React/Next.js, needs JS rendering):
```bash
./scripts/crawl.sh https://react.dev \
  --limit 100 --render true --include "https://react.dev/reference/react/**"
```

### Free Tier Limits

| | Workers Free | Workers Paid ($5/mo) |
|---|---|---|
| Browser time | 10 min/day | Pay-as-you-go |
| Crawl jobs | 5/day | Unlimited |
| Pages per job | 100 | 100,000 |

**Tips to save quota:** use `render: false` for static sites, add `rejectResourceTypes` to block images/fonts, use `includePatterns` to narrow scope, use `maxAge` for caching.

### Troubleshooting

| Problem | Solution |
|---------|----------|
| Empty results / all skipped | Check target site's robots.txt allows `CloudflareBrowserRenderingCrawler` |
| `cancelled_due_to_limits` | Free quota exhausted — wait until tomorrow or upgrade to paid plan |
| Slow crawling | Use `render: false`, add `rejectResourceTypes`, reduce `limit` |
| Blocked by bot protection | /crawl cannot bypass WAF/Turnstile — only whitelist your own sites |
| `verify.sh` says token invalid | Confirm token has Account → Browser Rendering → Edit permission |

### References

- [/crawl endpoint docs](https://developers.cloudflare.com/browser-rendering/rest-api/crawl-endpoint/)
- [Browser Rendering limits](https://developers.cloudflare.com/browser-rendering/limits/)
- [Browser Rendering pricing](https://developers.cloudflare.com/browser-rendering/platform/pricing/)
- [REST API getting started](https://developers.cloudflare.com/browser-rendering/get-started/)
