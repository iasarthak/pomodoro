import Foundation
@testable import PomodoroCore

// MARK: - IdleMonitor Tests

@MainActor
func runIdleMonitorTests() -> (passed: Int, failed: Int, failures: [(String, String)]) {
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

    func makeIdleMonitor(
        idleMinutes: Int = 30,
        enabled: Bool = true
    ) -> (IdleMonitor, PomodoroTimer, PomodoroSettings) {
        let timer = PomodoroTimer(testMode: true)
        let settings = PomodoroSettings()
        settings.idleReminderEnabled = enabled
        settings.idleReminderMinutes = idleMinutes
        timer.settings = settings
        let monitor = IdleMonitor(timer: timer, settings: settings, testMode: true)
        return (monitor, timer, settings)
    }

    print("\nIdle Monitor Tests")
    print("=" * 50)

    // ── Core Behavior ──

    print("\nCore Behavior:")

    test("Fires after idle threshold exceeded") {
        let (monitor, _, _) = makeIdleMonitor(idleMinutes: 30)
        let refDate = Date()
        monitor.now = { refDate }
        monitor.resetIdleClock()

        var fired = false
        monitor.onIdleReminder = { fired = true }

        // Advance past threshold
        monitor.now = { refDate.addingTimeInterval(31 * 60) }
        monitor.checkIdle()
        try expect(fired, "should fire after 31 minutes idle")
    }

    test("Does not fire before threshold") {
        let (monitor, _, _) = makeIdleMonitor(idleMinutes: 30)
        let refDate = Date()
        monitor.now = { refDate }
        monitor.resetIdleClock()

        var fired = false
        monitor.onIdleReminder = { fired = true }

        // Advance to just under threshold
        monitor.now = { refDate.addingTimeInterval(29 * 60) }
        monitor.checkIdle()
        try expect(!fired, "should not fire before 30 minutes")
    }

    test("Does not fire when timer is running") {
        let (monitor, timer, _) = makeIdleMonitor(idleMinutes: 30)
        let refDate = Date()
        monitor.now = { refDate }
        timer.now = { refDate }
        monitor.resetIdleClock()

        timer.start()

        var fired = false
        monitor.onIdleReminder = { fired = true }

        // Advance past threshold
        monitor.now = { refDate.addingTimeInterval(31 * 60) }
        timer.now = { refDate.addingTimeInterval(31 * 60) }
        monitor.checkIdle()
        try expect(!fired, "should not fire while timer is running")
    }

    test("Does not fire when disabled") {
        let (monitor, _, _) = makeIdleMonitor(idleMinutes: 30, enabled: false)
        let refDate = Date()
        monitor.now = { refDate }
        monitor.resetIdleClock()

        var fired = false
        monitor.onIdleReminder = { fired = true }

        monitor.now = { refDate.addingTimeInterval(31 * 60) }
        monitor.checkIdle()
        try expect(!fired, "should not fire when disabled")
    }

    test("Resets after dismissal — needs full interval again") {
        let (monitor, _, _) = makeIdleMonitor(idleMinutes: 30)
        let refDate = Date()
        monitor.now = { refDate }
        monitor.resetIdleClock()

        var fireCount = 0
        monitor.onIdleReminder = { fireCount += 1 }

        // First fire
        monitor.now = { refDate.addingTimeInterval(31 * 60) }
        monitor.checkIdle()
        try expectEqual(fireCount, 1)

        // Reset (simulates overlay dismissal — checkIdle already resets internally, but test explicit reset)
        monitor.now = { refDate.addingTimeInterval(32 * 60) }
        monitor.resetIdleClock()

        // Check just 10 min after reset — should not fire
        monitor.now = { refDate.addingTimeInterval(42 * 60) }
        monitor.checkIdle()
        try expectEqual(fireCount, 1, "should not fire before another full interval after reset")

        // Check 31 min after reset — should fire again
        monitor.now = { refDate.addingTimeInterval(63 * 60) }
        monitor.checkIdle()
        try expectEqual(fireCount, 2, "should fire again after full interval post-reset")
    }

    test("Respects custom duration setting") {
        let (monitor, _, _) = makeIdleMonitor(idleMinutes: 60)
        let refDate = Date()
        monitor.now = { refDate }
        monitor.resetIdleClock()

        var fired = false
        monitor.onIdleReminder = { fired = true }

        // 30 min — should not fire for 60 min setting
        monitor.now = { refDate.addingTimeInterval(30 * 60) }
        monitor.checkIdle()
        try expect(!fired, "should not fire at 30 min with 60 min threshold")

        // 61 min — should fire
        monitor.now = { refDate.addingTimeInterval(61 * 60) }
        monitor.checkIdle()
        try expect(fired, "should fire at 61 min with 60 min threshold")
    }

    return (passed, failed, failures)
}
