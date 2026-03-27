import SwiftUI
import AppKit
import ClipboardCore

// Shared state — single instance used by both menu bar and floating panel
@MainActor
let sharedHistory = ClipboardHistory()

// MARK: - App Entry Point

@main
struct ClipStashApp: App {
    @NSApplicationDelegateAdaptor(ClipStashDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(history: sharedHistory, onTogglePanel: {
                appDelegate.togglePanel()
            })
            .frame(width: 300)
        } label: {
            Image(systemName: "doc.on.clipboard")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App Delegate

@MainActor
class ClipStashDelegate: NSObject, NSApplicationDelegate {
    let panel = ClipboardPanel()
    private var monitor: ClipboardMonitor?
    private var globalHotkey: Any?
    private var localHotkey: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Start clipboard monitoring
        Task { @MainActor in
            let m = ClipboardMonitor()
            m.onNewClip = { content, sourceApp in
                sharedHistory.addItem(content: content, sourceApp: sourceApp)
            }
            self.monitor = m
        }

        setupHotkeys()
    }

    private func setupHotkeys() {
        // Global monitor — Cmd+Shift+V
        globalHotkey = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isCmdShiftC(event) == true {
                Task { @MainActor in
                    self?.togglePanel()
                }
            }
        }

        // Local monitor — when our app is focused
        localHotkey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isCmdShiftC(event) == true {
                Task { @MainActor in
                    self?.togglePanel()
                }
                return nil
            }
            return event
        }
    }

    private func isCmdShiftC(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == 0x08 && flags == [.command, .shift] // 0x08 = 'c'
    }

    @MainActor
    func togglePanel() {
        panel.toggle(content: PanelContentView(
            history: sharedHistory,
            onSelect: { [weak self] item in
                self?.panel.dismiss()
                PasteService.shared.paste(item)
            },
            onDismiss: { [weak self] in
                self?.panel.dismiss()
            }
        ))
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @ObservedObject var history: ClipboardHistory
    let onTogglePanel: () -> Void
    @State private var selectedIndex = -1
    @State private var keyMonitor: Any?

    private var visibleItems: [ClipItem] {
        Array(history.items.prefix(15))
    }

    private var needsAccessibility: Bool {
        !PasteService.checkAccessibility()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Accessibility nudge — only when not granted, user-initiated
            if needsAccessibility {
                Button {
                    PasteService.requestAccessibility()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Text("Enable Accessibility for paste & hotkey")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                Divider().opacity(0.15)
            }

            if history.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("Nothing copied yet")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .padding(.vertical, 24)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    PasteService.shared.paste(item)
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: menuBarIcon(for: item))
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(menuBarIconColor(for: item))
                                            .frame(width: 12)

                                        Text(item.preview)
                                            .font(.system(size: 11, design: .rounded))
                                            .lineLimit(1)
                                            .foregroundStyle(.primary)

                                        Spacer()

                                        if item.copyCount > 1 {
                                            Text("×\(item.copyCount)")
                                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                                .foregroundStyle(.secondary.opacity(0.4))
                                        }

                                        Text(item.relativeTime())
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundStyle(.secondary.opacity(0.5))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(index == selectedIndex ? Color.accentColor.opacity(0.25) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(item.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selectedIndex) {
                        if let item = visibleItems[safe: selectedIndex] {
                            proxy.scrollTo(item.id, anchor: .center)
                        }
                    }
                }
            }

            Divider().opacity(0.15)

            HStack {
                Button {
                    onTogglePanel()
                } label: {
                    HStack(spacing: 4) {
                        Text("⌘⇧C")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text("Full panel")
                            .font(.system(size: 10, design: .rounded))
                    }
                    .foregroundStyle(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                Spacer()
                HStack(spacing: 8) {
                    Text("↑↓ ↵")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.3))
                    Button("Quit") { NSApp.terminate(nil) }
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 8)
        .onAppear {
            selectedIndex = -1
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 125: // Down arrow
                if selectedIndex < visibleItems.count - 1 {
                    selectedIndex += 1
                }
                return nil
            case 126: // Up arrow
                if selectedIndex > 0 {
                    selectedIndex -= 1
                }
                return nil
            case 36: // Return
                if let item = visibleItems[safe: selectedIndex] {
                    PasteService.shared.paste(item)
                }
                return nil
            case 51: // Delete
                if let item = visibleItems[safe: selectedIndex] {
                    history.removeItem(id: item.id)
                    if selectedIndex >= visibleItems.count {
                        selectedIndex = max(-1, visibleItems.count - 1)
                    }
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func menuBarIcon(for item: ClipItem) -> String {
        guard case .text(let s) = item.content else { return "photo" }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return "link" }
        if t.contains("()") || t.contains("=>") || t.contains("SELECT ") || t.contains("FROM ") ||
           t.hasPrefix("npm ") || t.hasPrefix("swift ") || t.hasPrefix("git ") || t.hasPrefix("const ") ||
           t.hasPrefix("let ") || t.hasPrefix("var ") || t.hasPrefix("func ") { return "chevron.left.forwardslash.chevron.right" }
        return "doc.text"
    }

    private func menuBarIconColor(for item: ClipItem) -> Color {
        let icon = menuBarIcon(for: item)
        switch icon {
        case "link": return .blue
        case "chevron.left.forwardslash.chevron.right": return .orange
        case "photo": return .purple
        default: return .secondary.opacity(0.5)
        }
    }
}
