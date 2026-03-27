import SwiftUI
import ClipboardCore

struct FrequentBar: View {
    let items: [ClipItem]
    let onSelect: (ClipItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange.opacity(0.6))
                Text("FREQUENT")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .tracking(1.5)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            HStack(spacing: 4) {
                                Text(chipText(item))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary.opacity(0.85))

                                Text("×\(item.copyCount)")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary.opacity(0.5))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.06))
                            .overlay(
                                Capsule()
                                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                            )
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
        if clean.count > 28 {
            return String(clean.prefix(26)) + "..."
        }
        return clean
    }
}
