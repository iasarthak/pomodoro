import SwiftUI
import Foundation

public class PomodoroSettings: ObservableObject {
    @AppStorage("workMinutes") public var workMinutes = 50
    @AppStorage("breakMinutes") public var breakMinutes = 10
    @AppStorage("longBreakMinutes") public var longBreakMinutes = 20
    @AppStorage("longBreakInterval") public var longBreakInterval = 4
    @AppStorage("autoStartBreaks") public var autoStartBreaks = false
    @AppStorage("autoStartWork") public var autoStartWork = false
    @AppStorage("soundName") public var soundName = "Purr"

    public static let availableSounds = ["Purr", "Ping", "Pop", "Blow", "Glass", "Hero", "Submarine", "Tink"]

    public var workDuration: TimeInterval { TimeInterval(workMinutes * 60) }
    public var breakDuration: TimeInterval { TimeInterval(breakMinutes * 60) }
    public var longBreakDuration: TimeInterval { TimeInterval(longBreakMinutes * 60) }

    public init() {}

    /// Test-friendly initializer with custom values
    public init(work: Int = 50, brk: Int = 10, longBrk: Int = 20, interval: Int = 4,
                autoBreaks: Bool = false, autoWork: Bool = false) {
        // Can't set @AppStorage in init directly, so set after
        _workMinutes = AppStorage(wrappedValue: work, "workMinutes")
        _breakMinutes = AppStorage(wrappedValue: brk, "breakMinutes")
        _longBreakMinutes = AppStorage(wrappedValue: longBrk, "longBreakMinutes")
        _longBreakInterval = AppStorage(wrappedValue: interval, "longBreakInterval")
        _autoStartBreaks = AppStorage(wrappedValue: autoBreaks, "autoStartBreaks")
        _autoStartWork = AppStorage(wrappedValue: autoWork, "autoStartWork")
    }
}
