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
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No clipboard history")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(history.items.prefix(20)) { item in
                            Button {
                                PasteService.shared.paste(item)
                            } label: {
                                HStack {
                                    Text(item.preview)
                                        .font(.system(size: 11, design: .monospaced))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(item.relativeTime())
                                        .font(.system(size: 10, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider().opacity(0.3)

            HStack {
                Button("⌘⇧V Full Panel") { onTogglePanel() }
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.quaternary)
                    .buttonStyle(.plain)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 8)
    }
}
