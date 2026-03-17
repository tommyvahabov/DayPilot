// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DayPilot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DayPilot",
            path: "Sources",
            swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")]
        ),
        .testTarget(
            name: "DayPilotTests",
            dependencies: ["DayPilot"],
            path: "Tests"
        ),
    ]
)
