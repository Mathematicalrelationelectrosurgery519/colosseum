// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Colosseum",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Colosseum",
            path: "Sources/Colosseum",
            resources: [.process("Resources")]
        )
    ]
)
