# Typen

> A byte-faithful Markdown editor for macOS — open source, hackable, and structurally incapable of rewriting parts of your file you didn't touch.

![status](https://img.shields.io/badge/status-beta-yellow) ![platform](https://img.shields.io/badge/platform-macOS-lightgrey) ![flutter](https://img.shields.io/badge/flutter-3.44-blue)

## Why

Typora is closed-source and paid. I wanted something I could read the source of, tweak the typography of, and use without licensing concerns.

Typen's one non-negotiable property is **fidelity**: the bytes you open are the bytes you save, except for the characters you actually typed. Not "usually". Not "for common Markdown". Byte-for-byte, asserted by tests on every commit.

That sounds obvious for a text editor. It isn't — see [Fidelity](#fidelity) below.

## What it is

- **The buffer is plain Markdown text.** There is no rich document model between you and the file, so there is nothing that can normalise, reorder, or drop a construct it doesn't understand. Raw HTML, YAML front matter, footnotes, reference links, `~~~` fences, hard line breaks, escapes, table alignment — all survive because nothing ever parsed them in the first place.
- **Live syntax highlighting in the source view.** Headings scale up, emphasis renders, code blocks tint, links colour — while the text stays exactly the text.
- **A read-only preview** (`⌘/`) for when you want to see it rendered. It renders; it never writes.
- **Encoding is preserved**: CRLF stays CRLF, a BOM stays a BOM, a file that isn't valid UTF-8 round-trips through Latin-1 instead of failing to open. UTF-16 files are refused rather than silently mangled.
- **Saves are atomic.** A crash mid-write leaves the old file, never a truncated one.
- **It won't let you lose work**: ⌘Q and ⌘W prompt on unsaved changes, and a file edited by another program is detected instead of overwritten.

## Fidelity

The v0.1 WYSIWYG editor round-tripped your document through a rich-text model on every keystroke and wrote the result to disk. Feeding it a normal README:

```
376 bytes in  →  300 bytes out
```

Fenced code blocks were **deleted**. So were indented code blocks and raw HTML. Paragraph breaks collapsed. `\*escaped\*` became real emphasis. Front matter turned into a heading. Of 28 common Markdown constructs, 4 survived byte-identical.

That model is gone. `test/document_codec_test.dart` now asserts byte-exact round-trips over that whole corpus, and `test/highlighter_test.dart` asserts the highlighter's painted output equals the buffer character-for-character. CI fails if either regresses.

## Keyboard

| Shortcut | Action |
|---|---|
| `⌘N` / `⌘O` | New / Open |
| `⌘S` / `⇧⌘S` | Save / Save As |
| `⌘/` | Toggle source ↔ preview |
| `⌘F` / `⌥⌘F` | Find / Find & Replace |
| `⌘G` / `⇧⌘G` | Find next / previous |
| `⌘Z` `⇧⌘Z` `⌘X` `⌘C` `⌘V` `⌘A` | Standard editing |
| `⌘,` | Preferences |
| `⌃⌘F` | Full screen |

## Structure

```
lib/
├── main.dart                        # Editor window shell, save flow, menus, native handlers
├── document_file.dart               # Byte-faithful read/write (BOM, EOL, encoding, atomic)
├── native.dart                      # Per-window platform channel (Editor + Preferences)
├── store.dart                       # Recents (+ sandbox bookmarks), cursor memory, settings
├── find.dart                        # Find & replace engine (pure logic)
├── update_checker.dart              # GitHub latest-release check
├── updater.dart                     # One-click update: download/extract/verify/install
├── theme.dart                       # Light + dark palettes as a ThemeExtension
└── widgets/
    ├── editor_pane.dart             # Source editor ↔ read-only preview
    ├── markdown_highlighter.dart    # Markdown highlighting over plain text
    ├── find_bar.dart
    ├── preferences_window.dart      # Preferences window shell (sidebar + card pages)
    ├── settings_controls.dart       # Shared segmented/slider controls
    ├── dialog_shell.dart            # Shared confirm/action dialog chrome
    └── update_dialog.dart

macos/Runner/
├── AppDelegate.swift                # Window registry, quit guard, bookmarks, atomic write
├── EditorWindow.swift               # One Window, one Document, one Flutter engine
└── PreferencesWindow.swift          # Singleton settings window, its own Flutter engine
```

## Development

```bash
git clone https://github.com/Gitnapp/Typen.git
cd Typen

# China mirror (skip if you have direct pub.dev access)
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

flutter pub get
flutter test
flutter run -d macos
```

## Release

```bash
./scripts/notarize.sh
```

Builds, signs with a Developer ID Application identity, and notarizes —
see [docs/notarization.md](docs/notarization.md) for one-time machine setup
and how it works.

## Not there yet

- **Single window.** `⌘N` starts a new buffer in the same window rather than opening a second one. Real multi-window needs Flutter's multi-view support.
- **No DMG.** Notarized `.app` only for now. Updates are in-app (检查更新…), but the final install step still needs one folder-picker click — App Sandbox has no "write anywhere" entitlement.
- **No image paste-to-assets, math, or export.** Preview renders local relative-path images; it does not yet help you create them.
- Mixed CRLF/LF files are the one documented exception to byte fidelity — saving normalises them to the dominant ending, and the title bar says so.

## License

MIT
