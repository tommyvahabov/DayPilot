// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DayPilot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DayPilot",
            path: "Sources",
            exclude: ["MCPServer"],
            swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")]
        ),
        .executableTarget(
            name: "DayPilotMCP",
            path: "Sources/MCPServer"
        ),
        .testTarget(
            name: "DayPilotTests",
            dependencies: ["DayPilot"],
            path: "Tests"
        ),
    ]
)
