// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "promptu-bar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PromptuCore"),
        .executableTarget(name: "PromptuBar", dependencies: ["PromptuCore"]),
        .testTarget(name: "PromptuCoreTests", dependencies: ["PromptuCore"]),
    ]
)
