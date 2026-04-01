---
name: agent-reach
description: >
  Give your AI agent eyes to see the entire internet.
  Search and read 15+ platforms: Twitter/X, Reddit, YouTube, GitHub, Bilibili,
  XiaoHongShu, Douyin, Weibo, WeChat Articles, Xiaoyuzhou Podcast, LinkedIn,
  V2EX, RSS, Exa web search, and any web page.
  Use when user asks to search, read, or interact on any supported platform,
  shares a URL from a supported site, or asks to search the web.
  Triggers: "search twitter", "youtube transcript", "search reddit", "read this link",
  "bilibili", "web search", "research this", "search weibo", "wechat article",
  "xiaohongshu", "douyin", "podcast transcript", "V2EX", "RSS feed".
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Agent Reach

Search and read 15+ internet platforms from the CLI. Zero API fees for most channels.

**Upstream**: [Panniantong/Agent-Reach](https://github.com/Panniantong/Agent-Reach)

## Preflight (Auto-Update)

**Run this before every use.** It ensures Agent Reach is installed and up-to-date.

```bash
#!/usr/bin/env bash
set -euo pipefail

PASS=true

# 1. Check if agent-reach CLI exists
if ! command -v agent-reach &>/dev/null; then
    echo "  MISSING  agent-reach CLI"
    echo "  Installing via pipx..."
    if command -v pipx &>/dev/null; then
        pipx install https://github.com/Panniantong/agent-reach/archive/main.zip --python python3.13 2>&1
        agent-reach install --env=auto 2>&1
        echo "  OK  agent-reach installed"
    else
        echo "  FAIL  pipx not found. Install: brew install pipx"
        PASS=false
    fi
else
    INSTALLED=$(agent-reach --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "0.0.0")
    echo "  OK  agent-reach v${INSTALLED}"

    # 2. Check for updates (non-blocking: 5s timeout, failures are non-fatal)
    LATEST=$(curl -sf --max-time 5 https://api.github.com/repos/Panniantong/Agent-Reach/releases/latest 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','').lstrip('v'))" 2>/dev/null || echo "")

    if [[ -n "$LATEST" && "$LATEST" != "$INSTALLED" ]]; then
        echo "  UPDATE  v${INSTALLED} → v${LATEST}"
        echo "  Upgrading..."
        pipx upgrade agent-reach 2>&1 | tail -1
        # Re-run install to update tools and SKILL.md
        agent-reach install --env=auto 2>&1 | grep -E '^\s*(✅|--|✗|\[)' | head -20
        echo "  OK  Updated to v${LATEST}"
    fi
fi

# 3. Quick health check (which channels are active?)
if command -v agent-reach &>/dev/null; then
    DOCTOR_OUTPUT=$(agent-reach doctor 2>&1)
    ACTIVE=$(echo "$DOCTOR_OUTPUT" | grep -c '✅' || true)
    TOTAL=$(echo "$DOCTOR_OUTPUT" | grep -cE '(✅|--)' || true)
    echo "  OK  ${ACTIVE}/${TOTAL} channels active"
fi

if ! $PASS; then
    echo "FAIL: Agent Reach not available."
    exit 1
fi
echo "Preflight passed."
```

If the version check fails (no network, GitHub rate-limited), it silently continues with the installed version. Updates are best-effort, never blocking.

## Platform Commands

Run `agent-reach doctor` to see which channels are active on your machine.

### Web — Any URL

```bash
curl -s "https://r.jina.ai/URL"
```

### Web Search (Exa)

```bash
mcporter call 'exa.web_search_exa(query: "query", numResults: 5)'
mcporter call 'exa.get_code_context_exa(query: "code question", tokensNum: 3000)'
```

### Twitter/X (xreach)

```bash
xreach search "query" -n 10 --json          # search
xreach tweet URL_OR_ID --json                # read tweet
xreach tweets @username -n 20 --json         # user timeline
xreach thread URL_OR_ID --json               # full thread
```

### YouTube (yt-dlp)

```bash
yt-dlp --dump-json "URL"                     # video metadata
yt-dlp --write-sub --write-auto-sub --sub-lang "zh-Hans,zh,en" --skip-download -o "/tmp/%(id)s" "URL"
                                             # download subtitles
yt-dlp --dump-json "ytsearch5:query"         # search
```

### Bilibili (yt-dlp)

```bash
yt-dlp --dump-json "https://www.bilibili.com/video/BVxxx"
yt-dlp --write-sub --write-auto-sub --sub-lang "zh-Hans,zh,en" --convert-subs vtt --skip-download -o "/tmp/%(id)s" "URL"
```

> Server IPs may get 412. Use `--cookies-from-browser chrome` or configure proxy.

### Reddit

```bash
curl -s "https://www.reddit.com/r/SUBREDDIT/hot.json?limit=10" -H "User-Agent: agent-reach/1.0"
curl -s "https://www.reddit.com/search.json?q=QUERY&limit=10" -H "User-Agent: agent-reach/1.0"
```

> Server IPs may get 403. Search via Exa instead, or configure proxy.

### GitHub (gh CLI)

```bash
gh search repos "query" --sort stars --limit 10
gh repo view owner/repo
gh search code "query" --language python
gh issue list -R owner/repo --state open
```

### XiaoHongShu (mcporter)

```bash
mcporter call 'xiaohongshu.search_feeds(keyword: "query")'
mcporter call 'xiaohongshu.get_feed_detail(feed_id: "xxx", xsec_token: "yyy")'
```

> Requires Docker + cookies. See [setup reference](./references/setup-channels.md).

### Douyin (mcporter)

```bash
mcporter call 'douyin.parse_douyin_video_info(share_link: "https://v.douyin.com/xxx/")'
mcporter call 'douyin.get_douyin_download_link(share_link: "https://v.douyin.com/xxx/")'
```

### WeChat Articles

**Search** (miku_ai):

```bash
python3 -c "
import asyncio
from miku_ai import get_wexin_article
async def s():
    for a in await get_wexin_article('query', 5):
        print(f'{a[\"title\"]} | {a[\"url\"]}')
asyncio.run(s())
"
```

**Read** (Camoufox — bypasses WeChat anti-bot):

```bash
cd ~/.agent-reach/tools/wechat-article-for-ai && python3 main.py "https://mp.weixin.qq.com/s/ARTICLE_ID"
```

> WeChat articles cannot be read with Jina Reader or curl. Must use Camoufox.

### Xiaoyuzhou Podcast

```bash
~/.agent-reach/tools/xiaoyuzhou/transcribe.sh "https://www.xiaoyuzhoufm.com/episode/EPISODE_ID"
```

> Requires ffmpeg + Groq API Key (free). Configure: `agent-reach configure groq-key YOUR_KEY`

### LinkedIn (mcporter)

```bash
mcporter call 'linkedin.get_person_profile(linkedin_url: "https://linkedin.com/in/username")'
mcporter call 'linkedin.search_people(keyword: "AI engineer", limit: 10)'
```

Fallback: `curl -s "https://r.jina.ai/https://linkedin.com/in/username"`

### V2EX (public API)

```bash
curl -s "https://www.v2ex.com/api/topics/hot.json" -H "User-Agent: agent-reach/1.0"
curl -s "https://www.v2ex.com/api/topics/show.json?node_name=python&page=1" -H "User-Agent: agent-reach/1.0"
```

### RSS

```bash
python3 -c "
import feedparser
for e in feedparser.parse('FEED_URL').entries[:5]:
    print(f'{e.title} — {e.link}')
"
```

## Configuration

```bash
agent-reach configure proxy http://user:pass@ip:port     # Reddit/Bilibili proxy
agent-reach configure twitter-cookies "auth_token=xxx; ct0=yyy"
agent-reach configure groq-key gsk_xxxxx                 # Xiaoyuzhou podcasts
agent-reach configure xhs-cookies "key1=val1; key2=val2" # XiaoHongShu
agent-reach configure --from-browser chrome              # Auto-extract all cookies
```

## Troubleshooting

- **Channel not working?** Run `agent-reach doctor`
- **Update manually:** `pipx upgrade agent-reach && agent-reach install --env=auto`
- **Full reinstall:** `pipx reinstall agent-reach && agent-reach install --env=auto`

## Workspace Rules

**Never create files in the agent workspace.** Use `/tmp/` for temporary output and `~/.agent-reach/` for persistent data.


## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If the underlying tool's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
