import SwiftUI

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
/// The bar never reads the live viewport; the scroll view passes the
/// height its frame caps at instead. The popover window grows a frame
/// behind the content, so while it catches up the content genuinely
/// overflows the viewport — a thumb keyed on the viewport flashes on
/// every growth spurt (each added entry, the placeholder flow's stacked
/// resizes). Content measured against the constant cap can't: below
/// the cap the thumb never appears, above it it never blinks.
///
/// Dragging the thumb (or pressing anywhere on the track) scrolls, via
/// the reader's proxy: scrolling to the whole content with a
/// proportional anchor is the one continuous offset control SwiftUI
/// offers on macOS 14 — anchor y = t lands the scroll at
/// t × (content − viewport), exactly the thumb's progress.
///
/// It takes both halves plus the proxy — `scrollBarContent` on the
/// scrolled content, `scrollBar` on the scroll view around it, sharing
/// one measured frame. Without the first, nothing measures the content
/// and the bar silently never appears.
struct ScrollBarModifier: ViewModifier {
    let theme: Theme
    @Binding var content: CGRect
    let proxy: ScrollViewProxy
    /// The height the scroll view's frame caps at — its viewport
    /// height whenever there is anything to scroll.
    let height: CGFloat

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
            .overlay(alignment: .trailing) { track }
    }

    private var scrollable: Bool { content.height > height + 1 }

    private var thumbHeight: CGFloat {
        guard scrollable else { return Self.minThumb }
        return max(Self.minThumb, height * height / content.height)
    }

    /// How far the thumb's top can move along the track.
    private var travel: CGFloat { max(height - thumbHeight, 0) }

    /// Progress read back from the scroll view, clamped so an
    /// overscroll bounce pins the thumb to its end instead of pushing
    /// it out of the track.
    private var settledProgress: CGFloat {
        guard scrollable else { return 0 }
        return min(max(-content.minY / (content.height - height), 0), 1)
    }

    private var track: some View {
        Color.clear
            .frame(width: Self.gutter)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if scrollable {
                    Capsule()
                        .fill(theme.dimmed.opacity(hovering || dragProgress != nil ? 0.6 : 0.4))
                        .frame(width: Self.thumbWidth, height: thumbHeight)
                        .offset(y: (dragProgress ?? settledProgress) * travel)
                }
            }
            .onHover { hovering = $0 }
            .gesture(drag)
    }

    /// Grabbing the thumb drags it from where it is; pressing the bare
    /// track jumps the thumb under the pointer and drags from there.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard scrollable, travel > 0 else { return }
                if dragProgress == nil {
                    let top = settledProgress * travel
                    let y = value.startLocation.y
                    grabOffset = (top...top + thumbHeight).contains(y) ? y - top : thumbHeight / 2
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
    func scrollBarContent(_ content: Binding<CGRect>) -> some View {
        padding(.trailing, ScrollBarModifier.gutter)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(scrollBarSpace)) } action: {
                content.wrappedValue = $0
            }
            .id(scrollBarContentID)
    }

    /// On a scroll view whose frame caps at `height`, with its
    /// enclosing reader's proxy: draw the bar over the trailing gutter.
    /// See ScrollBarModifier.
    func scrollBar(
        _ theme: Theme, _ content: Binding<CGRect>, _ proxy: ScrollViewProxy,
        height: CGFloat
    ) -> some View {
        modifier(ScrollBarModifier(theme: theme, content: content, proxy: proxy, height: height))
    }
}
