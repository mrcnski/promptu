import Testing

@testable import PromptuCore

// MARK: - point

@Test func pointStartsAtEndAndAddsAppend() {
    var c = Composition()
    c.add("a")
    c.add("b")
    #expect(c.entries == ["a", "b"])
    #expect(c.point == nil)
}

@Test func addInsertsAtPointAndAdvancesPastIt() {
    var c = Composition()
    c.add("a")
    c.add("b")
    c.pointUp()
    c.pointUp()  // gap 0, before "a"
    c.add("c")
    #expect(c.entries == ["c", "a", "b"])
    #expect(c.point == 1)
}

@Test func pointClampsAtBothEnds() {
    var c = Composition()
    c.add("a")
    c.pointUp()
    c.pointUp()
    #expect(c.point == 0)
    c.pointDown()
    c.pointDown()
    #expect(c.point == nil)
}

// MARK: - remove

@Test func removeTakesEntryAboveThePoint() {
    var c = Composition()
    c.add("a")
    c.add("b")
    c.add("c")
    c.pointUp()  // gap 2, above = "b"
    c.removeEntry()
    #expect(c.entries == ["a", "c"])
    #expect(c.point == 1)
}

@Test func removeAtStartIsNoop() {
    var c = Composition()
    c.add("a")
    c.pointUp()  // gap 0, nothing above
    c.removeEntry()
    #expect(c.entries == ["a"])
}

@Test func removeLastEntryLeavesPointAtEnd() {
    var c = Composition()
    c.add("a")
    c.removeEntry()
    #expect(c.entries.isEmpty)
    #expect(c.point == nil)
}

// MARK: - replace

@Test func replaceActsOnEntryAboveThePoint() {
    var c = Composition()
    c.add("a")
    c.add("b")
    c.pointUp()  // above = "a"
    c.replaceEntry(with: "edited")
    #expect(c.entries == ["edited", "b"])
}

@Test func replaceAtStartIsNoop() {
    var c = Composition()
    c.add("a")
    c.pointUp()
    c.replaceEntry(with: "edited")
    #expect(c.entries == ["a"])
}

// MARK: - undo/redo

@Test func undoRevertsLastChangeIncludingPoint() {
    var c = Composition()
    c.add("a")
    c.add("b")
    c.pointUp()
    c.removeEntry()
    c.undo()
    #expect(c.entries == ["a", "b"])
    #expect(c.point == 1)
}

@Test func redoReappliesUndoneChange() {
    var c = Composition()
    c.add("a")
    c.undo()
    #expect(c.entries.isEmpty)
    c.redo()
    #expect(c.entries == ["a"])
}

@Test func newChangeClearsRedo() {
    var c = Composition()
    c.add("a")
    c.undo()
    c.add("b")
    c.redo()  // nothing to redo anymore
    #expect(c.entries == ["b"])
}

@Test func undoOnFreshCompositionIsNoop() {
    var c = Composition()
    c.undo()
    #expect(c.entries.isEmpty)
}

// MARK: - preview

@Test func previewWithoutMovedPointHasNoMarker() {
    var c = Composition()
    c.add("a")
    c.add("b")
    #expect(c.preview == "- a\n- b")
}

@Test func previewShowsMarkerOnOwnLineAtGap() {
    var c = Composition()
    c.add("a")
    c.add("b")
    c.pointUp()
    #expect(c.preview == "- a\n▮\n- b")
}

@Test func previewShowsMarkerBeforeFirstEntryAtGapZero() {
    var c = Composition()
    c.add("a")
    c.pointUp()
    #expect(c.preview == "▮\n- a")
}

// MARK: - previewLines

@Test func previewLinesCarryEachEntrysSlotAsDropGap() {
    var c = Composition()
    c.add("a")
    c.add("b")
    #expect(c.previewLines.map(\.text) == ["- a", "- b"])
    #expect(c.previewLines.map(\.gap) == [0, 1])
}

@Test func previewLinesGiveMarkerLineThePointGap() {
    var c = Composition()
    c.add("a")
    c.add("b")
    c.pointUp()
    #expect(c.previewLines.map(\.text) == ["- a", "▮", "- b"])
    #expect(c.previewLines.map(\.gap) == [0, 1, 1])
}

@Test func previewLinesKeepMultilineEntryOnOneSlot() {
    var c = Composition()
    c.add("a\nb")
    c.add("c")
    #expect(c.previewLines.map(\.text) == ["- a", "b", "- c"])
    #expect(c.previewLines.map(\.gap) == [0, 0, 1])
}
