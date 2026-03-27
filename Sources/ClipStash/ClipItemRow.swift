import SwiftUI
import AppKit
import ClipboardCore

struct ClipItemRow: View {
    let item: ClipItem
    let isSelected: Bool

    private var contentType: ContentType {
        guard case .text(let s) = item.content else { return .image }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return .url }
        if trimmed.contains("SELECT ") || trimmed.contains("INSERT ") || trimmed.contains("UPDATE ") || trimmed.contains("DELETE ") || trimmed.contains("FROM ") { return .code }
        if trimmed.contains("()") || trimmed.contains("=>") || trimmed.contains("func ") || trimmed.contains("const ") || trimmed.contains("let ") || trimmed.contains("var ") || trimmed.contains("import ") { return .code }
        if trimmed.hasPrefix("npm ") || trimmed.hasPrefix("swift ") || trimmed.hasPrefix("git ") || trimmed.hasPrefix("cd ") || trimmed.hasPrefix("bash ") { return .code }
        return .text
    }

    private enum ContentType {
        case text, url, code, image

        var icon: String {
            switch self {
            case .text: return "doc.text"
            case .url: return "link"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .image: return "photo"
            }
        }

        var iconColor: Color {
            switch self {
            case .text: return .secondary
            case .url: return .blue
            case .code: return .orange
            case .image: return .purple
            }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Type indicator
            Image(systemName: contentType.icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(contentType.iconColor)
                .frame(width: 16)

            // Content
            contentPreview
                .frame(maxWidth: .infinity, alignment: .leading)

            // Metadata
            VStack(alignment: .trailing, spacing: 3) {
                Text(item.relativeTime())
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.7))

                if item.copyCount > 1 {
                    Text("×\(item.copyCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        )
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.content {
        case .text(let string):
            VStack(alignment: .leading, spacing: 2) {
                Text(string.components(separatedBy: .newlines).first ?? string)
                    .font(contentType == .code
                        ? .system(size: 12, design: .monospaced)
                        : .system(size: 12, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let app = item.sourceApp {
                    Text(app)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.5))
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
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Image")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.primary)

                    if let app = item.sourceApp {
                        Text(app)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                }
            }
        }
    }
}
