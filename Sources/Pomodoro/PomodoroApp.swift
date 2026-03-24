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
    case longRest = "Long Break"

    var icon: String {
        switch self {
        case .work: "timer"
        case .rest: "cup.and.saucer.fill"
        case .longRest: "cup.and.saucer.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .work: .pomodoroWork
        case .rest, .longRest: .pomodoroBreak
        }
    }

    var completionTitle: String {
        switch self {
        case .work: "Focus session done!"
        case .rest: "Break's over!"
        case .longRest: "Long break's over!"
        }
    }

    var completionBody: String {
        switch self {
        case .work: "Nice work. Time for a break."
        case .rest: "Ready to focus again?"
        case .longRest: "Recharged? Let's go."
        }
    }
}

// MARK: - Settings

class PomodoroSettings: ObservableObject {
    @AppStorage("workMinutes") var workMinutes = 50
    @AppStorage("breakMinutes") var breakMinutes = 10
    @AppStorage("longBreakMinutes") var longBreakMinutes = 20
    @AppStorage("longBreakInterval") var longBreakInterval = 4
    @AppStorage("autoStartBreaks") var autoStartBreaks = false
    @AppStorage("autoStartWork") var autoStartWork = false
    @AppStorage("soundName") var soundName = "Purr"

    static let availableSounds = ["Purr", "Ping", "Pop", "Blow", "Glass", "Hero", "Submarine", "Tink"]

    var workDuration: TimeInterval { TimeInterval(workMinutes * 60) }
    var breakDuration: TimeInterval { TimeInterval(breakMinutes * 60) }
    var longBreakDuration: TimeInterval { TimeInterval(longBreakMinutes * 60) }
}

// MARK: - App Entry Point

@main
struct PomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = PomodoroSettings()
    @StateObject private var timer = PomodoroTimer()

    var body: some Scene {
        MenuBarExtra {
            TimerPopoverView(timer: timer, settings: settings)
                .frame(width: 280)
                .onAppear { timer.settings = settings }
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
    var settings: PomodoroSettings?

    private var endDate: Date?
    private var pausedRemaining: TimeInterval?
    private var ticker: Timer?
    private var wakeObserver: NSObjectProtocol?

    var isRunning: Bool { endDate != nil && pausedRemaining == nil }
    var hasStarted: Bool { endDate != nil || pausedRemaining != nil }

    var currentDuration: TimeInterval {
        guard let s = settings else { return 50 * 60 }
        switch mode {
        case .work: return s.workDuration
        case .rest: return s.breakDuration
        case .longRest: return s.longBreakDuration
        }
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
        advanceMode(from: completedMode)
    }

    private func advanceMode(from completedMode: TimerMode) {
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

    private func timerCompleted() {
        let completedMode = mode
        let shouldAutoStart: Bool
        if completedMode == .work {
            shouldAutoStart = settings?.autoStartBreaks ?? false
        } else {
            shouldAutoStart = settings?.autoStartWork ?? false
        }

        skip()
        sendNotification(for: completedMode)
        NSSound(named: settings?.soundName ?? "Purr")?.play()

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

// MARK: - Timer View

struct TimerPopoverView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var settings: PomodoroSettings
    @State private var showSettings = false
    private let controlAnimation = Animation.easeInOut(duration: 0.2)

    private var accent: Color { timer.mode.accentColor }

    var body: some View {
        VStack(spacing: 20) {
            // Header with settings gear
            HStack {
                Spacer()
                Text(timer.mode.rawValue.uppercased())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(accent.opacity(0.9))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showSettings.toggle() }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }

            if showSettings {
                SettingsPanel(settings: settings)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                timerContent
                    .transition(.opacity)
            }

            // Footer
            HStack {
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
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .buttonStyle(.plain)
                    .help("Quit Pomodoro")
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.4), value: timer.mode)
    }

    private var timerContent: some View {
        VStack(spacing: 20) {
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
                .help("Reset")

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
                .help(timer.isRunning ? "Pause" : "Start")

                circleButton(icon: "forward.fill") {
                    withAnimation(controlAnimation) { timer.skip() }
                }
                .opacity(timer.hasStarted ? 1 : 0.3)
                .disabled(!timer.hasStarted)
                .help("Skip")
            }
        }
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

// MARK: - Settings Panel

struct SettingsPanel: View {
    @ObservedObject var settings: PomodoroSettings

    var body: some View {
        VStack(spacing: 16) {
            // Durations
            VStack(spacing: 10) {
                durationRow("Focus", value: $settings.workMinutes, range: 1...90)
                durationRow("Break", value: $settings.breakMinutes, range: 1...30)
                durationRow("Long break", value: $settings.longBreakMinutes, range: 5...60)
            }

            Divider().opacity(0.3)

            // Long break interval
            HStack {
                Text("Long break every")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $settings.longBreakInterval) {
                    ForEach([2, 3, 4, 5, 6], id: \.self) { n in
                        Text("\(n) sessions").tag(n)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }

            Divider().opacity(0.3)

            // Auto-start toggles
            VStack(spacing: 8) {
                Toggle("Auto-start breaks", isOn: $settings.autoStartBreaks)
                    .font(.system(size: 12, design: .rounded))
                Toggle("Auto-start focus", isOn: $settings.autoStartWork)
                    .font(.system(size: 12, design: .rounded))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Divider().opacity(0.3)

            // Sound
            HStack {
                Text("Sound")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $settings.soundName) {
                    ForEach(PomodoroSettings.availableSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .onChange(of: settings.soundName) { newValue in
                    NSSound(named: newValue)?.play()
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func durationRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Button {
                    if value.wrappedValue > range.lowerBound {
                        value.wrappedValue -= 5
                        value.wrappedValue = max(value.wrappedValue, range.lowerBound)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(value.wrappedValue <= range.lowerBound)

                Text("\(value.wrappedValue)m")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 36)

                Button {
                    if value.wrappedValue < range.upperBound {
                        value.wrappedValue += 5
                        value.wrappedValue = min(value.wrappedValue, range.upperBound)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(value.wrappedValue >= range.upperBound)
            }
        }
    }
}
