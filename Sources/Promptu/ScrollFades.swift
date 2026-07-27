import SwiftUI

/// Where scrolled content sits inside its scroll view, and so which of
/// its edges are clipped. Held by the view that owns the scroll view,
/// because measuring it takes two observers in two places: the content
/// reports its frame, the scroll view its height.
struct ScrollEdges: Equatable {
    var content: CGRect = .zero
    var viewport: CGFloat = 0

    fileprivate func clipped(_ edge: VerticalEdge) -> Bool {
        edge == .top ? content.minY < -1 : content.maxY > viewport + 1
    }
}

/// Marks a scroll view's clipped edges with a short gradient into the
/// surface color, so content continuing past an edge is visible as
/// such.
///
/// It stands in for the scroll indicator, which the panel's scroll
/// views hide: the indicator's gutter appearing as content crosses the
/// height cap narrows the rows and jerks their trailing edge sideways.
///
/// Both halves are needed — `scrollEdgeContent` on the scrolled
/// content, `scrollEdgeFades` on the scroll view around it, sharing one
/// ScrollEdges. Without the first, nothing measures the content and the
/// fades never appear.
struct ScrollEdgeFades: ViewModifier {
    let theme: Theme
    @Binding var edges: ScrollEdges

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: scrollEdgeSpace)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                edges.viewport = $0
            }
            .overlay(alignment: .top) { fade(.top) }
            .overlay(alignment: .bottom) { fade(.bottom) }
    }

    private func fade(_ edge: VerticalEdge) -> some View {
        let clipped = edges.clipped(edge)
        return LinearGradient(
            colors: [theme.surface, theme.surface.opacity(0)],
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top
        )
        .frame(height: 14)
        .allowsHitTesting(false)
        .opacity(clipped ? 1 : 0)
        .animation(Motion.gated(.easeInOut(duration: 0.15)), value: clipped)
    }
}

/// The space the content's frame is measured in, named on the scroll
/// view by ScrollEdgeFades.
private let scrollEdgeSpace = "scrollEdges"

extension View {
    /// On a scroll view's content: report where it sits, for the fades
    /// on the scroll view around it.
    func scrollEdgeContent(_ edges: Binding<ScrollEdges>) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(scrollEdgeSpace)) } action: {
            edges.wrappedValue.content = $0
        }
    }

    /// On a scroll view: fade its clipped edges. See ScrollEdgeFades.
    func scrollEdgeFades(_ theme: Theme, _ edges: Binding<ScrollEdges>) -> some View {
        modifier(ScrollEdgeFades(theme: theme, edges: edges))
    }
}
