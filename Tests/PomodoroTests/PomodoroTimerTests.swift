import Foundation
@testable import PomodoroCore

// Minimal test runner — no Xcode/XCTest required

struct AssertionError: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: Bool, _ message: String = "assertion failed", file: String = #file, line: Int = #line) throws {
    guard condition else { throw AssertionError(description: "\(message) (\(file):\(line))") }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard a == b else {
        throw AssertionError(description: "expected \(a) == \(b) \(message) (\(file):\(line))")
    }
}

func expectClose(_ a: Double, _ b: Double, accuracy: Double = 0.1, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard abs(a - b) < accuracy else {
        throw AssertionError(description: "expected \(a) ≈ \(b) (±\(accuracy)) \(message) (\(file):\(line))")
    }
}

// MARK: - Helpers

@MainActor
func makeTimer() -> PomodoroTimer {
    PomodoroTimer(testMode: true)
}

@MainActor
func makeTimerWithSettings(
    work: Int = 50, brk: Int = 10, longBrk: Int = 20,
    interval: Int = 4, autoBreaks: Bool = false, autoWork: Bool = false
) -> PomodoroTimer {
    let timer = PomodoroTimer(testMode: true)
    let settings = PomodoroSettings()
    settings.workMinutes = work
    settings.breakMinutes = brk
    settings.longBreakMinutes = longBrk
    settings.longBreakInterval = interval
    settings.autoStartBreaks = autoBreaks
    settings.autoStartWork = autoWork
    timer.settings = settings
    return timer
}

// MARK: - Run Tests

