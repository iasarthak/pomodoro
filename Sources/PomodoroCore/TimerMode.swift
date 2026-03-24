import SwiftUI

// MARK: - Colors

public extension Color {
    static let pomodoroWork = Color(red: 1.0, green: 0.42, blue: 0.42)   // #FF6B6B
    static let pomodoroBreak = Color(red: 0.42, green: 0.80, blue: 0.47) // #6BCB77
}

// MARK: - Timer Mode

public enum TimerMode: String {
    case work = "Focus"
    case rest = "Break"
    case longRest = "Long Break"

    public var icon: String {
        switch self {
        case .work: "timer"
        case .rest: "cup.and.saucer.fill"
        case .longRest: "cup.and.saucer.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .work: .pomodoroWork
        case .rest, .longRest: .pomodoroBreak
        }
    }

    public var completionTitle: String {
        switch self {
        case .work: "Focus session done!"
        case .rest: "Break's over!"
        case .longRest: "Long break's over!"
        }
    }

    public var completionBody: String {
        switch self {
        case .work: "Nice work. Time for a break."
        case .rest: "Ready to focus again?"
        case .longRest: "Recharged? Let's go."
        }
    }
}
