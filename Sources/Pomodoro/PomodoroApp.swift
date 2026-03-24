import SwiftUI
import UserNotifications
import AppKit
import PomodoroCore

// MARK: - App Entry Point

@main
struct PomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings: PomodoroSettings
    @StateObject private var timer: PomodoroTimer

    init() {
        let s = PomodoroSettings()
        let t = PomodoroTimer()
        let overlay = OverlayManager()
        t.settings = s
        t.onTimerCompleted = { completedMode in
            overlay.show(mode: completedMode) {}
        }
        _settings = StateObject(wrappedValue: s)
        _timer = StateObject(wrappedValue: t)
    }

    var body: some Scene {
        MenuBarExtra {
            TimerPopoverView(timer: timer, settings: settings)
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

// MARK: - Timer View

struct TimerPopoverView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var settings: PomodoroSettings
    @State private var showSettings = false
    private let controlAnimation = Animation.easeInOut(duration: 0.2)

    private var accent: Color { timer.mode.accentColor }

    var body: some View {
        VStack(spacing: 20) {
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
            VStack(spacing: 10) {
                durationRow("Focus", value: $settings.workMinutes, range: 1...90)
                durationRow("Break", value: $settings.breakMinutes, range: 1...30)
                durationRow("Long break", value: $settings.longBreakMinutes, range: 5...60)
            }
            Divider().opacity(0.3)
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
            VStack(spacing: 8) {
                Toggle("Auto-start breaks", isOn: $settings.autoStartBreaks)
                    .font(.system(size: 12, design: .rounded))
                Toggle("Auto-start focus", isOn: $settings.autoStartWork)
                    .font(.system(size: 12, design: .rounded))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            Divider().opacity(0.3)
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

// MARK: - Completion Overlay

@MainActor
class OverlayManager {
    private var window: NSPanel?
    private var dismissAction: (() -> Void)?
    private var autoDismissTask: Task<Void, Never>?

    func show(mode: TimerMode, onDismiss: @escaping () -> Void) {
        dismiss()
        dismissAction = onDismiss

        guard let screen = NSScreen.main else { return }
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let overlayView = CompletionOverlayView(mode: mode) { [weak self] in
            self?.dismiss()
        }
        panel.contentView = NSHostingView(rootView: overlayView)
        panel.makeKeyAndOrderFront(nil)

        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 1
        }

        self.window = panel

        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self.dismiss()
        }
    }

    func dismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        guard let panel = window else { return }
        let action = dismissAction
        dismissAction = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
                self.window = nil
                action?()
            }
        })
    }
}

struct CompletionOverlayView: View {
    let mode: TimerMode
    let onDismiss: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: mode == .work ? "checkmark.circle.fill" : "bolt.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(mode.accentColor)
                    .scaleEffect(appeared ? 1 : 0.5)
                    .opacity(appeared ? 1 : 0)

                Text(mode.completionTitle)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)

                Text(mode.completionBody)
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)

                Text("click anywhere to dismiss")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 16)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}
