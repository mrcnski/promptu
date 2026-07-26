import PromptuCore
import SwiftUI

/// The past-prompts screen: one row per copied prompt, newest first,
/// ↑↓ to select and ⏎ to load it back into the composer.
///
/// Every row is a single truncated line and the list keeps a fixed
/// height whatever it holds, so moving the selection — or deleting a
/// row — can never resize the popover. A height change while the panel
/// is open repaints the window a frame ahead of its content, which
/// reads as an app-wide flash.
struct HistoryView: View {
    @ObservedObject var session: Session
    let theme: Theme

    private static let listHeight: CGFloat = 220

    var body: some View {
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
                    } else {
                        ForEach(Array(session.history.prompts.enumerated()), id: \.offset) {
                            index, entries in
                            HistoryRow(
                                session: session, theme: theme, index: index,
                                summary: History.summary(entries)
                            )
                            .id(index)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: Self.listHeight, alignment: .top)
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
