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

@Test func substituteDoesNotResubstituteInsertedValues() {
    #expect(Compose.substitute("{a} {b}", values: ["a": "{b}", "b": "x"]) == "{b} x")
}

// MARK: - activePlaceholders

@Test func activePlaceholdersMatchesEmittedTemplate() {
    let block = Block(
        key: "i", desc: "investigate", text: "investigate {link}",
        negative: "skip it", placeholders: ["link"])
    #expect(Compose.activePlaceholders(block, negated: false) == ["link"])
    #expect(Compose.activePlaceholders(block, negated: true) == [])
}

// A repeated name would otherwise be prompted for forever: the answers
// land in a dictionary, whose count can never reach the list's.
@Test func activePlaceholdersDedupsRepeatedNames() {
    let block = Block(key: "i", desc: "", text: "go {a}", placeholders: ["a", "a"])
    #expect(Compose.activePlaceholders(block, negated: false) == ["a"])
}

// MARK: - placeholderHints

@Test func placeholderHintsNilWithoutPlaceholders() {
    #expect(Compose.placeholderHints(Block(key: "c", desc: "commit", text: "commit")) == nil)
    #expect(
        Compose.placeholderHints(
            Block(key: "c", desc: "commit", text: "commit", placeholders: [])) == nil)
}

@Test func placeholderHintsBracketEveryName() {
    let block = Block(
        key: "i", desc: "investigate", text: "investigate {a} {b}", placeholders: ["a", "b"])
    #expect(Compose.placeholderHints(block) == "<a> <b>")
}

// MARK: - derivePlaceholders

@Test func derivePlaceholdersFindsBraceNames() {
    #expect(Compose.derivePlaceholders(text: "investigate {link}") == ["link"])
}

@Test func derivePlaceholdersNilWithoutBraces() {
    #expect(Compose.derivePlaceholders(text: "commit") == nil)
}

@Test func derivePlaceholdersDedupsInFirstAppearanceOrder() {
    #expect(Compose.derivePlaceholders(text: "{b} {a} {b}") == ["b", "a"])
}

@Test func derivePlaceholdersIncludesNegativeOnlyNames() {
    #expect(
        Compose.derivePlaceholders(text: "push {branch}", negative: "don't push {branch} to {remote}")
            == ["branch", "remote"])
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

