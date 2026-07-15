import Foundation
import Testing

@testable import PromptuCore

// MARK: - resolve

@Test func resolveAffirmative() {
    let block = Block(key: "p", desc: "push", text: "push when done")
    #expect(Compose.resolve(block, negated: false) == "push when done")
}

@Test func resolveNegatedWithoutExplicitNegative() {
    let block = Block(key: "p", desc: "push", text: "push when done")
    #expect(Compose.resolve(block, negated: true) == "don't push when done")
}

@Test func resolveNegatedWithExplicitNegative() {
    let block = Block(key: "p", desc: "push", text: "push when done", negative: "don't push")
    #expect(Compose.resolve(block, negated: true) == "don't push")
}

// MARK: - substitute

@Test func substituteSinglePlaceholder() {
    #expect(
        Compose.substitute(
            "investigate {link}", values: ["link": "https://example.com/issue/42"])
            == "investigate https://example.com/issue/42")
}

@Test func substituteMultipleOccurrences() {
    #expect(
        Compose.substitute("{a} and {a} and {b}", values: ["a": "x", "b": "y"])
            == "x and x and y")
}

@Test func substituteLeavesUnknownBracesAlone() {
    #expect(Compose.substitute("keep {this}", values: [:]) == "keep {this}")
}

// MARK: - activePlaceholders

@Test func activePlaceholdersMatchesEmittedTemplate() {
    let block = Block(
        key: "i", desc: "investigate", text: "investigate {link}",
        negative: "skip it", placeholders: ["link"])
    #expect(Compose.activePlaceholders(block, negated: false) == ["link"])
    #expect(Compose.activePlaceholders(block, negated: true) == [])
}

// MARK: - compose

@Test func composeEmptyIsEmpty() {
    #expect(Compose.compose([]) == "")
}

@Test func composeBulletsEveryEntry() {
    #expect(Compose.compose(["a", "b"]) == "- a\n- b")
}

@Test func composeSeparatorWithoutNewlineHasNoPrefix() {
    #expect(Compose.compose(["a", "b"], separator: ", ") == "a, b")
}

// MARK: - blocks.json decoding

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
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("promptu-bar-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("blocks.json")
    try Data(#"[{ "key": "c", "desc": "commit", "text": "commit" }]"#.utf8).write(to: file)

    let blocks = try BlocksConfig.load(file)
    #expect(blocks == [Block(key: "c", desc: "commit", text: "commit")])
}
