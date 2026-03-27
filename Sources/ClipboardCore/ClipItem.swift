import Foundation

public enum ClipContent: Codable, Equatable {
    case text(String)
    case image(Data)

    public var isText: Bool {
        if case .text = self { return true }
        return false
    }

    public var isImage: Bool {
        if case .image = self { return true }
        return false
    }

    public var textValue: String? {
        if case .text(let s) = self { return s }
        return nil
    }
}

public struct ClipItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public var content: ClipContent
    public var copyCount: Int
    public var firstCopied: Date
    public var lastCopied: Date
    public var sourceApp: String?

    public init(
        id: UUID = UUID(),
        content: ClipContent,
        copyCount: Int = 1,
        firstCopied: Date = Date(),
        lastCopied: Date = Date(),
        sourceApp: String? = nil
    ) {
        self.id = id
        self.content = content
        self.copyCount = copyCount
        self.firstCopied = firstCopied
        self.lastCopied = lastCopied
        self.sourceApp = sourceApp
    }

    public var preview: String {
        switch content {
        case .text(let s):
            let firstLine = s.components(separatedBy: .newlines).first ?? s
            if firstLine.count > 100 {
                return String(firstLine.prefix(100)) + "..."
            }
            return firstLine
        case .image:
            return "Image"
        }
    }

    /// Relative timestamp string (e.g. "3s", "2m", "1h", "3d")
    public func relativeTime(from now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(lastCopied))
        if seconds < 60 { return "\(max(seconds, 1))s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}
