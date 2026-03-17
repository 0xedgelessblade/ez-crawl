<p align="center">
  <img src="assets/banner.svg" alt="ez-crawl" width="720" />
</p>

<h1 align="center">ez-crawl</h1>

<p align="center">
  <strong>給一個 URL，整站爬回來變 Markdown。</strong><br/>
  Claude Code / Cowork skill + 獨立 CLI，用 Cloudflare headless browser 爬站 — 靜態站、SPA、JS 動態渲染都吃。
</p>

<p align="center">
  <a href="#-quick-start"><img src="https://img.shields.io/badge/Quick_Start-→-e67a1e?style=for-the-badge&labelColor=2c2420" alt="Quick Start" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-e67a1e?style=for-the-badge&labelColor=2c2420" alt="MIT License" /></a>
  <a href="https://developers.cloudflare.com/browser-rendering/"><img src="https://img.shields.io/badge/Cloudflare-/crawl_API-e67a1e?style=for-the-badge&labelColor=2c2420" alt="Cloudflare" /></a>
  <a href="README.en.md"><img src="https://img.shields.io/badge/📖_English-README-e67a1e?style=for-the-badge&labelColor=2c2420" alt="English" /></a>
</p>

<br/>

---

## 為什麼做這個

你想把一整個文件站餵進 LLM、建 local knowledge base、或單純備份成乾淨的 Markdown。一般作法？自己寫 scraper，處理分頁、JS rendering、rate limit。每個站都來一次。

