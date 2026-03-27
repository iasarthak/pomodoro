import Foundation
import Combine

@MainActor
public class ClipboardHistory: ObservableObject {
    @Published public var items: [ClipItem] = []

    public var now: () -> Date = { Date() }

    public static let maxItems = 50
    public static let frequentThreshold = 3
    public static let maxFrequentItems = 8
    private static let decayIntervalDays = 7

    private let storageURL: URL
    private var saveTask: Task<Void, Never>?

    /// Standard init — loads from disk
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ClipStash", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("history.json")
        load()
        decayIfNeeded()
    }

    /// Test init — no disk persistence
    public init(testMode: Bool) {
        storageURL = URL(fileURLWithPath: "/dev/null")
    }

    // MARK: - Frequent Items

    public var frequentItems: [ClipItem] {
        items
            .filter { $0.content.isText && $0.copyCount >= Self.frequentThreshold }
            .sorted { $0.copyCount > $1.copyCount }
            .prefix(Self.maxFrequentItems)
            .map { $0 }
    }

    private func isFrequent(_ item: ClipItem) -> Bool {
        item.content.isText && item.copyCount >= Self.frequentThreshold
    }

    // MARK: - Add / Remove

    public func addItem(content: ClipContent, sourceApp: String? = nil) {
        let timestamp = now()

        // Dedup text: if most recent text item matches, increment count
        if case .text(let newText) = content,
           let firstIndex = items.firstIndex(where: {
               if case .text(let existing) = $0.content { return existing == newText }
               return false
           }) {
            items[firstIndex].copyCount += 1
            items[firstIndex].lastCopied = timestamp
            // Move to front
            let item = items.remove(at: firstIndex)
            items.insert(item, at: 0)
            scheduleSave()
            return
        }

        let item = ClipItem(
            content: content,
            firstCopied: timestamp,
            lastCopied: timestamp,
            sourceApp: sourceApp
        )
        items.insert(item, at: 0)

        // Enforce cap — evict oldest non-frequent
        while items.count > Self.maxItems {
            if let evictIndex = items.lastIndex(where: { !isFrequent($0) }) {
                items.remove(at: evictIndex)
            } else {
                // All items are frequent (unlikely) — drop the last one
                items.removeLast()
            }
        }

        scheduleSave()
    }

    public func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
        scheduleSave()
    }

    // MARK: - Search

    public func search(query: String) -> [ClipItem] {
        guard !query.isEmpty else { return items }
        let q = query.lowercased()
        return items.filter { item in
            if let text = item.content.textValue, text.lowercased().contains(q) {
                return true
            }
            if let app = item.sourceApp, app.lowercased().contains(q) {
                return true
            }
            return false
        }
    }

    // MARK: - Frequency Decay

    public func decayIfNeeded() {
        let defaults = UserDefaults.standard
        let lastDecay = defaults.object(forKey: "clipstash.lastDecayDate") as? Date ?? Date.distantPast
        let daysSince = Calendar.current.dateComponents([.day], from: lastDecay, to: now()).day ?? 0

        guard daysSince >= Self.decayIntervalDays else { return }

        for i in items.indices {
            items[i].copyCount = max(1, items[i].copyCount / 2)
        }
        defaults.set(now(), forKey: "clipstash.lastDecayDate")
        scheduleSave()
    }

    /// Force decay — exposed for testing
    public func forceDecay() {
        for i in items.indices {
            items[i].copyCount = max(1, items[i].copyCount / 2)
        }
    }

    // MARK: - Persistence

    public func save() {
        guard storageURL.path != "/dev/null" else { return }
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Silent fail — clipboard history is not critical data
        }
    }

    public func load() {
        guard storageURL.path != "/dev/null" else { return }
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            items = try JSONDecoder().decode([ClipItem].self, from: data)
        } catch {
            items = []
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    // MARK: - Test Helpers

    /// Encode items to JSON data for round-trip testing
    public func encodeItems() throws -> Data {
        try JSONEncoder().encode(items)
    }

    /// Decode items from JSON data for round-trip testing
    public func decodeItems(from data: Data) throws {
        items = try JSONDecoder().decode([ClipItem].self, from: data)
    }
}
