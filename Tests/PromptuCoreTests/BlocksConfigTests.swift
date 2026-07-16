import Foundation
import Testing

@testable import PromptuCore

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("promptu-bar-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func defaultBlocksJSONDecodesToPromptuDefaults() throws {
    let blocks = try JSONDecoder().decode(
        [Block].self, from: Data(BlocksConfig.defaultBlocksJSON.utf8))
    #expect(blocks.count == 10)
    #expect(blocks.map(\.key) == ["t", "i", "b", "r", "c", "T", "p", "P", "R", "C"])
    #expect(blocks[7].negative == "don't push")
    #expect(blocks[0].placeholders == ["type a command"])
}

@Test func loadOrSeedCreatesMissingFileWithDefaults() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    // Nested path: seeding also creates the parent directory.
    let file = dir.appendingPathComponent("nested/blocks.json")

    let blocks = try BlocksConfig.loadOrSeed(file)
    #expect(blocks.count == 10)
    #expect(try String(contentsOf: file, encoding: .utf8) == BlocksConfig.defaultBlocksJSON)
}

@Test func loadOrSeedLeavesExistingFileAlone() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("blocks.json")
    try Data(#"[{ "key": "x", "desc": "mine", "text": "mine" }]"#.utf8).write(to: file)

    let blocks = try BlocksConfig.loadOrSeed(file)
    #expect(blocks == [Block(key: "x", desc: "mine", text: "mine")])
}

@Test func loadOrSeedThrowsOnMalformedFileWithoutOverwriting() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("blocks.json")
    try Data("not json".utf8).write(to: file)

    #expect(throws: (any Error).self) { try BlocksConfig.loadOrSeed(file) }
    #expect(try String(contentsOf: file, encoding: .utf8) == "not json")
}
