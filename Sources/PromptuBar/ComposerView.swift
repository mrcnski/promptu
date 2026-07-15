import PromptuCore
import SwiftUI

struct ComposerView: View {
    @ObservedObject var session: Session
    @Environment(\.dismiss) private var dismiss
    @FocusState private var keysFocused: Bool
    @FocusState private var fieldFocused: Bool

    private var fieldShown: Bool { session.pending != nil || session.editInput != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview
            Divider()
            if let error = session.loadError {
                Text(error).foregroundStyle(.red).font(.caption)
            } else if session.editInput != nil {
                editField
            } else if session.pending != nil {
                placeholderField
            } else {
                blockGrid
            }
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 380)
        .focusable()
        .focusEffectDisabled()
        .focused($keysFocused)
        .onKeyPress(phases: .down) { handleKey($0) }
        .onAppear { keysFocused = true }
        .onChange(of: fieldShown) { _, shown in
            if shown { fieldFocused = true } else { keysFocused = true }
        }
    }

    private var preview: some View {
        ScrollView {
            Text(session.isEmpty ? "empty prompt" : session.preview)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(session.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 40, maxHeight: 160)
    }

    private var blockGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .leading),
                      GridItem(.flexible(), alignment: .leading)],
            alignment: .leading, spacing: 3
        ) {
            ForEach(session.blocks) { block in
                Button {
                    session.add(block)
                } label: {
                    HStack(spacing: 6) {
                        Text(block.key)
                            .font(.system(.body, design: .monospaced).bold())
                            .foregroundStyle(.orange)
                        Text(block.desc.isEmpty ? block.text : block.desc)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var placeholderField: some View {
        TextField(
            session.pending?.currentName ?? "",
            text: Binding(
                get: { session.pending?.input ?? "" },
                set: { session.pending?.input = $0 }
            )
        )
        .textFieldStyle(.roundedBorder)
        .focused($fieldFocused)
        .onSubmit { session.submitPlaceholder() }
        .onExitCommand { session.cancelPending() }
    }

    private var editField: some View {
        TextField(
            "edit entry",
            text: Binding(
                get: { session.editInput ?? "" },
                set: { session.editInput = $0 }
            )
        )
        .textFieldStyle(.roundedBorder)
        .focused($fieldFocused)
        .onSubmit { session.submitEdit() }
        .onExitCommand { session.cancelEdit() }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if session.negateNext {
                Text("negating next")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            } else {
                Text("- negate   ⌫ remove   ↑↓ point   ⌘E edit   ⌘Z undo   ⏎ copy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !fieldShown else { return .ignored }

        if press.modifiers.contains(.command) {
            switch press.key.character {
            case "e":
                session.beginEdit()
                return .handled
            case "z":
                press.modifiers.contains(.shift) ? session.redo() : session.undo()
                return .handled
            default:
                return .ignored
            }
        }

        if press.modifiers.contains(.control) {
            switch press.key.character {
            case "p": session.pointUp(); return .handled
            case "n": session.pointDown(); return .handled
            default: return .ignored
            }
        }

        switch press.key {
        case .return:
            if session.finish() { dismiss() }
            return .handled
        case .upArrow:
            session.pointUp()
            return .handled
        case .downArrow:
            session.pointDown()
            return .handled
        // Backspace arrives as DEL (U+7F), not KeyEquivalent.delete (U+8).
        case .delete, KeyEquivalent("\u{7F}"):
            session.removeEntry()
            return .handled
        case .escape:
            dismiss()
            return .handled
        default:
            break
        }

        if press.characters == "-" {
            session.negateNext.toggle()
            return .handled
        }
        if let block = session.blocks.first(where: { $0.key == press.characters }) {
            session.add(block)
            return .handled
        }
        return .ignored
    }
}
