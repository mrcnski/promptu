// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "promptu",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PromptuCore"),
        .executableTarget(name: "Promptu", dependencies: ["PromptuCore"]),
        .testTarget(name: "PromptuCoreTests", dependencies: ["PromptuCore"]),
    ]
)
