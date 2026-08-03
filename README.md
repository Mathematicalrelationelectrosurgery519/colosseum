# Colosseum

A local, Are.na-inspired macOS app for curating design references.

Boards hold images, videos, links, text notes, nested boards, and Are.na channel previews — all stored on your machine.

![Colosseum](Resources/colosseum-icon-1024.png)

## Features

- **Boards** — collections you can nest and connect
- **Blocks** — image, video, link, text, and Are.na channel cards
- **Connections** — the same block can live in many boards (`Connect →`)
- **Import** — drag & drop files, paste (`⌘V`), open files (`⌘O`), or paste any URL
- **Menu bar capture** — click the menu bar icon to paste a URL/media (including Are.na channels), preview, pick a board, optionally add notes, and save
- **Are.na browse** — open a public channel in-app (streamed thumbs/previews; nothing downloaded until you save)
- **Are.na import** — optionally download a whole channel into a local board
- **Are.na cards** — connect a channel URL as a card; click to browse in Colosseum
- **Overview + block view** — dense grid for browsing; full preview with metadata sidebar for focus
- **Tags** — write `#tags` in notes; filter the board with pills (And / Or). Tags render in light purple and are tappable.
- **Local-only** — SwiftData + media files under `~/Library/Application Support/Colosseum/`

## Requirements

- macOS 14+
- Swift 5.9+ / Xcode Command Line Tools

## Install

```bash
./Scripts/package-app.sh
```

This builds a Release binary, assembles `Colosseum.app`, and copies it to `/Applications`.

Or open from the built bundle:

```bash
open dist/Colosseum.app
```

## Development

```bash
swift build
swift run
```

## Shortcuts

| Shortcut | Action |
|---|---|
| `⌘N` | New board |
| `⌘↩` | Add to current board |
| `⌘V` | Paste into current board |
| `⌘O` | Open files |
| `⌘W` / `Esc` | Close block view |
| `←` `→` | Previous / next block |
| Menu bar icon | Quick capture → preview → choose board → add |

## Storage

| Path | Contents |
|---|---|
| `~/Library/Application Support/Colosseum/Colosseum.store` | SwiftData database |
| `~/Library/Application Support/Colosseum/Media/` | Copied images & videos |

## License

MIT
