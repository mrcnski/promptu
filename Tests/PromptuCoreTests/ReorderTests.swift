import CoreGraphics
import Testing

@testable import PromptuCore

// Three rows, 20pt tall, stacked from y=0 with no spacing: midYs at 10,
// 30, 50. IDs are their letters.
private var order: [AnyHashable] { ["a", "b", "c"] }
private var frames: [AnyHashable: CGRect] {
    [
        "a": CGRect(x: 0, y: 0, width: 100, height: 20),
        "b": CGRect(x: 0, y: 20, width: 100, height: 20),
        "c": CGRect(x: 0, y: 40, width: 100, height: 20),
    ]
}

// MARK: - target

@Test func targetIsNilWhenNothingIsDragging() {
    #expect(Reorder.target(order: order, frames: frames, dragging: nil, offset: 0) == nil)
}

@Test func targetStaysPutForASmallOffset() {
    // "a" nudged down 5pt: floating midY 15, still below "b"'s 30.
    #expect(Reorder.target(order: order, frames: frames, dragging: "a", offset: 5) == 0)
}

@Test func targetAdvancesPastEachCrossedMidpoint() {
    // "a" dragged down past "b"'s midpoint (30) but not "c"'s (50).
    #expect(Reorder.target(order: order, frames: frames, dragging: "a", offset: 25) == 1)
    // ...and past "c"'s midpoint too: lands at the end.
    #expect(Reorder.target(order: order, frames: frames, dragging: "a", offset: 45) == 2)
}

@Test func targetMovesBackwardWhenDraggedUp() {
    // "c" dragged up past "a"'s midpoint: lands first.
    #expect(Reorder.target(order: order, frames: frames, dragging: "c", offset: -45) == 0)
}

// MARK: - offset

@Test func draggedRowFollowsTheGesture() {
    #expect(
        Reorder.offset(
            for: "a", order: order, frames: frames, dragging: "a", dragOffset: 17, spacing: 0)
            == 17)
}

@Test func restingRowsDoNotMoveWhenNothingIsDragging() {
    for id in order {
        #expect(
            Reorder.offset(
                for: id, order: order, frames: frames, dragging: nil, dragOffset: 0, spacing: 0)
                == 0)
    }
}

@Test func othersOpenAGapAsTheDraggedRowCrossesThem() {
    // "a" dragged to the end (past both midpoints): "b" and "c" each
    // slide up one 20pt slot to close "a"'s vacated spot.
    #expect(offsetFor("b", dragging: "a", dragOffset: 45) == -20)
    #expect(offsetFor("c", dragging: "a", dragOffset: 45) == -20)
}

@Test func onlyRowsBetweenSourceAndTargetShift() {
    // "a" dropped between "b" and "c": "b" fills "a"'s spot (up 20),
    // "c" keeps its place.
    #expect(offsetFor("b", dragging: "a", dragOffset: 25) == -20)
    #expect(offsetFor("c", dragging: "a", dragOffset: 25) == 0)
}

@Test func draggingUpwardPushesRowsDown() {
    // "c" dragged up above "a": both "a" and "b" open a gap downward.
    #expect(offsetFor("a", dragging: "c", dragOffset: -45) == 20)
    #expect(offsetFor("b", dragging: "c", dragOffset: -45) == 20)
}

private func offsetFor(
    _ id: AnyHashable, dragging: AnyHashable, dragOffset: CGFloat
) -> CGFloat {
    Reorder.offset(
        for: id, order: order, frames: frames, dragging: dragging,
        dragOffset: dragOffset, spacing: 0)
}

// MARK: - follow

@Test func followRidesAlongWithTheSelectedRow() {
    #expect(Reorder.follow(selection: 1, from: 1, to: 3) == 3)
}

@Test func followShiftsAsideWhenARowCrossesTheSelection() {
    // A row pulled from above the selection and dropped below it:
    // everything above slides up one, the selection with it.
    #expect(Reorder.follow(selection: 2, from: 0, to: 3) == 1)
    // And the mirror: pulled from below, dropped above.
    #expect(Reorder.follow(selection: 2, from: 4, to: 0) == 3)
}

@Test func followIgnoresAMoveOnOneSideOfTheSelection() {
    #expect(Reorder.follow(selection: 3, from: 0, to: 1) == 3)
    #expect(Reorder.follow(selection: 0, from: 2, to: 4) == 0)
}
