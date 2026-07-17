import SwiftUI

/// The ≡ icon marking a draggable row; the drag itself is attached by
/// the caller.
struct Grip: View {
    let theme: Theme

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption)
            .foregroundStyle(theme.dimmed)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
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
