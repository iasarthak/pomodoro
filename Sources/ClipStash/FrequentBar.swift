import SwiftUI
import ClipboardCore

struct FrequentBar: View {
    let items: [ClipItem]
    let onSelect: (ClipItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FREQUENT")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            Text(chipText(item))
                                .font(.system(size: 11, design: .rounded))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func chipText(_ item: ClipItem) -> String {
        let text = item.content.textValue ?? ""
        let clean = text.components(separatedBy: .newlines).first ?? text
        if clean.count > 30 {
            return String(clean.prefix(28)) + "..."
        }
        return clean
    }
}
