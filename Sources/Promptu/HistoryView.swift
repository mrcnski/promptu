import PromptuCore
import SwiftUI

/// The past-prompts screen: the selection shown in full at the top, in
/// the composer's own preview, over the list of prompts to pick from.
/// ↑↓ move the selection and ⏎ loads it into the composer, where it
/// then looks exactly as it does here.
///
/// Both boxes are a fixed height and scroll their own content, so a
/// long prompt is reachable without being cut off, and neither moving
/// the selection nor forgetting a row resizes the popover — a height
/// change while the panel is open repaints the window a frame ahead of
/// its content, which reads as an app-wide flash.
struct HistoryView: View {
    @ObservedObject var session: Session
    let theme: Theme
    @State private var edges = ScrollEdges()

    // The list is the part being driven, so it gets the height; the
    // preview only has to show enough of a prompt to recognize it,
    // and scrolls for the rest.
    private static let previewHeight: CGFloat = 98
    private static let listHeight: CGFloat = 212

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Blank rather than captioned when there is nothing to
            // show: the list below says why.
            PromptPreview(
                entries: selection ?? [], theme: theme, emptyText: "",
                minHeight: Self.previewHeight, maxHeight: Self.previewHeight)
            list
        }
    }

    /// The prompt the selection points at, nil when there is none to
    /// point at.
    private var selection: [String]? {
        let index = session.historySelection
        return session.history.prompts.indices.contains(index)
            ? session.history.prompts[index] : nil
    }

    /// One line per past prompt, newest first. A row is the prompt
    /// summarized to a single line: the preview above carries the whole
    /// of it, so the list stays scannable.
    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if session.history.isEmpty {
                        Text("no past prompts yet")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(theme.dimmed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                    }
                    ForEach(Array(session.history.prompts.enumerated()), id: \.offset) {
                        index, entries in
                        HistoryRow(
                            session: session, theme: theme, index: index,
                            summary: History.summary(entries)
                        )
                        .id(index)
                    }
                }
                .scrollEdgeContent($edges)
            }
            .scrollIndicators(.never)
            .frame(height: Self.listHeight, alignment: .top)
            // The same clipped-edge hint the preview uses: with the
            // list a fixed height, nothing else says that more prompts
            // continue past its edge.
            .scrollEdgeFades(theme, $edges)
            .onChange(of: session.historySelection) { _, index in
                proxy.scrollTo(index, anchor: nil)
            }
        }
        .padding(8)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.dimmed.opacity(0.15)))
    }
}

/// One past prompt. Clicking loads it, the same as ⏎ on the selection.
private struct HistoryRow: View {
    @ObservedObject var session: Session
    let theme: Theme
    let index: Int
    let summary: String
    @State private var hovering = false

    private var selected: Bool { index == session.historySelection }

    var body: some View {
        Text(summary)
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(selected ? theme.foreground : theme.dimmed)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                selected || hovering ? theme.hover : .clear,
                in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { session.recall(index) }
    }
}