**ez-crawl** 把 Cloudflare 的 [`/crawl` REST API](https://developers.cloudflare.com/browser-rendering/rest-api/crawl-endpoint/) 包成一條指令。給一個 URL — 它自動透過 sitemap + link following 發現子頁面，可選擇是否 render JavaScript，然後回傳 Markdown、HTML、或 structured JSON。整個 crawl 跑在 Cloudflare 的 infra 上，你不用自己架 Puppeteer。

可以當 Claude skill 用（說「爬這個站」就好），也可以當獨立 bash script 跑。一個 URL 進去，整站出來。

---

## ✦ Features

**One-Command Crawl** — 給一個 URL，自動發現子頁面（sitemap + link traversal）。不用寫 config、不用裝一堆 dependency — 就 `crawl.sh <url>`。

**Smart Rendering** — 靜態 HTML 站用 `render: false`，快且省額度。React / Next.js SPA 用 `render: true` 跑 headless browser。Claude skill 會自動判斷。

**Multiple Output Formats** — Markdown（預設，最適合餵 LLM）、HTML、或 JSON（搭配 Workers AI 做 structured extraction）。自定義 schema 抽產品名稱、價格、描述都行。

**Free Tier Friendly** — 內建省額度策略：resource blocking、URL pattern filtering、`maxAge` caching、smart render toggling。免費方案的 10 分鐘用到極致。

---

## ✦ Quick Start

### 前置需求

- [Cloudflare 帳號](https://dash.cloudflare.com)（免費）
- API Token（需要 **Browser Rendering → Edit** 權限）
- `curl`、`jq`、Python 3.6+

### Setup

1. **Clone**

```bash
git clone https://github.com/0xedgelessblade/ez-crawl.git
cd ez-crawl
```

2. **設定 credentials**

```bash
cp .env.example .env
# 編輯 .env — 填入 CF_ACCOUNT_ID 和 CF_API_TOKEN
```

> **怎麼拿？**
> **Account ID** — [Dashboard](https://dash.cloudflare.com) 首頁右邊欄。
> **API Token** — [Create Token](https://dash.cloudflare.com/profile/api-tokens) → Custom Token → 權限選 *Account → Browser Rendering → Edit*。

3. **驗證**

```bash
./scripts/verify.sh
```

4. **開爬**

```bash
./scripts/crawl.sh https://docs.example.com --limit 50

# 拆成個別 Markdown 檔案
python scripts/split-results.py results/crawl-*.json --output-dir pages/
```

---

## ✦ How It Works

```
                    ┌──────────────────┐
  給一個 URL        │   crawl.sh       │    Markdown 檔案
  ───────────────▶  │                  │  ──────────────────▶
                    │  1. POST /crawl  │    pages/
                    │  2. Poll status  │    ├── getting-started.md
                    │  3. Fetch result │    ├── api-reference.md
                    │  4. Split pages  │    └── ...
                    └──────────────────┘
                           │
                    Cloudflare Browser
                    Rendering 負責
                    實際的 crawling
```

三個階段：

1. **Submit** — `crawl.sh` 送 POST 到 Cloudflare 的 `/crawl` endpoint，帶上 URL、page limit、render 設定。
2. **Poll** — 每幾秒檢查 job 狀態，直到 Cloudflare 爬完所有子頁面。
3. **Collect** — 結果回來是一包 JSON。`split-results.py` 拆成個別 Markdown 檔，附 YAML frontmatter（title、URL、status）。

---

## ✦ 作為 Claude Skill 使用

安裝到 Claude Code 或 Cowork，用自然語言觸發：

```
幫我把 https://docs.astro.build 爬下來轉成 markdown
用 Cloudflare crawl 抓 react.dev 的 API 文件
crawl this site and save as markdown
```

**Claude Code:**
```bash
cp -r ez-crawl/ ~/.claude/skills/
```

**Cowork:**
把資料夾放到 workspace 的 `.skills/skills/` 目錄下。

> **觸發語句：** `/ez`、`ez crawl`、或直接描述你想爬什麼。

---

## ✦ CLI Reference

```bash
./scripts/crawl.sh <url> [options]
```

| Option | 預設值 | 說明 |
|--------|--------|------|
| `--limit N` | `10` | 最多爬幾頁（free tier 上限 100） |
| `--render BOOL` | `false` | 是否 render JS — SPA 設 `true` |
| `--formats JSON` | `["markdown"]` | 輸出格式：`markdown`、`html`、`json` |
| `--include PATTERN` | — | 只爬符合的 URL glob |
| `--exclude PATTERN` | — | 排除符合的 URL glob |
| `--output DIR` | `results/` | 結果存放目錄 |
| `--poll N` | `5` | Polling 間隔秒數 |

---

## ✦ Examples

**靜態文件站** — 不跑 JS，省 browser time：
```bash
./scripts/crawl.sh https://docs.astro.build/en/getting-started/ \
  --limit 30 --render false --include "**/getting-started/**"
```

**SPA + URL filtering** — React / Next.js，需要 JS rendering：
```bash
./scripts/crawl.sh https://react.dev \
  --limit 100 --render true --include "https://react.dev/reference/react/**"
```

**AI Structured Extraction** — 用 Workers AI 抽結構化資料：
```bash
source .env
curl -X POST \
  "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/browser-rendering/crawl" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @examples/ai-extraction.json
```

更多 payload 範本見 [`examples/`](examples/)。

---

## ✦ Free Tier 限制

| | Workers Free | Workers Paid ($5/mo) |
|---|---|---|
| Browser time | 10 min/day | Pay-as-you-go |
| Crawl jobs | 5/day | Unlimited |
| Pages per job | 100 | 100,000 |
| API requests | 6/min | 600/min |

**省額度技巧：** 靜態站用 `render: false`（beta 期間 0 browser time）、加 `rejectResourceTypes: ["image", "media", "font", "stylesheet"]` 擋重資源、用 `includePatterns` 縮小範圍、設 `maxAge` 利用 cache。

---

## ✦ Troubleshooting

| 問題 | 解法 |
|------|------|
| 結果為空 / 全部 skipped | 檢查目標站 `robots.txt` 是否允許 `CloudflareBrowserRenderingCrawler` |
| `cancelled_due_to_limits` | 免費額度用完，等明天或升級 paid plan |
| 爬很慢 | 用 `render: false`、加 `rejectResourceTypes`、降低 `--limit` |
| Bot 防護擋住 | `/crawl` 無法繞過 WAF / Turnstile — 只能對自己的站加白名單 |
| `verify.sh` 報 token 無效 | 確認 token 有 *Account → Browser Rendering → Edit* 權限 |

---

## ✦ Project Structure

```
ez-crawl/
├── README.md                  # 你在這裡（中文）
├── README.en.md               # English version
├── SKILL.md                   # Claude skill 指令
├── LICENSE                    # MIT
├── CHANGELOG.md               # 版本紀錄
├── .env.example               # Credential 範本（.env 不會進 git！）
├── .gitignore                 # OS + editor + language ignores
├── assets/
│   └── banner.svg             # README header banner
├── scripts/
│   ├── crawl.sh               # 主角 — 一鍵爬站腳本
│   ├── split-results.py       # 拆 JSON 結果成個別 Markdown
│   └── verify.sh              # 驗證 Cloudflare credentials
└── examples/
    ├── static-docs.json       # 靜態站 crawl payload
    ├── spa-filtered.json      # SPA + URL filtering payload
    └── ai-extraction.json     # AI structured extraction payload
```

---

## ✦ License

[MIT](LICENSE) — 愛怎麼用就怎麼用。

---

## ✦ References

- [/crawl endpoint 官方文件](https://developers.cloudflare.com/browser-rendering/rest-api/crawl-endpoint/)
- [Browser Rendering 限制](https://developers.cloudflare.com/browser-rendering/limits/)
- [Browser Rendering 定價](https://developers.cloudflare.com/browser-rendering/platform/pricing/)

---

<p align="center">
  <sub>Powered by <a href="https://developers.cloudflare.com/browser-rendering/">Cloudflare Browser Rendering</a>.</sub><br/>
  <sub>如果這省了你寫 scraper 的時間 — 考慮給顆 ⭐</sub>
</p>
