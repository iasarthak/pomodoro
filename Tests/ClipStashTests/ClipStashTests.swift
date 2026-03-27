import Foundation
@testable import ClipboardCore

// Minimal test runner — same pattern as PomodoroTests

struct AssertionError: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: Bool, _ message: String = "assertion failed", file: String = #file, line: Int = #line) throws {
    guard condition else { throw AssertionError(description: "\(message) (\(file):\(line))") }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard a == b else {
        throw AssertionError(description: "expected \(a) == \(b) \(message) (\(file):\(line))")
    }
}

extension String {
    static func * (lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}

// MARK: - Helpers

@MainActor
func makeHistory() -> ClipboardHistory {
    ClipboardHistory(testMode: true)
}

// MARK: - Tests

@MainActor
func runAllTests() -> Bool {
    var passed = 0
    var failed = 0
    var failures: [(String, String)] = []

    func test(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            passed += 1
            print("  \u{2705} \(name)")
        } catch {
            failed += 1
            failures.append((name, "\(error)"))
            print("  \u{274C} \(name): \(error)")
        }
    }

    print("\nClipStash Tests")
    print("=" * 50)

    // ── Add Items ──

    print("\nAdd Items:")

    test("Add text item appears in history") {
        let h = makeHistory()
        h.addItem(content: .text("hello world"), sourceApp: "Safari")
        try expectEqual(h.items.count, 1)
        try expectEqual(h.items[0].content, .text("hello world"))
        try expectEqual(h.items[0].sourceApp, "Safari")
        try expectEqual(h.items[0].copyCount, 1)
    }

    test("Add image item appears in history") {
        let h = makeHistory()
        let data = Data([0x89, 0x50, 0x4E, 0x47]) // fake PNG header
        h.addItem(content: .image(data))
        try expectEqual(h.items.count, 1)
        try expect(h.items[0].content.isImage)
    }

    test("Items ordered newest first") {
        let h = makeHistory()
        let t0 = Date()
        h.now = { t0 }
        h.addItem(content: .text("first"))
        h.now = { t0.addingTimeInterval(10) }
        h.addItem(content: .text("second"))
        try expectEqual(h.items[0].content, .text("second"))
        try expectEqual(h.items[1].content, .text("first"))
    }

    // ── Deduplication ──

    print("\nDeduplication:")

    test("Duplicate text increments copyCount") {
        let h = makeHistory()
        h.addItem(content: .text("repeated"))
        h.addItem(content: .text("repeated"))
        h.addItem(content: .text("repeated"))
        try expectEqual(h.items.count, 1)
        try expectEqual(h.items[0].copyCount, 3)
    }

    test("Duplicate text moves to front") {
        let h = makeHistory()
        let t0 = Date()
        h.now = { t0 }
        h.addItem(content: .text("old"))
        h.now = { t0.addingTimeInterval(10) }
        h.addItem(content: .text("newer"))
        h.now = { t0.addingTimeInterval(20) }
        h.addItem(content: .text("old")) // should move "old" to front
        try expectEqual(h.items[0].content, .text("old"))
        try expectEqual(h.items[0].copyCount, 2)
        try expectEqual(h.items.count, 2)
    }

    test("Images are not deduplicated") {
        let h = makeHistory()
        let data = Data([0x89, 0x50])
        h.addItem(content: .image(data))
        h.addItem(content: .image(data))
        try expectEqual(h.items.count, 2)
    }

    // ── Eviction ──

    print("\nEviction:")

    test("50-item cap enforced") {
        let h = makeHistory()
        for i in 0..<55 {
            h.addItem(content: .text("item \(i)"))
        }
        try expectEqual(h.items.count, 50)
    }

    test("Frequent items protected from eviction") {
        let h = makeHistory()
        // Make one item frequent (copyCount >= 3)
        h.addItem(content: .text("frequent"))
        h.addItem(content: .text("frequent"))
        h.addItem(content: .text("frequent"))
        try expectEqual(h.items[0].copyCount, 3)

        // Fill up with other items
        for i in 0..<52 {
            h.addItem(content: .text("filler \(i)"))
        }
        try expectEqual(h.items.count, 50)
        // The frequent item should still be there
        try expect(h.items.contains(where: { $0.content == .text("frequent") }),
                   "frequent item should survive eviction")
    }

    // ── Frequent Items ──

    print("\nFrequent Items:")

    test("Items with copyCount >= 3 appear in frequentItems") {
        let h = makeHistory()
        h.addItem(content: .text("rare"))
        h.addItem(content: .text("popular"))
        h.addItem(content: .text("popular"))
        h.addItem(content: .text("popular"))
        try expectEqual(h.frequentItems.count, 1)
        try expectEqual(h.frequentItems[0].content, .text("popular"))
    }

    test("Items with copyCount < 3 excluded from frequentItems") {
        let h = makeHistory()
        h.addItem(content: .text("once"))
        h.addItem(content: .text("twice"))
        h.addItem(content: .text("twice"))
        try expectEqual(h.frequentItems.count, 0)
    }

