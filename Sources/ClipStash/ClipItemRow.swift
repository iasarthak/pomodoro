import SwiftUI
import AppKit
import ClipboardCore

struct ClipItemRow: View {
    let item: ClipItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            contentPreview
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.relativeTime())
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)

                if item.copyCount > 1 {
                    Text("×\(item.copyCount)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.content {
        case .text(let string):
            VStack(alignment: .leading, spacing: 2) {
                Text(string.components(separatedBy: .newlines).first ?? string)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let app = item.sourceApp {
                    Text(app)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }

        case .image(let data):
            HStack(spacing: 8) {
                if let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Image")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.primary)

                    if let app = item.sourceApp {
                        Text(app)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
