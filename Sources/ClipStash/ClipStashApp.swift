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

        // Request accessibility if not granted
        if !PasteService.checkAccessibility() {
            PasteService.requestAccessibility()
        }

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
            if self?.isCmdShiftV(event) == true {
                Task { @MainActor in
                    self?.togglePanel()
                }
            }
        }

        // Local monitor — when our app is focused
        localHotkey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isCmdShiftV(event) == true {
                Task { @MainActor in
                    self?.togglePanel()
                }
                return nil
            }
            return event
        }
    }

    private func isCmdShiftV(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == 0x09 && flags == [.command, .shift]
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

    var body: some View {
        VStack(spacing: 0) {
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
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(history.items.prefix(15)) { item in
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
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            }

            Divider().opacity(0.15)

            HStack {
                Button {
                    onTogglePanel()
                } label: {
                    HStack(spacing: 4) {
                        Text("⌘⇧V")
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
                Button("Quit") { NSApp.terminate(nil) }
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 8)
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
