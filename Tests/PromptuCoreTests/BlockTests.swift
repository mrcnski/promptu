import Testing

@testable import PromptuCore

// MARK: - moving(_:over:)

private let blocks = [
    Block(key: "a", desc: "", text: "A"),
    Block(key: "b", desc: "", text: "B"),
    Block(key: "c", desc: "", text: "C"),
]

@Test func movingForwardTakesTargetSlot() {
    #expect(blocks.moving("a", over: "c").map(\.key) == ["b", "c", "a"])
}

@Test func movingBackwardTakesTargetSlot() {
    #expect(blocks.moving("c", over: "a").map(\.key) == ["c", "a", "b"])
}

@Test func movingAdjacentSwaps() {
    #expect(blocks.moving("a", over: "b").map(\.key) == ["b", "a", "c"])
    #expect(blocks.moving("b", over: "a").map(\.key) == ["b", "a", "c"])
}

@Test func movingOverItselfChangesNothing() {
    #expect(blocks.moving("b", over: "b") == blocks)
}

@Test func movingUnknownKeyChangesNothing() {
    #expect(blocks.moving("x", over: "a") == blocks)
    #expect(blocks.moving("a", over: "x") == blocks)
}
