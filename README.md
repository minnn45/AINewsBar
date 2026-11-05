# AI News — a menu bar app for the latest AI news

A small macOS menu bar app that shows the latest AI news in a clean white frame with pastel accents. Stories are boiled down to 2–3 key points, filtered for ads, and grouped so you can catch up in a minute — in English or Korean.

## Features

- **Key points, not paragraphs** — every headline comes with 2–3 bullet points
- **Daily briefing** — a short "what happened today" card at the top of Today, with an optional morning notification
- **★ Big news** — major stories (new frontier models, big launches, acquisitions) pinned at the top, with official lab posts preferred
- **Official + press sources** — OpenAI, Google DeepMind, Google AI, plus TechCrunch, The Verge, MIT Technology Review, Ars Technica and WIRED
- **No ads** — sponsored posts, deals, event promos, webinars and vendor case studies are filtered out
- **English ↔ 한국어** — one tap switches everything to Korean: headlines, key points, the briefing, and the full article
- **Built-in reader** — in Korean mode, stories open inside the panel with the article body translated and laid out for easy reading
- **Search** — across titles, key points and excerpts, in both English and Korean (⌘F)
- **Bookmarks** — save stories to the Saved tab; saved stories are kept even after the 30-day archive window
- **Keyboard navigation** — move, open, save and switch tabs without the mouse (works with the Korean input source too)
- **Today / Past / Saved** — older stories are kept for 30 days and grouped by day, then by topic (Models, Research, Business, Policy, Products)
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

To update later: `git pull && ./build.sh`, then quit and reopen the app.

## Korean (한국어)

Tap **한** in the header. Translation uses Apple's on-device Translation framework — free and private.

The first time, the app asks you to download the Korean language pack (a banner appears at the top of the panel). You can also install it from **System Settings → General → Language & Region → Translation Languages**. Until the pack is installed, text stays in English.

In Korean mode, opening a story shows it in the built-in reader, translated. **원문 보기** opens the original page in your browser.

## Keyboard shortcuts

| Key | Action |
|---|---|
| `↑` `↓` / `j` `k` | Move between stories |
| `↵` / `Space` | Open (Korean mode: read in the app) |
| `B` | Save / unsave |
| `O` | Open the original in your browser |
| `←` `→` | In the reader: previous / next story |
| `⌘F` / `/` | Search (`↓` jumps from the field to the results) |
| `⌘1` `⌘2` `⌘3` | Today · Past · Saved |
| `R` | Refresh |
| `Esc` | Back / close search |

## Optional: Claude summaries

Everything works without an API key: key points are taken from each story's feed text, and the briefing is a simple digest of the top stories.

For better results, open the panel → gear icon → paste an [Anthropic API key](https://console.anthropic.com/). The key is stored in your macOS Keychain, never in files. With a key, Claude:

- reads the **full article body** (not just the feed excerpt) and writes 2–3 neutral key points
- assigns the topic, flags promotional posts, and helps pick Big news
- writes the **daily briefing** — the day's main threads, in English and Korean

Each story is summarized only once, so API usage stays small.

## Your data

Bookmarks, the archive and the briefing are stored locally in `~/Library/Application Support/AINewsBar/`. The app only sends data out in two cases: article text goes to Claude if you add an API key, and the reader's web-translation button opens the article link in Google Translate.

## Customize sources

Edit `FeedSource.all` in `Sources/AINewsBar/Models.swift` (any RSS or Atom feed works), then run `./build.sh` again.

## Project layout

| File | Purpose |
|---|---|
| `App.swift` | Menu bar UI, story rows, the reader, settings (SwiftUI) |
| `ExtraViews.swift` | Search results, Saved list, daily briefing card, shortcuts table |
| `KeyboardController.swift` | Panel state, keyboard shortcuts, the search field |
| `NewsStore.swift` | Fetching, archive, Big news ranking, search, bookmarks, briefing, translation |
| `ArticleExtractor.swift` | Pulls readable body text out of article pages |
| `FeedParser.swift` | RSS / Atom parsing |
| `Summarizer.swift` | Ad filtering, categorization, key points, Claude summaries and briefing |
| `Notifier.swift` | Big news and briefing notifications |
| `Keychain.swift` | API key storage |

## License

MIT — see [LICENSE](LICENSE).
