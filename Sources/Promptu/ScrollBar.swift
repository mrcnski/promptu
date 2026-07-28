import SwiftUI

/// Geometry shared between a scroll view and its bar: the content's
/// frame in scroll space, and the viewport's height. Held by the view
/// that owns the scroll view, because measuring it takes two observers
/// in two places: the content reports its frame, the scroll view its
/// height.
struct ScrollBarState: Equatable {
    var content: CGRect = .zero
    var viewport: CGFloat = 0
}

/// A hand-drawn scroll bar in a gutter the content reserves
/// permanently, standing in for the system indicator on the panel's
/// scroll views.
///
/// The system indicator can't keep these rows still: a legacy scroller
/// (a mouse, or "always" in System Settings) carves its gutter out of
/// the content only once it overflows, narrowing the rows and jerking
/// their trailing edge sideways — and an overlay scroller shows nothing
/// until mid-scroll. Reserving the gutter unconditionally and drawing
/// our own thumb keeps the rows one width whether or not the content
/// scrolls, and the bar visible whenever it does.
///
/// Dragging the thumb (or pressing anywhere on the track) scrolls, via
/// the reader's proxy: scrolling to the whole content with a
/// proportional anchor is the one continuous offset control SwiftUI
/// offers on macOS 14 — anchor y = t lands the scroll at
/// t × (content − viewport), exactly the thumb's progress.
///
/// It takes both halves plus the proxy — `scrollBarContent` on the
/// scrolled content, `scrollBar` on the scroll view around it, sharing
/// one ScrollBarState. Without the first, nothing measures the content
/// and the bar silently never appears.
struct ScrollBarModifier: ViewModifier {
    let theme: Theme
    @Binding var state: ScrollBarState
    let proxy: ScrollViewProxy

    /// The width the content leaves free at its trailing edge.
    static let gutter: CGFloat = 12
    private static let thumbWidth: CGFloat = 6
    private static let minThumb: CGFloat = 24

    /// The drag's progress while one is in flight. The thumb obeys the
    /// pointer directly instead of chasing it through the scroll
    /// geometry's measurement round-trip, which lags a frame.
    @State private var dragProgress: CGFloat?
    /// Where within the thumb the drag grabbed it, so the thumb doesn't
    /// jump to center itself under the pointer.
    @State private var grabOffset: CGFloat = 0
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.never)
            .coordinateSpace(name: scrollBarSpace)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                state.viewport = $0
            }
            .overlay(alignment: .trailing) { track }
    }

    private var scrollable: Bool {
        state.viewport > 0 && state.content.height > state.viewport + 1
    }

    private var thumbHeight: CGFloat {
        max(Self.minThumb, state.viewport * state.viewport / state.content.height)
    }

    /// Progress read back from the scroll view, clamped so an
    /// overscroll bounce pins the thumb to its end instead of pushing
    /// it out of the track.
    private var settledProgress: CGFloat {
        min(max(-state.content.minY / (state.content.height - state.viewport), 0), 1)
    }

    @ViewBuilder private var track: some View {
        if scrollable {
            let height = thumbHeight
            let travel = state.viewport - height
            Color.clear
                .frame(width: Self.gutter)
                .contentShape(Rectangle())
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(theme.dimmed.opacity(hovering || dragProgress != nil ? 0.6 : 0.4))
                        .frame(width: Self.thumbWidth, height: height)
                        .offset(y: (dragProgress ?? settledProgress) * travel)
                }
                .onHover { hovering = $0 }
                .gesture(drag(travel: travel, thumb: height))
        }
    }

    /// Grabbing the thumb drags it from where it is; pressing the bare
    /// track jumps the thumb under the pointer and drags from there.
    private func drag(travel: CGFloat, thumb: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard travel > 0 else { return }
                if dragProgress == nil {
                    let top = settledProgress * travel
                    let y = value.startLocation.y
                    grabOffset = (top...top + thumb).contains(y) ? y - top : thumb / 2
                }
                let progress = min(max((value.location.y - grabOffset) / travel, 0), 1)
                dragProgress = progress
                proxy.scrollTo(scrollBarContentID, anchor: UnitPoint(x: 0, y: progress))
            }
            .onEnded { _ in dragProgress = nil }
    }
}

/// The space the content's frame is measured in, named on the scroll
/// view by ScrollBarModifier.
private let scrollBarSpace = "scrollBar"

/// The identity the bar's drag scrubs to — `scrollBarContent` puts it
/// on the whole scrolled content.
private let scrollBarContentID = "scrollBarContent"

extension View {
    /// On a scroll view's content: reserve the bar's gutter, report
    /// where the content sits, and carry the identity the bar's drag
    /// steers by.
    func scrollBarContent(_ state: Binding<ScrollBarState>) -> some View {
        padding(.trailing, ScrollBarModifier.gutter)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(scrollBarSpace)) } action: {
                state.wrappedValue.content = $0
            }
            .id(scrollBarContentID)
    }

    /// On a scroll view, with its enclosing reader's proxy: draw the
    /// bar over the trailing gutter. See ScrollBarModifier.
    func scrollBar(
        _ theme: Theme, _ state: Binding<ScrollBarState>, _ proxy: ScrollViewProxy
    ) -> some View {
        modifier(ScrollBarModifier(theme: theme, state: state, proxy: proxy))
    }
}
