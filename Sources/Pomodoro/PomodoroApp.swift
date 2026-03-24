import SwiftUI
import UserNotifications
import AppKit

// MARK: - Colors

extension Color {
    static let pomodoroWork = Color(red: 1.0, green: 0.42, blue: 0.42)   // #FF6B6B
    static let pomodoroBreak = Color(red: 0.42, green: 0.80, blue: 0.47) // #6BCB77
}

// MARK: - Timer Mode

enum TimerMode: String {
    case work = "Focus"
    case rest = "Break"

    var icon: String {
        switch self {
        case .work: "timer"
        case .rest: "cup.and.saucer.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .work: .pomodoroWork
        case .rest: .pomodoroBreak
        }
    }

    var completionTitle: String {
        switch self {
        case .work: "Focus session done!"
        case .rest: "Break's over!"
        }
    }

    var completionBody: String {
        switch self {
        case .work: "Nice work. Take a 10-minute break."
        case .rest: "Ready to focus again?"
        }
    }
}

// MARK: - App Entry Point

@main
struct PomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var timer = PomodoroTimer()

    var body: some Scene {
        MenuBarExtra {
            TimerPopoverView(timer: timer)
                .frame(width: 280)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: timer.mode.icon)
                if timer.isRunning {
                    Text(timer.displayTime)
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Timer State

@MainActor
class PomodoroTimer: ObservableObject {
    @Published var mode: TimerMode = .work
    @Published var sessionsCompleted = 0

    private var endDate: Date?
    private var pausedRemaining: TimeInterval?
    private var ticker: Timer?
    private var wakeObserver: NSObjectProtocol?

    let workDuration: TimeInterval = 50 * 60
    let breakDuration: TimeInterval = 10 * 60

    var isRunning: Bool { endDate != nil && pausedRemaining == nil }

    var hasStarted: Bool { endDate != nil || pausedRemaining != nil }

    var currentDuration: TimeInterval {
        mode == .work ? workDuration : breakDuration
    }

    var remaining: TimeInterval {
        if let paused = pausedRemaining { return paused }
        guard let end = endDate else { return currentDuration }
        return max(0, end.timeIntervalSince(Date()))
    }

    var progress: Double {
        1.0 - (remaining / currentDuration)
    }

    var displayTime: String {
        let total = Int(remaining)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    init() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func start() {
        endDate = Date().addingTimeInterval(pausedRemaining ?? currentDuration)
        pausedRemaining = nil
        startTicking()
    }

    func pause() {
        pausedRemaining = remaining
        endDate = nil
        stopTicking()
    }

    func reset() {
        endDate = nil
        pausedRemaining = nil
        stopTicking()
    }

    func skip() {
        let completedMode = mode
        stopTicking()
        endDate = nil
        pausedRemaining = nil

        if completedMode == .work {
            sessionsCompleted += 1
            mode = .rest
        } else {
            mode = .work
        }
    }

    private func timerCompleted() {
        let completedMode = mode
        skip()
        sendNotification(for: completedMode)
        NSSound(named: "Purr")?.play()
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
        content.sound = nil // NSSound handles audio

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Views

struct TimerPopoverView: View {
    @ObservedObject var timer: PomodoroTimer
    private let controlAnimation = Animation.easeInOut(duration: 0.2)

    private var accent: Color { timer.mode.accentColor }

    var body: some View {
        VStack(spacing: 20) {
            Text(timer.mode.rawValue.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(accent.opacity(0.9))

            // Ring + countdown
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timer.progress)

                Text(timer.displayTime)
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
            .frame(width: 180, height: 180)

            // Controls
            HStack(spacing: 24) {
                circleButton(icon: "arrow.counterclockwise") {
                    withAnimation(controlAnimation) { timer.reset() }
                }
                .opacity(timer.hasStarted ? 1 : 0.3)
                .disabled(!timer.hasStarted)

                Button {
                    withAnimation(controlAnimation) {
                        timer.isRunning ? timer.pause() : timer.start()
                    }
                } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 56, height: 56)
                        .background(accent)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                circleButton(icon: "forward.fill") {
                    withAnimation(controlAnimation) { timer.skip() }
                }
                .opacity(timer.hasStarted ? 1 : 0.3)
                .disabled(!timer.hasStarted)
            }

            // Session dots
            if timer.sessionsCompleted > 0 {
                HStack(spacing: 4) {
                    ForEach(0..<min(timer.sessionsCompleted, 8), id: \.self) { _ in
                        Circle()
                            .fill(accent.opacity(0.7))
                            .frame(width: 6, height: 6)
                    }
                    if timer.sessionsCompleted > 8 {
                        Text("+\(timer.sessionsCompleted - 8)")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
            }

            Button("Quit") { NSApp.terminate(nil) }
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .help("Quit Pomodoro")
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.4), value: timer.mode)
    }

    private func circleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
