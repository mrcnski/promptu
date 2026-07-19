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

// MARK: - replaceAll

@Test func replaceAllStripsTheLeadingLinePrefix() {
    var c = Composition()
    c.add("a")
    c.add("b")
    c.replaceAll(with: c.composed)
    #expect(c.entries == ["a\n- b"])
    #expect(c.composed == "- a\n- b")
}

@Test func replaceAllCollapsesEntriesToOneAndUndoRestoresThem() {
    var c = Composition()
    c.add("a")
    c.add("b")
    c.pointUp()
    c.replaceAll(with: "whole new prompt")
    #expect(c.entries == ["whole new prompt"])
    #expect(c.point == nil)
    c.undo()
    #expect(c.entries == ["a", "b"])
    #expect(c.point == 1)
}

@Test func replaceAllOnEmptyIsNoop() {
    var c = Composition()
    c.replaceAll(with: "x")
    #expect(c.entries.isEmpty)
}

// MARK: - move

@Test func moveEntryForwardPutsPointPastIt() {
    var c = Composition()
    c.add("a")
    c.add("b")
    c.add("c")
    c.moveEntry(from: 0, to: 1)
    #expect(c.entries == ["b", "a", "c"])
    #expect(c.point == 2)
}

@Test func moveEntryBackwardPutsPointPastIt() {
    var c = Composition()
    c.add("a")
    c.add("b")
    c.add("c")
    c.moveEntry(from: 2, to: 0)
    #expect(c.entries == ["c", "a", "b"])
    #expect(c.point == 1)
}

@Test func moveEntryToItsOwnIndexIsNoop() {
    var c = Composition()
    c.add("a")
    c.add("b")
    c.moveEntry(from: 1, to: 1)
    #expect(c.entries == ["a", "b"])
    #expect(c.point == nil)
    c.undo()  // no-ops must not have checkpointed
    #expect(c.entries == ["a"])
}

@Test func moveEntryToTheEndLeavesPointAtEnd() {
    var c = Composition()
    c.add("a")
    c.add("b")
    c.moveEntry(from: 0, to: 1)
    #expect(c.entries == ["b", "a"])
    #expect(c.point == nil)
    c.undo()
    #expect(c.entries == ["a", "b"])
}

@Test func moveEntryOutOfRangeIsNoop() {
    var c = Composition()
    c.add("a")
    c.moveEntry(from: 0, to: 1)
    c.moveEntry(from: 1, to: 0)
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
    #expect(!c.canUndo)
    c.undo()
    #expect(c.entries.isEmpty)
    c.add("a")
    #expect(c.canUndo)
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
