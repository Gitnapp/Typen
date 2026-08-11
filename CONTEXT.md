# Typen

Typen is a byte-faithful Markdown editor for macOS. Its domain model centers on how editing sessions map to windows, and which state is shared across the whole app versus scoped to a single window.

## Language

**Window**:
An NSWindow in the running app, hosting exactly one Document. Multiple Windows may be open at once; each is independently closable and carries its own unsaved-changes prompt.
_Avoid_: Instance, view

**Document**:
The per-Window editable session: the plain-text buffer, its dirty flag, undo history, cursor/scroll position, and find/replace state. Never shared between Windows — two Windows never point at the same live Document.
_Avoid_: Buffer (Buffer is just the text content; Document is the whole per-Window session around it), Tab, File (a Document may have no backing File yet — Untitled)

**Workspace state**:
App-wide state that is conceptually one shared source of truth across all open Windows: Settings (theme, font size, column width) and the Recents list. Never tied to a single Document.
_Avoid_: Global state, Preferences

**New Buffer**:
The existing ⌘N action — replaces the current Window's Document with a blank Untitled one (after the usual unsaved-changes prompt if needed). Stays within the same Window; no new Window is created.
_Avoid_: New File, New Document (ambiguous with New Window)

**New Window**:
Opens an additional Window with its own blank Untitled Document, leaving every existing Window untouched.
_Avoid_: New tab, New instance

**Empty Window**:
A Window whose Document is still the default blank Untitled one and has never been edited. Opening a file (via ⌘O, Finder, or Recents) reuses an Empty Window instead of spawning a new one; New Window always creates a fresh Window regardless of whether an Empty Window exists.
_Avoid_: Blank window, untouched window
