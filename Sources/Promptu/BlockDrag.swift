import PromptuCore
import SwiftUI

/// The ≡ icon marking a draggable row; the drag itself is attached by
/// the caller. Fills whatever height it is proposed, so an overlaid
/// grip catches clicks across the row's full height, not just the
/// icon's. When the row's height can reflow, pass `firstLine` to
/// center the icon within a top-pinned strip of that height — the
/// row's first line — where a full-height-centered icon would jump
/// with every re-measure.
struct Grip: View {
    let theme: Theme
    var firstLine: CGFloat? = nil

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption)
            .foregroundStyle(theme.dimmed)
            .padding(.horizontal, 6)
            .frame(height: firstLine)
            .frame(maxHeight: .infinity, alignment: firstLine == nil ? .center : .top)
            .contentShape(Rectangle())
    }
}

/// One list's hand-rolled reorder-drag state: the dragged row's id,
/// its gesture translation, and the rows' resting frames, frozen while
/// a drag is in flight so the layout it reasons about stays still.
/// Held as one @State per reorderable list; the Reorder geometry is
/// wrapped so callers never thread the pieces through by hand.
struct ReorderDrag {
    var draggingID: AnyHashable?
    var translation: CGFloat = 0
    var frames: [AnyHashable: CGRect] = [:]

    /// The one animation every reorder slides and settles under.
    static let settle = Animation.snappy(duration: 0.22)

    var active: Bool { draggingID != nil }

    /// Where the dragged row would land; see Reorder.target.
    func target(in order: [AnyHashable]) -> Int? {
        Reorder.target(order: order, frames: frames, dragging: draggingID, offset: translation)
    }

    /// The offset to render row `id` at; see Reorder.offset.
    func offset(of id: AnyHashable, in order: [AnyHashable], spacing: CGFloat) -> CGFloat {
        Reorder.offset(
            for: id, order: order, frames: frames, dragging: draggingID,
            dragOffset: translation, spacing: spacing)
    }

    /// Adopt newly measured row frames — unless a drag is in flight:
    /// the offsets applied to rows must not feed back into their
    /// measured positions.
    mutating func measure(_ next: [AnyHashable: CGRect]) {
        if draggingID == nil { frames = next }
    }
}

/// The reorder gesture for the row `id` of the list `order`: grabbing
/// the row updates `drag`, so it floats while the others slide to open
/// a gap; releasing maps the drop onto `move(from:to:)` — `to` in
/// Reorder.target's convention — with the settle under one animation.
@MainActor
func reorderGesture(
    _ drag: Binding<ReorderDrag>, id: AnyHashable, space: String,
    order: [AnyHashable], move: @escaping (Int, Int) -> Void
) -> some Gesture {
    DragGesture(minimumDistance: 3, coordinateSpace: .named(space))
        .onChanged { value in
            if drag.wrappedValue.draggingID == nil { drag.wrappedValue.draggingID = id }
            drag.wrappedValue.translation = value.translation.height
        }
        .onEnded { _ in
            let state = drag.wrappedValue
            withAnimation(ReorderDrag.settle) {
                if let dragged = state.draggingID, let from = order.firstIndex(of: dragged),
                    let to = state.target(in: order)
                {
                    move(from, to)
                }
                drag.wrappedValue.draggingID = nil
                drag.wrappedValue.translation = 0
            }
        }
}

/// Each row's natural (pre-offset) frame, keyed by row id, collected in
/// a named coordinate space so a drag can tell which row it is over.
struct ReorderFrameKey: PreferenceKey {
    static var defaultValue: [AnyHashable: CGRect] { [:] }
    static func reduce(
        value: inout [AnyHashable: CGRect], nextValue: () -> [AnyHashable: CGRect]
    ) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func reorderFrame(_ id: AnyHashable, in space: String) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ReorderFrameKey.self, value: [id: geo.frame(in: .named(space))])
            })
    }
}
