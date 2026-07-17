import CoreGraphics

/// Pure geometry for a hand-rolled drag reorder of a vertical stack.
/// No system drag-and-drop is involved, so there is no drag snapshot
/// and none of its snap-back on drop. The rows never move in the model
/// mid-drag: their measured frames stay put, the dragged row floats by
/// the gesture translation, and the others slide to open a gap.
public enum Reorder {
    /// Where the dragged row would land, as an index into the list with
    /// the dragged row removed (0...count-1). nil when not dragging or
    /// the dragged row has not been measured.
    public static func target(
        order: [AnyHashable], frames: [AnyHashable: CGRect],
        dragging: AnyHashable?, offset: CGFloat
    ) -> Int? {
        guard let id = dragging, let from = order.firstIndex(of: id),
            let dragged = frames[id]
        else { return nil }
        let floatingMidY = dragged.midY + offset
        var index = 0
        for (i, other) in order.enumerated()
        where i != from && (frames[other]?.midY ?? .infinity) < floatingMidY {
            index += 1
        }
        return index
    }

    /// The vertical offset to render row `id` at during a drag: the
    /// dragged row follows the gesture; the rest open a gap for it.
    public static func offset(
        for id: AnyHashable, order: [AnyHashable], frames: [AnyHashable: CGRect],
        dragging: AnyHashable?, dragOffset: CGFloat, spacing: CGFloat
    ) -> CGFloat {
        guard let draggedID = dragging, let from = order.firstIndex(of: draggedID)
        else { return 0 }
        if id == draggedID { return dragOffset }
        guard
            let to = target(
                order: order, frames: frames, dragging: dragging, offset: dragOffset),
            let height = frames[draggedID]?.height, let i = order.firstIndex(of: id)
        else { return 0 }
        let slot = height + spacing
        // Filling the dragged row's vacated slot pulls later rows up;
        // opening the gap at the target pushes rows there and after down.
        let fill: CGFloat = i > from ? -slot : 0
        let positionWithoutDragged = i < from ? i : i - 1
        let open: CGFloat = positionWithoutDragged >= to ? slot : 0
        return fill + open
    }
}
