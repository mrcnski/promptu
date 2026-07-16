import Foundation
import Testing

@testable import PromptuCore

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("promptu-app-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func decodeSharedConfigSchema() throws {
    let json = """
        [
          { "key": "P", "desc": "push", "text": "push when done", "negative": "don't push" },
          { "key": "i", "desc": "investigate", "text": "investigate {link}",
            "placeholders": ["link"] }
        ]
        """
    let blocks = try JSONDecoder().decode([Block].self, from: Data(json.utf8))
    #expect(blocks.count == 2)
    #expect(blocks[0].negative == "don't push")
    #expect(blocks[0].placeholders == nil)
    #expect(blocks[1].placeholders == ["link"])
    #expect(blocks[1].negative == nil)
}

@Test func loadReadsFileFromDisk() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("blocks.json")
    try Data(#"[{ "key": "c", "desc": "commit", "text": "commit" }]"#.utf8).write(to: file)

    let blocks = try BlocksConfig.load(file)
    #expect(blocks == [Block(key: "c", desc: "commit", text: "commit")])
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

@Test func serializeReproducesTheDefaultBlocksJSON() throws {
    let blocks = try JSONDecoder().decode(
        [Block].self, from: Data(BlocksConfig.defaultBlocksJSON.utf8))
    #expect(BlocksConfig.serialize(blocks) == BlocksConfig.defaultBlocksJSON)
}

@Test func saveRoundtripsBlocksWithSpecialCharacters() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("blocks.json")
    let blocks = [
        Block(
            key: "x", desc: "say \"hi\"", text: "line\nbreak\tand \\slash",
            negative: "don't", placeholders: ["a", "b"])
    ]

    try BlocksConfig.save(blocks, to: file)
    #expect(try BlocksConfig.load(file) == blocks)
}

@Test func loadOrSeedThrowsOnMalformedFileWithoutOverwriting() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("blocks.json")
    try Data("not json".utf8).write(to: file)

    #expect(throws: (any Error).self) { try BlocksConfig.loadOrSeed(file) }
    #expect(try String(contentsOf: file, encoding: .utf8) == "not json")
}
