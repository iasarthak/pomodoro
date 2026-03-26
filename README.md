# Pomodoro

A minimal pomodoro timer for macOS. Lives in your menu bar, stays out of your way.

![SwiftUI](https://img.shields.io/badge/SwiftUI-blue) ![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Menu bar app** — no dock icon, always one click away
- **50/10 focus cycles** — configurable work, break, and long break durations
- **Circular progress ring** — visual countdown with smooth animation
- **Fullscreen completion overlay** — appears above everything (including fullscreen apps) when a session ends
- **Idle reminder** — fullscreen nudge if you haven't started a session in a while (default: 30 min, configurable). "Start Focus" button or click to dismiss. Auto-repeats.
- **Long breaks** — automatic long break every N sessions (default: 4)
- **Auto-start** — optionally auto-start breaks or focus sessions
- **Sound picker** — choose from 8 macOS system sounds
- **Native notifications** — macOS notification center alerts
- **Settings persist** — durations, sounds, and preferences survive restarts

## Install

Requires macOS 13+ and Swift 5.9+ (Command Line Tools).

```bash
git clone https://github.com/iasarthak/pomodoro.git
cd pomodoro
bash build.sh
```

This builds, runs tests, bundles a `.app`, and installs to `/Applications`. Search "Pomodoro" in Spotlight to launch.

## Usage

Click the timer icon in your menu bar to open the popover:

- **Play/Pause** — start or pause the current session
- **Reset** — reset the timer to full duration
- **Skip** — jump to the next session (work → break or break → work)
- **Gear icon** — open settings

The menu bar shows remaining time while the timer is running.

## Architecture

```
Sources/
  PomodoroCore/     ← library (timer logic, settings, idle monitor, mode)
  Pomodoro/         ← executable (app, views, overlays)
Tests/
  PomodoroTests/    ← 35 unit tests
```

Timer logic is extracted into `PomodoroCore` for testability. The timer uses date-based math (not decrementing counters) so it stays accurate through sleep/wake cycles.

## Tests

```bash
swift run PomodoroTests
```

35 tests covering state transitions, mode advancement, computed properties, completion callbacks, idle monitor, and edge cases.

## Rebuild after changes

```bash
bash build.sh
```

Runs tests → builds release → bundles `.app` → kills running instance → installs to `/Applications` → launches.

## License

MIT