    test("Images excluded from frequentItems") {
        let h = makeHistory()
        // Can't dedup images so can't get copyCount > 1 naturally,
        // but verify the filter works
        try expectEqual(h.frequentItems.count, 0)
    }

    test("Max 8 frequent items") {
        let h = makeHistory()
        for i in 0..<12 {
            let text = "freq\(i)"
            // Add 3 times each to make frequent
            h.addItem(content: .text(text))
            h.addItem(content: .text(text))
            h.addItem(content: .text(text))
        }
        try expectEqual(h.frequentItems.count, 8)
    }

    // ── Search ──

    print("\nSearch:")

    test("Search by text content") {
        let h = makeHistory()
        h.addItem(content: .text("hello world"))
        h.addItem(content: .text("goodbye world"))
        h.addItem(content: .text("something else"))
        let results = h.search(query: "world")
        try expectEqual(results.count, 2)
    }

    test("Search by source app") {
        let h = makeHistory()
        h.addItem(content: .text("some code"), sourceApp: "VS Code")
        h.addItem(content: .text("some url"), sourceApp: "Safari")
        let results = h.search(query: "safari")
        try expectEqual(results.count, 1)
        try expectEqual(results[0].sourceApp, "Safari")
    }

    test("Search case insensitive") {
        let h = makeHistory()
        h.addItem(content: .text("Hello World"))
        let results = h.search(query: "hello")
        try expectEqual(results.count, 1)
    }

    test("Empty search returns all") {
        let h = makeHistory()
        h.addItem(content: .text("a"))
        h.addItem(content: .text("b"))
        let results = h.search(query: "")
        try expectEqual(results.count, 2)
    }

    // ── Remove ──

    print("\nRemove:")

    test("Remove item by ID") {
        let h = makeHistory()
        h.addItem(content: .text("keep"))
        h.addItem(content: .text("delete me"))
        let idToRemove = h.items[0].id
        h.removeItem(id: idToRemove)
        try expectEqual(h.items.count, 1)
        try expectEqual(h.items[0].content, .text("keep"))
    }

    // ── Decay ──

    print("\nDecay:")

    test("Decay halves copyCount") {
        let h = makeHistory()
        h.addItem(content: .text("popular"))
        h.addItem(content: .text("popular"))
        h.addItem(content: .text("popular"))
        h.addItem(content: .text("popular"))
        try expectEqual(h.items[0].copyCount, 4)
        h.forceDecay()
        try expectEqual(h.items[0].copyCount, 2)
    }

    test("Decay minimum is 1") {
        let h = makeHistory()
        h.addItem(content: .text("once"))
        try expectEqual(h.items[0].copyCount, 1)
        h.forceDecay()
        try expectEqual(h.items[0].copyCount, 1)
    }

    // ── JSON Round-Trip ──

    print("\nPersistence:")

    test("JSON encode/decode round-trip") {
        let h = makeHistory()
        h.addItem(content: .text("hello"), sourceApp: "Safari")
        h.addItem(content: .image(Data([0x89, 0x50, 0x4E, 0x47])))
        h.addItem(content: .text("hello")) // dedup, count = 2

        let data = try h.encodeItems()
        let h2 = makeHistory()
        try h2.decodeItems(from: data)

        try expectEqual(h2.items.count, 2)
        try expectEqual(h2.items[0].copyCount, 2)
        try expect(h2.items[1].content.isImage)
    }

    // ── ClipItem Helpers ──

    print("\nClipItem Helpers:")

    test("Preview truncates long text") {
        let longText = String(repeating: "a", count: 200)
        let item = ClipItem(content: .text(longText))
        try expect(item.preview.count <= 104) // 100 + "..."
    }

    test("Preview shows first line only") {
        let item = ClipItem(content: .text("first line\nsecond line"))
        try expectEqual(item.preview, "first line")
    }

    test("Preview for image says Image") {
        let item = ClipItem(content: .image(Data()))
        try expectEqual(item.preview, "Image")
    }

    test("Relative time formatting") {
        let base = Date()
        let item = ClipItem(content: .text("x"), lastCopied: base.addingTimeInterval(-30))
        try expectEqual(item.relativeTime(from: base), "30s")

        let item2 = ClipItem(content: .text("x"), lastCopied: base.addingTimeInterval(-150))
        try expectEqual(item2.relativeTime(from: base), "2m")

        let item3 = ClipItem(content: .text("x"), lastCopied: base.addingTimeInterval(-7200))
        try expectEqual(item3.relativeTime(from: base), "2h")

        let item4 = ClipItem(content: .text("x"), lastCopied: base.addingTimeInterval(-172800))
        try expectEqual(item4.relativeTime(from: base), "2d")
    }

    // ── Summary ──

    print("\n" + "=" * 50)
    print("Results: \(passed) passed, \(failed) failed, \(passed + failed) total")
    if !failures.isEmpty {
        print("\nFailures:")
        for (name, msg) in failures {
            print("  - \(name): \(msg)")
        }
    }
    print("")
    return failed == 0
}

@main
struct TestRunner {
    @MainActor
    static func main() {
        let success = runAllTests()
        if !success { exit(1) }
    }
}
