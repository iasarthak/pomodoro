import SwiftUI
import ClipboardCore

struct PanelContentView: View {
    @ObservedObject var history: ClipboardHistory
    @State private var searchQuery = ""
    @State private var selectedIndex = 0
    @State private var keyMonitor: Any?
    let onSelect: (ClipItem) -> Void
    let onDismiss: () -> Void

    private var filteredItems: [ClipItem] {
        history.search(query: searchQuery)
    }

    private var filteredFrequent: [ClipItem] {
        guard searchQuery.isEmpty else {
            let q = searchQuery.lowercased()
            return history.frequentItems.filter {
                $0.content.textValue?.lowercased().contains(q) ?? false
            }
        }
        return history.frequentItems
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.6))

                TextField("Search clips...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .rounded))

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }

                // Item count
                Text("\(history.items.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.05))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.15)

            // Frequent bar
            if !filteredFrequent.isEmpty {
                FrequentBar(items: filteredFrequent) { item in
                    onSelect(item)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider().opacity(0.15)
            }

            // Recent list header
            if !filteredItems.isEmpty {
                HStack {
                    Text("RECENT")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .tracking(1.5)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            // Recent list
            if filteredItems.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text(searchQuery.isEmpty ? "Nothing copied yet" : "No matches")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                ClipItemRow(item: item, isSelected: index == selectedIndex)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onSelect(item)
                                    }
                            }
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                    }
                    .onChange(of: selectedIndex) {
                        if let item = filteredItems[safe: selectedIndex] {
                            proxy.scrollTo(item.id, anchor: .center)
                        }
                    }
                }
            }

            // Footer
            Divider().opacity(0.15)
            HStack(spacing: 16) {
                keyHint("⌘⇧C", "toggle")
                keyHint("↵", "paste")
                keyHint("⌫", "delete")
                keyHint("esc", "close")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .onChange(of: searchQuery) {
            selectedIndex = 0
        }
        .onAppear {
            selectedIndex = 0
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            switch Int(event.keyCode) {
            case 53: // Escape
                onDismiss()
                return nil
            case 125: // Down arrow
                if selectedIndex < filteredItems.count - 1 {
                    selectedIndex += 1
                }
                return nil
            case 126: // Up arrow
                if selectedIndex > 0 {
                    selectedIndex -= 1
                }
                return nil
            case 36: // Return
                if let item = filteredItems[safe: selectedIndex] {
                    onSelect(item)
                }
                return nil
            case 51: // Delete
                if let item = filteredItems[safe: selectedIndex] {
                    history.removeItem(id: item.id)
                    if selectedIndex >= filteredItems.count {
                        selectedIndex = max(0, filteredItems.count - 1)
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

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.4))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.3))
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