@MainActor
func runAllTests() -> Bool {
    var passed = 0
    var failed = 0
    var failures: [(String, String)] = []

    func test(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            passed += 1
            print("  \u{2705} \(name)")
        } catch {
            failed += 1
            failures.append((name, "\(error)"))
            print("  \u{274C} \(name): \(error)")
        }
    }

    print("\nPomodoro Timer Tests")
    print("=" * 50)

    // ── State Transitions ──

    print("\nState Transitions:")

    test("Initial state") {
        let timer = makeTimer()
        try expectEqual(timer.mode, .work)
        try expect(!timer.isRunning)
        try expect(!timer.hasStarted)
        try expectEqual(timer.sessionsCompleted, 0)
    }

    test("Start sets isRunning and hasStarted") {
        let timer = makeTimerWithSettings()
        timer.start()
        try expect(timer.isRunning)
        try expect(timer.hasStarted)
        try expect(timer.remaining <= timer.currentDuration)
    }

    test("Pause stops running but stays started") {
        let timer = makeTimerWithSettings()
        timer.start()
        timer.pause()
        try expect(!timer.isRunning)
        try expect(timer.hasStarted)
    }

    test("Resume after pause continues from paused time") {
        let timer = makeTimerWithSettings(work: 25)
        let refDate = Date()
        timer.now = { refDate }
        timer.start()

        timer.now = { refDate.addingTimeInterval(600) }
        timer.pause()
        let pausedRemaining = timer.remaining

        timer.now = { refDate.addingTimeInterval(1200) }
        try expectClose(timer.remaining, pausedRemaining)

        timer.start()
        try expect(timer.isRunning)
        try expectClose(timer.remaining, pausedRemaining, accuracy: 1.0)
    }

    test("Reset stops running and resets to full duration") {
        let timer = makeTimerWithSettings(work: 50)
        timer.start()
        timer.reset()
        try expect(!timer.isRunning)
        try expect(timer.hasStarted, "reset pauses at start, ready to play")
        try expectClose(timer.remaining, 50 * 60)
    }

    test("Reset while running stops and stays ready") {
        let timer = makeTimerWithSettings()
        timer.start()
        try expect(timer.isRunning)
        timer.reset()
        try expect(!timer.isRunning)
        try expect(timer.hasStarted, "stays ready to play after reset")
    }

    test("Reset while paused resets to full duration") {
        let timer = makeTimerWithSettings()
        timer.start()
        timer.pause()
        try expect(timer.hasStarted)
        timer.reset()
        try expect(timer.hasStarted, "stays ready after reset")
        try expect(!timer.isRunning)
        try expectClose(timer.remaining, timer.currentDuration)
    }

    test("Start without settings defaults to 50 min") {
        let timer = makeTimer()
        try expectEqual(timer.currentDuration, 50 * 60)
        try expectEqual(timer.displayTime, "50:00")
    }

    // ── Mode Advancement ──

    print("\nMode Advancement:")

    test("Skip from work → rest, sessions increment") {
        let timer = makeTimerWithSettings()
        try expectEqual(timer.mode, .work)
        timer.skip()
        try expectEqual(timer.mode, .rest)
        try expectEqual(timer.sessionsCompleted, 1)
    }

    test("Skip from rest → work, sessions unchanged") {
        let timer = makeTimerWithSettings()
        timer.skip()
        let sessions = timer.sessionsCompleted
        timer.skip()
        try expectEqual(timer.mode, .work)
        try expectEqual(timer.sessionsCompleted, sessions)
    }

    test("Skip from long rest → work") {
        let timer = makeTimerWithSettings(interval: 1)
        timer.skip()
        try expectEqual(timer.mode, .longRest)
        timer.skip()
        try expectEqual(timer.mode, .work)
    }

    test("Long break every 4 sessions") {
        let timer = makeTimerWithSettings(interval: 4)
        for _ in 1...3 {
            timer.skip() // work → rest
            try expectEqual(timer.mode, .rest)
            timer.skip() // rest → work
        }
        timer.skip() // session 4 → longRest
        try expectEqual(timer.mode, .longRest)
        try expectEqual(timer.sessionsCompleted, 4)
    }

    test("Long break custom interval (every 2)") {
        let timer = makeTimerWithSettings(interval: 2)
        timer.skip() // work → rest (session 1)
        try expectEqual(timer.mode, .rest)
        timer.skip() // rest → work
        timer.skip() // work → longRest (session 2)
        try expectEqual(timer.mode, .longRest)
        try expectEqual(timer.sessionsCompleted, 2)
    }

    test("Full 4-session cycle") {
        let timer = makeTimerWithSettings(interval: 4)
        var modes: [TimerMode] = []
        for _ in 1...4 {
            try expectEqual(timer.mode, .work)
            timer.skip()
            modes.append(timer.mode)
            timer.skip()
        }
        try expectEqual(modes, [.rest, .rest, .rest, .longRest])
        try expectEqual(timer.sessionsCompleted, 4)
        try expectEqual(timer.mode, .work)
    }

    // ── Computed Properties ──

    print("\nComputed Properties:")

    test("Display time format MM:SS") {
        let timer = makeTimerWithSettings(work: 50)
        try expectEqual(timer.displayTime, "50:00")

        let refDate = Date()
        timer.now = { refDate }
        timer.start()
        timer.now = { refDate.addingTimeInterval(1) }
        try expectEqual(timer.displayTime, "49:59")
    }

    test("Progress is 0 at start") {
        let timer = makeTimerWithSettings()
        try expectClose(timer.progress, 0.0, accuracy: 0.001)
    }

    test("Progress is 1 at end") {
        let timer = makeTimerWithSettings(work: 1)
        let refDate = Date()
        timer.now = { refDate }
        timer.start()
        timer.now = { refDate.addingTimeInterval(61) }
        try expectClose(timer.progress, 1.0, accuracy: 0.001)
    }

    test("Progress clamped when settings change mid-timer") {
        let timer = makeTimerWithSettings(work: 50)
        let refDate = Date()
        timer.now = { refDate }
        timer.start()
        timer.now = { refDate.addingTimeInterval(600) } // 10 min in
        // Shrink duration so remaining > currentDuration
        timer.settings?.workMinutes = 5
        try expect(timer.progress >= 0.0, "progress must not go negative")
        try expect(timer.progress <= 1.0, "progress must not exceed 1")
    }

    test("Current duration reflects mode") {
        let timer = makeTimerWithSettings(work: 50, brk: 10, longBrk: 20)
        try expectEqual(timer.currentDuration, 50 * 60)
        timer.mode = .rest
        try expectEqual(timer.currentDuration, 10 * 60)
        timer.mode = .longRest
        try expectEqual(timer.currentDuration, 20 * 60)
    }

    test("Current duration reflects custom settings") {
        let timer = makeTimerWithSettings(work: 25, brk: 5, longBrk: 15)
        try expectEqual(timer.currentDuration, 25 * 60)
        timer.mode = .rest
        try expectEqual(timer.currentDuration, 5 * 60)
        timer.mode = .longRest
        try expectEqual(timer.currentDuration, 15 * 60)
    }

    // ── Completion Callback ──

    print("\nCompletion Callback:")

    test("Callback fires with correct mode and auto-start flag") {
        let timer = makeTimerWithSettings()
        var callbackMode: TimerMode?
        var callbackAutoStart: Bool?
        timer.onTimerCompleted = { mode, autoStart in
            callbackMode = mode
            callbackAutoStart = autoStart
        }
        timer.simulateCompletion()
        try expectEqual(callbackMode, .work)
        try expectEqual(callbackAutoStart, false)
    }

    test("Auto-start break after work completion") {
        let timer = makeTimerWithSettings(autoBreaks: true)
        timer.onTimerCompleted = { _, shouldAutoStart in
            if shouldAutoStart { timer.start() }
        }
        timer.simulateCompletion()
        try expect(timer.isRunning)
        try expectEqual(timer.mode, .rest)
    }

    test("No auto-start by default") {
        let timer = makeTimerWithSettings()
        timer.onTimerCompleted = { _, shouldAutoStart in
            if shouldAutoStart { timer.start() }
        }
        timer.simulateCompletion()
        try expect(!timer.isRunning)
    }

    // ── Edge Cases ──

    print("\nEdge Cases:")

    test("Double start doesn't break state") {
        let timer = makeTimerWithSettings()
        timer.start()
        let remaining1 = timer.remaining
        timer.start()
        try expect(timer.isRunning)
        try expectClose(timer.remaining, remaining1, accuracy: 1.0)
    }

    test("Pause when not running is safe") {
        let timer = makeTimerWithSettings()
        timer.pause()
        try expect(!timer.isRunning)
        try expectEqual(timer.mode, .work)
    }

    test("Pause when not running keeps hasStarted false") {
        let timer = makeTimerWithSettings()
        timer.pause()
        try expect(!timer.hasStarted, "pause from idle must not set hasStarted")
    }

    test("Switch mode when paused toggles and resets duration") {
        let timer = makeTimerWithSettings(work: 50, brk: 10)
        try expectEqual(timer.mode, .work)
        timer.switchMode(to: .rest)
        try expectEqual(timer.mode, .rest)
        try expectClose(timer.remaining, 10 * 60, accuracy: 0.1)
        try expect(!timer.isRunning)
        // Switch back
        timer.switchMode(to: .work)
        try expectEqual(timer.mode, .work)
        try expectClose(timer.remaining, 50 * 60, accuracy: 0.1)
    }

    test("Switch mode blocked while running") {
        let timer = makeTimerWithSettings(work: 50, brk: 10)
        timer.start()
        try expect(timer.isRunning)
        timer.switchMode(to: .rest)
        try expectEqual(timer.mode, .work, "mode should not change while running")
    }

    test("Skip before start advances mode") {
        let timer = makeTimerWithSettings()
        timer.skip()
        try expectEqual(timer.mode, .rest)
        try expectEqual(timer.sessionsCompleted, 1)
        try expect(!timer.isRunning)
    }

    // ── Summary ──

    print("\n" + "=" * 50)
    print("Results: \(passed) passed, \(failed) failed, \(passed + failed) total")
    if !failures.isEmpty {
        print("\nFailures:")
        for (name, msg) in failures {
            print("  - \(name): \(msg)")
        }
    }
    print("")
    return failed == 0
}

extension String {
    static func * (lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}

@main
struct TestRunner {
    @MainActor
    static func main() {
        let timerSuccess = runAllTests()

        let idleResult = runIdleMonitorTests()
        print("\n" + "=" * 50)
        print("Idle Monitor: \(idleResult.passed) passed, \(idleResult.failed) failed")
        if !idleResult.failures.isEmpty {
            print("\nFailures:")
            for (name, msg) in idleResult.failures {
                print("  - \(name): \(msg)")
            }
        }
        print("")

        if !timerSuccess || idleResult.failed > 0 { exit(1) }
    }
}
