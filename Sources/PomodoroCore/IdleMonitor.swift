import Foundation
import Combine

@MainActor
public class IdleMonitor: ObservableObject {
    public var onIdleReminder: (() -> Void)?

    /// Injectable clock for testing — defaults to system time
    public var now: () -> Date = { Date() }

    private var lastActiveDate: Date
    private var ticker: Timer?
    private var cancellable: AnyCancellable?
    private let timer: PomodoroTimer
    private let settings: PomodoroSettings
    private var wasRunning = false

    public init(timer: PomodoroTimer, settings: PomodoroSettings) {
        self.timer = timer
        self.settings = settings
        self.lastActiveDate = Date()

        // Observe timer state changes — reset idle clock when timer starts running
        cancellable = timer.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.handleTimerStateChange()
            }
        }

        startChecking()
    }

    /// Test init — skips background timer
    public init(timer: PomodoroTimer, settings: PomodoroSettings, testMode: Bool) {
        self.timer = timer
        self.settings = settings
        self.lastActiveDate = Date()
    }

    /// Reset the idle clock — called after overlay dismissal
    public func resetIdleClock() {
        lastActiveDate = now()
    }

    /// Manually trigger an idle check — exposed for testing
    public func checkIdle() {
        guard settings.idleReminderEnabled else { return }
        guard !timer.isRunning else {
            lastActiveDate = now()
            return
        }

        let elapsed = now().timeIntervalSince(lastActiveDate)
        if elapsed >= settings.idleReminderDuration {
            lastActiveDate = now()
            onIdleReminder?()
        }
    }

    private func handleTimerStateChange() {
        let running = timer.isRunning
        if running && !wasRunning {
            lastActiveDate = now()
        }
        wasRunning = running
    }

    private func startChecking() {
        ticker = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdle()
            }
        }
    }

    deinit {
        ticker?.invalidate()
    }
}
