import Foundation
import AppKit
import UserNotifications
import Combine

@MainActor
public class PomodoroTimer: ObservableObject {
    @Published public var mode: TimerMode = .work
    @Published public var sessionsCompleted = 0
    public var settings: PomodoroSettings?
    public var onTimerCompleted: ((TimerMode) -> Void)?

    /// Injectable clock for testing — defaults to system time
    public var now: () -> Date = { Date() }

    private var endDate: Date?
    private var pausedRemaining: TimeInterval?
    private var ticker: Timer?
    private var wakeObserver: NSObjectProtocol?

    public var isRunning: Bool { endDate != nil && pausedRemaining == nil }
    public var hasStarted: Bool { endDate != nil || pausedRemaining != nil }

    public var currentDuration: TimeInterval {
        guard let s = settings else { return 50 * 60 }
        switch mode {
        case .work: return s.workDuration
        case .rest: return s.breakDuration
        case .longRest: return s.longBreakDuration
        }
    }

    public var remaining: TimeInterval {
        if let paused = pausedRemaining { return paused }
        guard let end = endDate else { return currentDuration }
        return max(0, end.timeIntervalSince(now()))
    }

    public var progress: Double {
        1.0 - (remaining / currentDuration)
    }

    public var displayTime: String {
        let total = Int(remaining)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private let isTestMode: Bool

    /// Production init — registers wake observer
    public init() {
        isTestMode = false
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Test init — skips wake observer and side effects
    public init(testMode: Bool) {
        isTestMode = testMode
    }

    public func start() {
        endDate = now().addingTimeInterval(pausedRemaining ?? currentDuration)
        pausedRemaining = nil
        startTicking()
    }

    public func pause() {
        pausedRemaining = remaining
        endDate = nil
        stopTicking()
    }

    public func reset() {
        endDate = nil
        pausedRemaining = nil
        stopTicking()
    }

    public func skip() {
        let completedMode = mode
        stopTicking()
        endDate = nil
        pausedRemaining = nil
        advanceMode(from: completedMode)
    }

    /// Exposed as internal for testing
    func advanceMode(from completedMode: TimerMode) {
        if completedMode == .work {
            sessionsCompleted += 1
            let interval = settings?.longBreakInterval ?? 4
            if interval > 0 && sessionsCompleted % interval == 0 {
                mode = .longRest
            } else {
                mode = .rest
            }
        } else {
            mode = .work
        }
    }

    /// Simulate timer completion — exposed for testing
    public func simulateCompletion() {
        timerCompleted()
    }

    private func timerCompleted() {
        let completedMode = mode
        let shouldAutoStart: Bool
        if completedMode == .work {
            shouldAutoStart = settings?.autoStartBreaks ?? false
        } else {
            shouldAutoStart = settings?.autoStartWork ?? false
        }

        skip()
        if !isTestMode {
            sendNotification(for: completedMode)
            NSSound(named: settings?.soundName ?? "Purr")?.play()
        }
        onTimerCompleted?(completedMode)

        if shouldAutoStart {
            start()
        }
    }

    private var lastDisplayTime = ""

    private func startTicking() {
        stopTicking()
        lastDisplayTime = ""
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let newTime = self.displayTime
                if newTime != self.lastDisplayTime {
                    self.lastDisplayTime = newTime
                    self.objectWillChange.send()
                }
                if self.remaining <= 0 && self.isRunning {
                    self.timerCompleted()
                }
            }
        }
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func sendNotification(for completedMode: TimerMode) {
        let content = UNMutableNotificationContent()
        content.title = completedMode.completionTitle
        content.body = completedMode.completionBody
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}
