import PromptuCore
import SwiftUI

/// A composed prompt as one row per entry, in its own bordered box:
/// the composer's live preview, and the history screen's readout of the
/// past prompt under the selection. One view for both, so a prompt
/// looks the same before and after it is recalled.
///
/// Passing `move` turns on drag-to-reorder and makes the box the
/// composer's; without it the preview is a read-only readout, which
/// also scrolls back to the top whenever its content is swapped for
/// another prompt.
struct PromptPreview: View {
    let entries: [String]
    let theme: Theme
    /// The gap the point sits at, nil for no marker — a read-only
    /// preview has no point to show.
    var pointGap: Int?
    var emptyText = "empty prompt"
    /// Equal bounds pin the height: the history screen selects with the
    /// arrow keys, and a preview that resized to each prompt would
    /// resize the popover under every keypress.
    var minHeight: CGFloat = 40
    var maxHeight: CGFloat = 300
    var move: ((Int, Int) -> Void)?

    @State private var drag = ReorderDrag()
    @State private var bar = ScrollBarState()

    private nonisolated static let previewSpace = "preview"
    private static let markerID: AnyHashable = "marker"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if entries.isEmpty {
                        Text(emptyText)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(theme.dimmed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        if pointGap == 0 { marker }
                        ForEach(rows) { row in
                            entryRow(row)
                            if pointGap == row.index + 1 { marker }
                        }
                    }
                }
                .coordinateSpace(name: Self.previewSpace)
                .animation(Motion.gated(ReorderDrag.settle), value: dragTarget)
                .onPreferenceChange(ReorderFrameKey.self) { drag.measure($0) }
                .scrollBarContent($bar)
            }
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .scrollBar(theme, $bar, proxy)
            .onChange(of: entries) { follow(proxy) }
            .onChange(of: pointGap) { follow(proxy) }
        }
        .padding(8)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.dimmed.opacity(0.15)))
        // A screen switch mid-drag (⌘B under a held mouse) cancels the
        // gesture without its onEnded; don't keep a stuck drag around —
        // the marker would stay hidden and the frames frozen.
        .onDisappear { drag = ReorderDrag() }
    }

    /// Keep the interesting end in view: the point's marker when it has
    /// moved, the tail otherwise, and the top when the whole prompt was
    /// swapped for another. The nil anchor scrolls the minimum needed.
    ///
    /// A frame later, because the popover window grows a frame behind
    /// the content: scrolling against the still-small viewport shifts
    /// every row up, and the resize snaps them back — a visible bounce.
    private func follow(_ proxy: ScrollViewProxy) {
        let target: AnyHashable? =
            move == nil
            ? rows.first?.id
            : (pointGap != nil ? Self.markerID : rows.last?.id)
        guard let target else { return }
        let anchor: UnitPoint? = move == nil ? .top : nil
        DispatchQueue.main.async { proxy.scrollTo(target, anchor: anchor) }
    }

    /// One row per entry, with an identity that stays with the entry
    /// across reorders so a drop settles under one animation. Duplicate
    /// entries are told apart by their occurrence number.
    private struct PreviewRow: Identifiable {
        let id: AnyHashable
        let index: Int
        let text: String
    }

    private var rows: [PreviewRow] {
        var seen: [String: Int] = [:]
        return entries.enumerated().map { index, text in
            let n = seen[text, default: 0]
            seen[text] = n + 1
            return PreviewRow(id: AnyHashable("\(n)|\(text)"), index: index, text: text)
        }
    }

    private var rowIDs: [AnyHashable] { rows.map(\.id) }

    /// See BlockEditorView.dragTarget — the same drag geometry, over
    /// the preview's entry rows.
    private var dragTarget: Int? { drag.target(in: rowIDs) }

    /// The point marker, on its own line (the separator is multi-line).
    /// Hidden — but keeping its slot — while a drag is in flight, since
    /// the sliding entry rows don't reflow around it.
    private var marker: some View {
        Text("▮")
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(theme.key)
            .opacity(drag.active ? 0 : 1)
            .id(Self.markerID)
    }

    /// An entry's line(s), bulleted like the composed prompt, with a
    /// full-height reorder grip overlaid on the trailing edge, its icon
    /// centered on the row. The grip is absent when there is nothing to
    /// reorder.
    private func entryRow(_ row: PreviewRow) -> some View {
        HStack(spacing: 0) {
            Text(Compose.linePrefix() + row.text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(theme.foreground)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if move != nil { Grip(theme: theme).hidden() }
        }
        .overlay(alignment: .trailing) {
            if let move {
                Grip(theme: theme)
                    .gesture(
                        reorderGesture(
                            $drag, id: row.id, space: Self.previewSpace, order: rowIDs,
                            move: move))
            }
        }
        // The dragged row rides above the rest on an opaque background,
        // so it reads as lifted while it floats over them.
        .background(
            drag.draggingID == row.id ? theme.hover : .clear,
            in: RoundedRectangle(cornerRadius: 4))
        .reorderFrame(row.id, in: Self.previewSpace)
        .offset(y: drag.offset(of: row.id, in: rowIDs, spacing: 0))
        .zIndex(drag.draggingID == row.id ? 1 : 0)
    }
}
