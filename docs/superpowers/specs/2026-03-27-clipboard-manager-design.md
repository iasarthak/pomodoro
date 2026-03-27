# ClipStash — Universal Clipboard Manager Design Spec

**Date:** 2026-03-27
**Status:** Approved
**Reference:** Maccy (github.com/p0deje/Maccy, 19K+ stars) studied for architectural patterns

## Problem

We copy things constantly — code snippets, URLs, IDs, messages — and lose them the moment we copy something else. Going back to find what got copied is a pain. We need a clipboard history that's always available and surfaces frequently-used items automatically.

## Requirements

- Monitor macOS clipboard and store last 50 items (text + images)
- Global keyboard shortcut (Cmd+Shift+V) opens a floating search panel
- Menu bar icon for quick browse access
- Smart "Frequent" bar — automatically surfaces top text items by copy count (no manual pinning)
- Paste directly into the active app on item selection
- Search/filter across clipboard history
- Persist history to disk across app restarts
- Separate app from Pomodoro, same repo (new SPM targets)
- Zero external dependencies (pure Swift + Apple frameworks)

## Architecture

### Clipboard Monitoring — `ClipboardMonitor`

Standard macOS pattern (same as Maccy, Raycast, etc.):
- Poll `NSPasteboard.general.changeCount` every 500ms via `Timer.scheduledTimer`
- When `changeCount` changes, capture the new content
- Capture source app via `NSWorkspace.shared.frontmostApplication?.localizedName`
- Fires `onNewClip` callback with the captured `ClipItem`

**Content capture priority:**
1. `.string` (NSPasteboard.PasteboardType) — store as `.text(String)`
2. `.png` / `.tiff` — store as `.image(Data)` (convert TIFF to PNG for storage)
3. Skip if only contains ignored types

