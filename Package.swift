// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProductivityTools",
    platforms: [.macOS(.v14)],
    targets: [
        // Pomodoro
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

        // ClipStash
        .target(name: "ClipboardCore"),
        .executableTarget(
            name: "ClipStash",
            dependencies: ["ClipboardCore"]
        ),
        .executableTarget(
            name: "ClipStashTests",
            dependencies: ["ClipboardCore"],
            path: "Tests/ClipStashTests",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
    ]
)
