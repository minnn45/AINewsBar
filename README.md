# AI News — a menu bar app for the latest AI news

A small macOS menu bar app that shows the latest AI news in a clean, white‑pastel panel. Stories are summarized, filtered for ads, and grouped so you can catch up in a minute.

## Features

- **★ Big news** — major stories (new frontier models, big launches, acquisitions) pinned at the top, with official lab posts preferred
- **Official + press sources** — OpenAI, Google DeepMind, Google AI, plus TechCrunch, The Verge, MIT Technology Review, Ars Technica and WIRED
- **No ads** — sponsored posts, deals, event promos, webinars and vendor case studies are filtered out
- **Clear summaries** — the first lines from each story, or optional AI-written 1–2 sentence summaries with Claude
- **English ↔ 한국어** — one-tap translation of headlines and summaries using Apple's on-device Translation (free, private)
- **Today / Past days** — older stories are kept for 30 days and grouped by day, then by topic (Models, Research, Business, Policy, Products)
- **Notifications** — a macOS notification when a new Big news story appears
- **Always fresh** — refreshes every 30 minutes, at midnight, and when your Mac wakes; launches at login

## Requirements

- macOS 15 (Sequoia) or later
- Xcode or the Command Line Tools (`xcode-select --install`) — Xcode itself is not required

## Install

```sh
git clone https://github.com/minnn45/AINewsBar.git
cd AINewsBar
./build.sh
open ~/Applications/AINewsBar.app
```

`build.sh` compiles the app, signs it locally, and installs it to `~/Applications/AINewsBar.app`. Look for the ✦ icon in your menu bar.

## Optional: AI summaries

Open the panel → gear icon → paste an [Anthropic API key](https://console.anthropic.com/). The key is stored in your macOS Keychain, never in files. With a key, Claude writes a short neutral summary of each new story, assigns its topic, flags promotional posts, and helps pick Big news. Each story is summarized only once.

## Korean translation

Tap **한** in the header. The first time, macOS asks to download the Korean language pack; after that translation runs fully on-device.

## Customize sources

Edit `FeedSource.all` in `Sources/AINewsBar/Models.swift` (any RSS or Atom feed works), then run `./build.sh` again.

## Project layout

| File | Purpose |
|---|---|
| `App.swift` | Menu bar UI (SwiftUI) |
| `NewsStore.swift` | Fetching, archive, Big news ranking, translation |
| `FeedParser.swift` | RSS / Atom parsing |
| `Summarizer.swift` | Ad filtering, categorization, Claude summaries |
| `Notifier.swift` | Big news notifications |
| `Keychain.swift` | API key storage |

## License

MIT — see [LICENSE](LICENSE).
