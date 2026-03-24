// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pomodoro",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "PomodoroCore"),
        .executableTarget(
            name: "Pomodoro",
            dependencies: ["PomodoroCore"],
            exclude: ["AppIcon.icns"]
        ),
        .executableTarget(
            name: "PomodoroTests",
            dependencies: ["PomodoroCore"],
            path: "Tests/PomodoroTests",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
    ]
)
