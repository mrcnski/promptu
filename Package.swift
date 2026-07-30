// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "promptu",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PromptuCore"),
        .executableTarget(
            name: "Promptu",
            dependencies: ["PromptuCore"],
            linkerSettings: [
                // Embed Info.plist into the bare executable, so `swift
                // run` builds know who they are: without it they fall
                // into a separate "Promptu" preferences domain (a
                // split-brain against the app bundle's settings and
                // history) and report version "dev", which reads as 0
                // and flags every release as an update.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist",
                ])
            ]),
        .testTarget(name: "PromptuCoreTests", dependencies: ["PromptuCore"]),
    ]
)
