import PromptuCore
import SwiftUI

/// In-popover editor for the shared blocks.json: the block list, and a
/// small form for adding, editing, or deleting one block.
struct BlockEditorView: View {
    @ObservedObject var session: Session
    let theme: Theme
    @FocusState.Binding var fieldFocused: Bool

    @State private var drag = ReorderDrag()

    private static let rowSpacing: CGFloat = 3
    private static let space = "blocks"

    var body: some View {
        if session.draft != nil {
            form
        } else {
            list
        }
    }

    private var blockIDs: [AnyHashable] { session.blocks.map { AnyHashable($0.id) } }

    /// The row order changes only as the drag crosses a resting row's
    /// midpoint, so animating on this index — not the continuous offset
    /// — slides the others without lagging the dragged row.
    private var dragTarget: Int? { drag.target(in: blockIDs) }

    /// A plain ScrollView + VStack, reordered by a hand-rolled
    /// DragGesture (grab a row's grip). Unlike onDrag/onDrop there is no
    /// system drag snapshot, so nothing snaps back on drop; unlike a
    /// List it sizes to its content, so it renders in the popover.
    private var list: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ScrollView {
                VStack(spacing: Self.rowSpacing) {
                    ForEach(session.blocks) { block in
                        BlockRow(
                            session: session, theme: theme, block: block,
                            content: row(block), spacing: Self.rowSpacing, space: Self.space,
                            drag: $drag)
                    }
                }
                .coordinateSpace(name: Self.space)
                .animation(ReorderDrag.settle, value: dragTarget)
                .onPreferenceChange(ReorderFrameKey.self) { drag.measure($0) }
            }
            .frame(maxHeight: 380)
            Button {
                session.beginDraft()
            } label: {
                Text("+ add block").font(.callout).foregroundStyle(theme.key)
            }
            .buttonStyle(HoverButtonStyle(theme: theme))
        }
    }

    private func row(_ block: Block) -> some View {
        HStack(spacing: 8) {
            Text(block.key)
                .font(.system(.body, design: .monospaced).bold())
                .foregroundStyle(theme.key)
                .frame(width: 22, height: 22)
                .background(theme.key.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(block.desc.isEmpty ? block.text : block.desc)
                    .foregroundStyle(theme.foreground)
                    .lineLimit(1)
                if !block.desc.isEmpty {
                    Text(block.text)
                        .font(.caption)
                        .foregroundStyle(theme.dimmed)
                        .lineLimit(1)
                }
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("key (a single character)", \.key, focusedFirst: true)
            field("desc (shown in the menu)", \.desc)
            field("text ({name} prompts for a value)", \.text)
            field("negative (optional, used when negated)", \.negative)
            if let error = session.draft?.error {
                Text(error).font(.caption).foregroundStyle(theme.error)
            }
            HStack {
                if session.draft?.originalKey != nil {
                    formButton("delete", theme.error) { session.deleteDraftBlock() }
                }
                Spacer()
                formButton("cancel", theme.dimmed) { session.cancelDraft() }
                formButton("save", theme.key) { session.submitDraft() }
            }
        }
    }

    @ViewBuilder
    private func field(
        _ label: String, _ keyPath: WritableKeyPath<Session.Draft, String>,
        focusedFirst: Bool = false
    ) -> some View {
        let text = Binding(
            get: { session.draft?[keyPath: keyPath] ?? "" },
            set: { session.draft?[keyPath: keyPath] = $0 })
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(theme.dimmed)
            if focusedFirst {
                styledField(text).focused($fieldFocused)
            } else {
                styledField(text)
            }
        }
    }

    private func styledField(_ text: Binding<String>) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .foregroundStyle(theme.foreground)
            .padding(6)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 6))
            .onSubmit { session.submitDraft() }
            .onExitCommand { session.cancelDraft() }
    }

    private func formButton(
        _ label: String, _ color: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label).font(.callout).foregroundStyle(color)
        }
        .buttonStyle(HoverButtonStyle(theme: theme))
    }
}

/// One reorderable row: tap the body to edit, drag the grip to move.
/// The grip owns the drag so it can never be mistaken for a tap, and so
/// the body's text stays a plain click target.
private struct BlockRow<Content: View>: View {
    @ObservedObject var session: Session
    let theme: Theme
    let block: Block
    let content: Content
    let spacing: CGFloat
    let space: String
    @Binding var drag: ReorderDrag
    @State private var hovering = false

    private var dragging: Bool { drag.draggingID == AnyHashable(block.id) }
    private var order: [AnyHashable] { session.blocks.map { AnyHashable($0.id) } }

    var body: some View {
        HStack(spacing: 0) {
            content.frame(maxWidth: .infinity, alignment: .leading)
            // Reserves the grip's width; the visible grip is overlaid
            // below so its hit target spans the row's full height.
            Grip(theme: theme).hidden()
        }
        .overlay(alignment: .trailing) {
            Grip(theme: theme)
                // A grip click that never moves must not fall through
                // to the row's tap and open the edit form.
                .onTapGesture {}
                .gesture(
                    reorderGesture(
                        $drag, id: AnyHashable(block.id), space: space, order: order,
                        move: session.moveBlock))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        // The dragged row rides above the rest on an opaque background,
        // so it reads as lifted while it floats over them.
        .background(background, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { session.beginDraft(block) }
        .reorderFrame(block.id, in: space)
        .offset(y: drag.offset(of: AnyHashable(block.id), in: order, spacing: spacing))
        .zIndex(dragging ? 1 : 0)
    }

    private var background: Color {
        if dragging { return theme.hover }
        return hovering ? theme.hover : .clear
    }
}