**Ignored pasteboard types** (security, learned from Maccy):
- `.concealed` — password managers mark content with this
- `.transient` — system-marked ephemeral content
- Any type with `dyn.` prefix (dynamic UTIs we don't understand)

**Deduplication:**
- For text: if new content matches the most recent text item exactly, increment `copyCount` and update `lastCopied` instead of creating a new entry
- For images: no dedup (binary comparison is expensive and rarely useful)

### Data Model — `ClipItem`

```swift
struct ClipItem: Codable, Identifiable {
    let id: UUID
    var content: ClipContent       // .text(String) or .image(Data)
    var copyCount: Int             // text only, starts at 1
    var firstCopied: Date
    var lastCopied: Date
    var sourceApp: String?         // "Safari", "VS Code", etc.
}

enum ClipContent: Codable {
    case text(String)
    case image(Data)              // PNG data
}
```

### History Management — `ClipboardHistory`

- `items: [ClipItem]` — max 50, ordered by `lastCopied` descending
- When at capacity, evict the oldest non-frequent item
- **Frequent items** (computed): top 5–8 text items where `copyCount >= 3`, ordered by `copyCount` descending. These are protected from eviction.
- **Weekly decay**: on app launch, if 7+ days since last decay, halve all `copyCount` values (drop items below 1 from frequent status). Tracked via `lastDecayDate` in UserDefaults.

**Persistence:**
- Save to `~/Library/Application Support/ClipStash/history.json`
- Save on each new clip (debounced — save after 1s of no new clips to avoid thrashing)
- Load on app launch
- Images stored as base64-encoded PNG data in JSON. With 50 items max this stays manageable.

### UI — Floating Panel (`ClipboardPanel`)

Activated by Cmd+Shift+V. An `NSPanel` (not NSPopover) that appears centered on the active screen.

**Panel properties** (following Maccy's proven pattern):
```swift
styleMask: [.nonactivatingPanel, .fullSizeContentView]
level: .statusBar
collectionBehavior: [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
backgroundColor: .clear
```

**Dimensions:** ~420pt wide, ~500pt tall. Vibrancy background (`.ultraThinMaterial`).

**Dismissal:** Escape key, clicking outside (via `hidesOnDeactivate = false` + manual tracking), or selecting an item.

**Layout:**
```
┌──────────────────────────────────┐
│ 🔍 Search...                     │  ← auto-focused, filters everything
├──────────────────────────────────┤
│ FREQUENT                         │  ← only if qualifying items exist
│ [sarthak@in...] [localhost:3...]│  ← horizontal chips, scroll if overflow
├──────────────────────────────────┤
│ RECENT                           │
│ ┌──────────────────────────┬───┐ │
│ │ Some code snippet I co...│ 3s│ │  ← text preview + relative time
│ ├──────────────────────────┼───┤ │
│ │ https://github.com/ias...│ 2m│ │
│ ├──────────────────────────┼───┤ │
│ │ [🖼 image thumbnail]     │ 5m│ │  ← image shows small preview
│ ├──────────────────────────┼───┤ │
│ │ Another text item here...│12m│ │
│ └──────────────────────────┴───┘ │
│                                  │
│               ⌘⇧V to toggle      │  ← subtle footer hint
└──────────────────────────────────┘
```

**Keyboard navigation:**
- Arrow up/down: move selection in recent list
- Enter: paste selected item
- Delete/Backspace: remove selected item from history
- Tab: cycle focus between frequent bar and recent list
- Type anything: filters search

**Search:** Filters both frequent and recent items. Matches against text content and source app name. Case-insensitive substring match.

### Menu Bar

A simple `MenuBarExtra` with a clipboard icon (`doc.on.clipboard`). Shows a condensed list of recent items (no search, no frequent bar). Clicking an item pastes it. Includes "Quit" at the bottom.

### Paste Mechanism

On item selection:
1. Dismiss the panel
2. Copy selected item to `NSPasteboard.general`
3. Small delay (~50ms) for the frontmost app to regain focus
4. Simulate Cmd+V via `CGEvent`:
```swift
let source = CGEventSource(stateID: .combinedSessionState)
let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)  // 'v'
keyDown?.flags = .maskCommand
let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
keyUp?.flags = .maskCommand
keyDown?.post(tap: .cghidEventTap)
keyUp?.post(tap: .cghidEventTap)
```
- Requires Accessibility permission — check `AXIsProcessTrusted()` on launch, prompt if not granted.

### Global Hotkey

Using `NSEvent.addGlobalMonitorForEvents` for Cmd+Shift+V (no external dependencies):
```swift
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
    if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 0x09 { // 'v'
        togglePanel()
    }
}
// Also add local monitor for when our app is focused
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 0x09 {
        togglePanel()
        return nil
    }
    return event
}
```

### Accessibility Permission

On first launch:
1. Check `AXIsProcessTrusted()`
2. If not granted, show a one-time overlay explaining why we need it ("ClipStash needs Accessibility access to paste items into your apps")
3. Open System Settings → Privacy → Accessibility via `AXIsProcessTrustedWithOptions` with prompt option
4. Poll `AXIsProcessTrusted()` every 2s until granted, then proceed

### SPM Structure

New targets in existing `Package.swift`:
```
Sources/
  ClipboardCore/              ← library (monitor, history, data model)
    ClipboardMonitor.swift    ← polls NSPasteboard, fires callbacks
    ClipboardHistory.swift    ← history management, persistence, frequency
    ClipItem.swift            ← data model + ClipContent enum
  ClipStash/                  ← executable (app entry, views, panel, hotkey)
    ClipStashApp.swift        ← app entry, menu bar, wiring
    ClipboardPanel.swift      ← NSPanel subclass, floating window
    PanelContentView.swift    ← search + frequent bar + recent list
    FrequentBar.swift         ← horizontal chip row
    ClipItemRow.swift         ← individual item in recent list
    PasteService.swift        ← CGEvent paste simulation
    AccessibilityCheck.swift  ← AXIsProcessTrusted prompting
Tests/
  ClipStashTests/             ← tests
    ClipboardHistoryTests.swift  ← history, dedup, eviction, frequency, decay
    ClipItemTests.swift          ← encoding/decoding, content types
```

### Build

New target in `build.sh` — or a separate `build-clipstash.sh`. Creates `ClipStash.app` bundle, installs to `/Applications`.

**App properties:**
- Bundle ID: `com.sarthak.clipstash`
- `LSUIElement = true` (menu bar only, no dock)
- Minimum macOS: 13.0

## Permissions Required

| Permission | Why | How |
|-----------|-----|-----|
| Accessibility | Paste simulation (CGEvent) + global hotkey | `AXIsProcessTrusted` prompt on first launch |

No calendar, no network, no entitlements file.

## Verification

1. Build: new build script compiles and passes all tests
2. Launch app — menu bar icon appears
3. Copy some text in any app → appears in ClipStash history
4. Copy an image (screenshot) → appears with thumbnail
5. Cmd+Shift+V → floating panel appears, search works
6. Select an item → pastes into the frontmost app
7. Copy same text 3+ times → appears in Frequent bar
8. Restart app → history persists
9. Delete an item from history → removed
10. 50-item cap: copy 51 items → oldest non-frequent item drops

## Future Enhancements (Parked)

- Configurable hotkey in settings
- Snippet templates (predefined text snippets, not from clipboard)
- Sync across devices via iCloud
- Rich text preservation (HTML/RTF)
- Exclude specific apps from monitoring
