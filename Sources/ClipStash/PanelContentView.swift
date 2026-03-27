import SwiftUI
import ClipboardCore

struct PanelContentView: View {
    @ObservedObject var history: ClipboardHistory
    @State private var searchQuery = ""
    @State private var selectedIndex = 0
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
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                TextField("Search...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .rounded))

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider().opacity(0.3)

            // Frequent bar
            if !filteredFrequent.isEmpty {
                FrequentBar(items: filteredFrequent) { item in
                    onSelect(item)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider().opacity(0.3)
            }

            // Recent list
            if filteredItems.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(searchQuery.isEmpty ? "Clipboard history is empty" : "No matches")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                ClipItemRow(item: item, isSelected: index == selectedIndex)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onSelect(item)
                                    }
                            }
                        }
                        .padding(.vertical, 4)
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
            Divider().opacity(0.3)
            HStack {
                Text("⌘⇧V to toggle")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.quaternary)
                Spacer()
                Text("↵ paste · ⌫ delete · esc close")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredItems.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            if let item = filteredItems[safe: selectedIndex] {
                onSelect(item)
            }
            return .handled
        }
        .onKeyPress(.delete) {
            if let item = filteredItems[safe: selectedIndex] {
                history.removeItem(id: item.id)
                if selectedIndex >= filteredItems.count {
                    selectedIndex = max(0, filteredItems.count - 1)
                }
            }
            return .handled
        }
        .onChange(of: searchQuery) {
            selectedIndex = 0
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
