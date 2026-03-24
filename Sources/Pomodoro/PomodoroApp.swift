import SwiftUI
import UserNotifications
import AppKit

// MARK: - App Entry Point

@main
struct PomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var timer = PomodoroTimer()

    var body: some Scene {
        MenuBarExtra {
            TimerPopoverView(timer: timer)
                .frame(width: 280, height: 380)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: timer.mode == .work ? "brain.head.profile" : "cup.and.saucer.fill")
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
        setupNotifications()
    }

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // Show notification even when app is focused
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Timer State

enum TimerMode: String {
    case work = "Focus"
    case rest = "Break"
}

@MainActor
class PomodoroTimer: ObservableObject {
    @Published var mode: TimerMode = .work
    @Published var isRunning = false
    @Published var sessionsCompleted = 0

    private var endDate: Date?
    private var pausedRemaining: TimeInterval?
    private var displayLink: Timer?

    // Durations in seconds
    let workDuration: TimeInterval = 50 * 60
    let breakDuration: TimeInterval = 10 * 60

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
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    func start() {
        let duration = pausedRemaining ?? currentDuration
        endDate = Date().addingTimeInterval(duration)
        pausedRemaining = nil
        isRunning = true
        startTicking()
        observeWake()
    }

    func pause() {
        pausedRemaining = remaining
        endDate = nil
        isRunning = false
        stopTicking()
    }

    func reset() {
        endDate = nil
        pausedRemaining = nil
        isRunning = false
        stopTicking()
    }

    func skip() {
        switchMode()
    }

    private func switchMode() {
        stopTicking()
        isRunning = false
        endDate = nil
        pausedRemaining = nil

        if mode == .work {
            sessionsCompleted += 1
            mode = .rest
        } else {
            mode = .work
        }
    }

    private func timerCompleted() {
        sendNotification()
        playSound()
        switchMode()
    }

    private func startTicking() {
        stopTicking()
        displayLink = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.objectWillChange.send()
                if self.remaining <= 0 && self.isRunning {
                    self.timerCompleted()
                }
            }
        }
    }

    private func stopTicking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func observeWake() {
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = mode == .work ? "Focus session done!" : "Break's over!"
        content.body = mode == .work
            ? "Nice work. Take a 10-minute break."
            : "Ready to focus again?"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func playSound() {
        NSSound(named: "Purr")?.play()
    }
}

// MARK: - Main Popover View

struct TimerPopoverView: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        VStack(spacing: 20) {
            // Mode label
            Text(timer.mode.rawValue.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(accentColor.opacity(0.9))

            // Ring + time
            ZStack {
                // Background ring
                Circle()
                    .stroke(accentColor.opacity(0.15), lineWidth: 6)

                // Progress ring
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(
                        accentColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timer.progress)

                // Countdown
                Text(timer.displayTime)
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
            .frame(width: 180, height: 180)

            // Controls
            HStack(spacing: 24) {
                // Reset
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { timer.reset() }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(timer.isRunning || timer.remaining < timer.currentDuration ? 1 : 0.3)
                .disabled(!timer.isRunning && timer.remaining >= timer.currentDuration)

                // Play / Pause
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        timer.isRunning ? timer.pause() : timer.start()
                    }
                } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 56, height: 56)
                        .background(accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Skip
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { timer.skip() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Session count
            if timer.sessionsCompleted > 0 {
                HStack(spacing: 4) {
                    ForEach(0..<min(timer.sessionsCompleted, 8), id: \.self) { _ in
                        Circle()
                            .fill(Color(hex: "FF6B6B").opacity(0.7))
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

            // Quit
            Button("Quit") { NSApp.terminate(nil) }
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.4), value: timer.mode)
    }

    var accentColor: Color {
        timer.mode == .work ? Color(hex: "FF6B6B") : Color(hex: "6BCB77")
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
