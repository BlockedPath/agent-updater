// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgentUpdater",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "AgentUpdater",
            path: "Sources/AgentUpdater",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
