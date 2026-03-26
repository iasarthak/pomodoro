# Idle Reminder — Design Spec

**Date:** 2026-03-26
**Status:** Approved

## Problem

We forget to use the Pomodoro timer. It sits in the menu bar doing nothing because there's no nudge to actually start a session. The app should remind us when we've been idle too long.

## Requirements

- Show a fullscreen overlay reminder if no Pomodoro session has been active for 30 minutes (configurable, 10–120 min range)
- Always on — fires whenever the app is running and no session is active. Quit the app to stop reminders.
- Auto-repeats: dismissing without starting resets the idle clock, and another reminder fires after the same interval
- Overlay has a "Start Focus" button that dismisses AND starts a work session
- Clicking anywhere else dismisses without starting (idle clock resets)
- Configurable in settings: toggle on/off + duration slider
- **Parked for future:** Meeting app detection (suppress reminder when Zoom/Meet/Teams call is active)

## Architecture

### Approach: Separate IdleMonitor class

An `IdleMonitor` class alongside `PomodoroTimer` — clean separation of concerns. The idle monitor observes the timer's state and fires a callback when idle too long. It doesn't touch timer logic, and the timer doesn't know about idle monitoring.

### New file: `Sources/PomodoroCore/IdleMonitor.swift`

`@MainActor` observable class with:

- **`lastActiveDate: Date`** — updated when `timer.isRunning` becomes `true` or a session completes
- **Background `Timer`** — checks every 60 seconds: `now() - lastActiveDate > threshold`
- **`onIdleReminder: (() -> Void)?`** — callback when threshold exceeded
- **`resetIdleClock()`** — public method called after overlay dismissal, sets `lastActiveDate = now()`
- **`now: () -> Date`** — injectable clock for testing (same pattern as `PomodoroTimer`)
- **`init(testMode:)`** — skips background timer for unit tests
- Observes `PomodoroTimer` via Combine (`objectWillChange` sink) — checks `isRunning` on each change to update `lastActiveDate`
- When `settings.idleReminderEnabled == false`, the check timer still runs but the callback never fires (avoids start/stop lifecycle complexity)

### Changes to `PomodoroSettings.swift`

Two new `@AppStorage` properties:

```swift
@AppStorage("idleReminderEnabled") public var idleReminderEnabled = true
@AppStorage("idleReminderMinutes") public var idleReminderMinutes = 30
```

### Changes to `PomodoroApp.swift`

**1. New `IdleReminderOverlayView`**

Same structure as `CompletionOverlayView`:
- Dark translucent background (`Color.black.opacity(0.75)`)
- Icon: `cup.and.saucer.fill` using `TimerMode.work.accentColor` (matches the work/focus theme)
- Title: "Time to focus?"
- Subtitle: "You haven't started a session in a while."
- **"Start Focus" button** — prominent, accent-colored. Dismisses overlay + starts work session.
- "click anywhere to dismiss" text at bottom — dismisses without starting

Two dismiss paths:
- Button click → `onStart()` (starts timer)
- Background tap → `onDismiss()` (just resets idle clock)

**2. Generalize `OverlayManager`**

Current `show(mode:onDismiss:)` is hardcoded to `CompletionOverlayView`. Add a generic method or a second method:

```swift
func showIdleReminder(onStart: @escaping () -> Void, onDismiss: @escaping () -> Void)
```

Uses the same NSPanel creation logic (fullscreen, above all windows, all spaces, fade in animation).

**3. Wire in `PomodoroApp.init()`**

```swift
let idle = IdleMonitor(timer: t, settings: s)
idle.onIdleReminder = {
    overlay.showIdleReminder(
        onStart: { t.start() },
        onDismiss: { idle.resetIdleClock() }
    )
}
```

IdleMonitor automatically resets its clock when `timer.isRunning` becomes true (via Combine observation), so the "Start Focus" path doesn't need an explicit `resetIdleClock()`.

**4. Settings UI additions**

After the sound picker section in `SettingsPanel`, add a new divider + section:

- Toggle: "Idle reminder" (bound to `settings.idleReminderEnabled`)
- Duration row (same +/- stepper pattern): "Remind after" — range 10–120, step 5, default 30m
- Duration row only visible when toggle is on (animated)

### New file: `Tests/PomodoroTests/IdleMonitorTests.swift`

Test cases using injectable `now()`:

1. **Fires after threshold** — advance clock 31 min past lastActiveDate, trigger check, verify callback
2. **Doesn't fire when timer is running** — start timer, advance clock, verify no callback
3. **Doesn't fire when disabled** — set `idleReminderEnabled = false`, advance clock, verify no callback
4. **Resets after dismissal** — fire once, call `resetIdleClock()`, verify needs another full interval
5. **Respects custom duration** — set to 60 min, advance 30 min, verify no callback; advance to 61 min, verify fires

## Files Summary

| File | Change |
|------|--------|
| `Sources/PomodoroCore/IdleMonitor.swift` | **New** — idle detection logic |
| `Sources/PomodoroCore/PomodoroSettings.swift` | Add 2 `@AppStorage` properties |
| `Sources/Pomodoro/PomodoroApp.swift` | Wire IdleMonitor, add IdleReminderOverlayView, generalize OverlayManager, add settings UI |
| `Tests/PomodoroTests/IdleMonitorTests.swift` | **New** — 5 test cases |
| `Package.swift` | No changes |

## Future Enhancements (Parked)

- **Meeting app detection** — check if Zoom, Google Meet (Chrome), Teams processes have active calls. Suppress reminder during meetings. This is the ideal approach but needs research into reliable detection methods.
- **System idle detection** — `NSEvent.addGlobalMonitorForEvents` to detect AFK. Don't remind if user walked away from computer. Requires accessibility permissions.

## Verification

1. Build: `bash build.sh` — must compile and pass all tests (existing + new)
2. Manual test: launch app, don't start a session, wait 30 min (or temporarily set threshold to 1 min for testing) — overlay should appear
3. Dismiss by clicking background — overlay should reappear after another interval
4. Click "Start Focus" — overlay dismisses, work timer starts, no more reminders while running
5. Toggle off in settings — no reminders fire
6. Change duration in settings — next reminder uses new duration
