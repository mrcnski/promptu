import Testing

@testable import PromptuCore

@Test func recordsNewestFirst() {
    var history = History()
    history.record(["one"])
    history.record(["two"])
    #expect(history.prompts == [["two"], ["one"]])
}

/// Copying the same prompt again must move it, not duplicate it —
/// reuse is the common case and would otherwise crowd the list out.
@Test func recordMovesARepeatToTheFront() {
    var history = History([["one"], ["two"], ["three"]])
    history.record(["three"])
    #expect(history.prompts == [["three"], ["one"], ["two"]])
    #expect(history.count == 3)
}

/// A prompt differing only in one entry is a different prompt.
@Test func recordKeepsNearlyIdenticalPrompts() {
    var history = History()
    history.record(["a", "b"])
    history.record(["a", "c"])
    #expect(history.count == 2)
}

@Test func recordIgnoresAnEmptyPrompt() {
    var history = History()
    history.record([])
    #expect(history.isEmpty)
}

@Test func recordDropsTheOldestPastTheLimit() {
    var history = History()
    for i in 0...History.limit {
        history.record(["prompt \(i)"])
    }
    #expect(history.count == History.limit)
    #expect(history.prompts.first == ["prompt \(History.limit)"])
    #expect(history.prompts.last == ["prompt 1"])
}

/// An oversized stored list (hand-edited, or written by a build with a
/// larger limit) is trimmed on the way in.
@Test func initTrimsToTheLimit() {
    let stored = (0..<(History.limit + 10)).map { ["prompt \($0)"] }
    #expect(History(stored).count == History.limit)
}

@Test func removeDropsOnePrompt() {
    var history = History([["one"], ["two"], ["three"]])
    history.remove(at: 1)
    #expect(history.prompts == [["one"], ["three"]])
}

@Test func removeIgnoresAnOutOfRangeIndex() {
    var history = History([["one"]])
    history.remove(at: 5)
    history.remove(at: -1)
    #expect(history.count == 1)
}

@Test func clearEmptiesTheList() {
    var history = History([["one"], ["two"]])
    history.clear()
    #expect(history.isEmpty)
}

@Test func summaryJoinsEntries() {
    #expect(History.summary(["one", "two"]) == "one · two")
}

/// A row must stay one line: a wrapped row would resize the panel as
/// the selection moved over it.
@Test func summaryFlattensNewlines() {
    #expect(History.summary(["one\ntwo", "three"]) == "one two · three")
}

/// The rows color entries and separators separately, so they flatten
/// each entry on its own — it must do to one entry what summary does
/// to the whole prompt.
@Test func flattenCollapsesNewlinesInOneEntry() {
    #expect(History.flatten("one\ntwo") == "one two")
}
