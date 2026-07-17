import PromptuCore
import SwiftUI

/// In-popover editor for the shared blocks.json: the block list, and a
/// small form for adding, editing, or deleting one block.
struct BlockEditorView: View {
    @ObservedObject var session: Session
    let theme: Theme
    @FocusState.Binding var fieldFocused: Bool

    var body: some View {
        if session.draft != nil {
            form
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 3) {
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(session.blocks) { block in
                        Button {
                            session.beginDraft(block)
                        } label: {
                            row(block).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(HoverButtonStyle(theme: theme))
                    }
                }
            }
            .frame(maxHeight: 300)
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
