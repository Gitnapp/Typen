# Typen

> A proper Markdown editor for macOS — open-source [Typora](https://typora.io) alternative built in Flutter.

Single-file Markdown editing with a WYSIWYG ↔ source toggle, system-native menu bar (with Open Recent), and tight typography modeled after Typora / iA Writer / GitHub-Markdown. Dark theme by default.

![status](https://img.shields.io/badge/status-alpha-orange) ![platform](https://img.shields.io/badge/platform-macOS-lightgrey) ![flutter](https://img.shields.io/badge/flutter-3.41-blue)

## Why

Typora is closed-source and paid. I wanted something I could read the source of, tweak the typography of, and use without licensing concerns. Typen aims to nail the **single-document, no-distractions, WYSIWYG-or-source** writing experience that Typora got right, while being open and hackable.

## Features

- **WYSIWYG ↔ source toggle** — appflowy_editor renders rich markdown live; one keypress (`⌘/`) swaps to raw markdown text. Round-trip is lossless within markdown's grammar.
- **System menu bar** — native macOS menus: `File → Open / Open Recent / Save`, `View → Mode / Full Screen`. The recents list lives in the menu bar, not a sidebar.
- **No sidebar, no welcome page** — launches straight into an `Untitled` buffer or the last file. Distraction-free by default.
- **Explicit save** — no auto-save. `⌘S` to save, save dialog for new files. Switching docs with unsaved changes prompts `Save / Discard / Cancel`.
- **Typography that doesn't fight you** — researched defaults from Typora / iA Writer / Bear / Obsidian / github-markdown-css. 16px body, 760px reading column, proper heading hierarchy. Cursor aligned with glyph.
- **Dark warm palette** — gold / coral / emerald accents on a 4-layer surface ramp (the "Dusk" system).

## Keyboard

| Shortcut | Action |
|---|---|
| `⌘O` | Open a `.md` file |
| `⌘S` | Save (or Save As… if Untitled) |
| `⌘/` | Toggle WYSIWYG / source mode |
| `⌃⌘F` | Toggle full screen |

## Status

Alpha. macOS-only for now. Works for daily writing but expect rough edges.

Known limitations:
- `appflowy_editor` doesn't expose `cursorHeight`, so achieving cursor / glyph / line-box alignment forces `line-height: 1.0` (single-paragraph multi-line wrapping has no inter-line spacing). Inter-paragraph rhythm is handled via block padding instead.
- WYSIWYG ↔ source round-trip is lossy for some corner cases (YAML front matter, complex tables, raw HTML blocks).

## Development

```bash
git clone https://github.com/Gitnapp/Typen.git
cd Typen

# China mirror (skip if you have direct pub.dev access)
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

flutter pub get
flutter run -d macos
```

## Structure

```
lib/
├── main.dart            # App shell, file I/O, save flow, platform menu bar
├── theme.dart           # Inlined "Dusk" color tokens (gold / coral / emerald)
├── recents.dart         # SharedPreferences-backed recent files list
└── widgets/
    └── editor_pane.dart # appflowy_editor (WYSIWYG) ↔ TextField (source)
```

## Roadmap

- [ ] Custom `AppFlowyRichText` fork or wrapper that lets us pass explicit `cursorHeight` — would unlock comfortable line-height + perfect cursor alignment simultaneously
- [ ] `.md` file association (double-click to open in Finder)
- [ ] Find & replace
- [ ] Export to PDF / HTML
- [ ] Linux + Windows builds

## License

MIT
