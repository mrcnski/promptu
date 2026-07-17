import PromptuCore
import SwiftUI

struct ComposerView: View {
    @ObservedObject var session: Session
    /// Closes the hosting popover; injected because the view is hosted
    /// in an NSPopover, outside any SwiftUI presentation context.
    let close: () -> Void
    @FocusState private var keysFocused: Bool
    @FocusState private var fieldFocused: Bool
    @State private var draggingKey: String?
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ThemeChoice.defaultsKey) private var themeChoice = ThemeChoice.system

    private var theme: Theme { themeChoice.theme(for: colorScheme) }
    private var fieldShown: Bool {
        session.pending != nil || session.editInput != nil || session.draft != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if session.screen == .editor {
                BlockEditorView(session: session, theme: theme, fieldFocused: $fieldFocused)
            } else if session.screen == .settings {
                SettingsView(theme: theme)
            } else if let error = session.loadError {
                preview
                Text(error).foregroundStyle(theme.error).font(.caption)
            } else if session.editInput != nil {
                preview
                editField
            } else if session.pending != nil {
                preview
                placeholderField
            } else {
                preview
                blockGrid
            }
            Divider().overlay(theme.dimmed.opacity(0.3))
            footer
        }
        .padding(12)
        .frame(width: 380)
        .background(theme.background)
        .focusable()
        .focusEffectDisabled()
        .focused($keysFocused)
        .onKeyPress(phases: [.down, .repeat]) { handleKey($0) }
        .onAppear { keysFocused = true }
        .onChange(of: fieldShown) { _, shown in
            if shown { fieldFocused = true } else { keysFocused = true }
        }
    }

    /// The preview split into lines, so the scroll view can target the
    /// point marker's line.
    private var previewLines: [String] {
        (session.isEmpty ? "empty prompt" : session.preview)
            .components(separatedBy: "\n")
    }

    private var preview: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(previewLines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(previewColor(line))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                }
            }
            .frame(minHeight: 40, maxHeight: 300)
            .onChange(of: session.preview) {
                // Follow the point: its marker's line when moved, the tail
                // otherwise. The nil anchor scrolls the minimum needed.
                let lines = previewLines
                let target = lines.firstIndex { $0.contains("▮") } ?? lines.count - 1
                proxy.scrollTo(target, anchor: nil)
            }
        }
        .padding(8)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.dimmed.opacity(0.15)))
    }

    private func previewColor(_ line: String) -> Color {
        if session.isEmpty { return theme.dimmed }
        return line == "▮" ? theme.key : theme.foreground
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
                    HStack(spacing: 8) {
                        Text(block.key)
                            .font(.system(.body, design: .monospaced).bold())
                            .foregroundStyle(theme.key)
                            .frame(width: 22, height: 22)
                            .background(
                                theme.key.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                        blockLabel(block)
                            .foregroundStyle(theme.foreground)
                            .lineLimit(1)
                    }
                    // Fill the grid cell, so the hover highlight spans
                    // the whole column.
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(HoverButtonStyle(theme: theme))
                .blockReorderable(block, draggingKey: $draggingKey, session: session)
            }
        }
        .animation(.default, value: session.blocks)
    }

    /// The block's menu label: its desc plus colored <placeholder> hints,
    /// standing alone when the desc is empty — the same rules as Emacs
    /// promptu's `promptu--block-description`.
    private func blockLabel(_ block: Block) -> Text {
        guard let hints = Compose.placeholderHints(block) else { return Text(block.desc) }
        let hintText = Text(hints).foregroundStyle(theme.placeholder)
        return block.desc.isEmpty ? hintText : Text(block.desc + " ") + hintText
    }

    private var placeholderField: some View {
        TextField(
            session.pending?.currentName ?? "",
            text: Binding(
                get: { session.pending?.input ?? "" },
                set: { session.pending?.input = $0 }
            )
        )
        .textFieldStyle(.plain)
        .foregroundStyle(theme.foreground)
        .padding(6)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 6))
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
        .textFieldStyle(.plain)
        .foregroundStyle(theme.foreground)
        .padding(6)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 6))
        .focused($fieldFocused)
        .onSubmit { session.submitEdit() }
        .onExitCommand { session.cancelEdit() }
    }

    /// One "key action" hint, two-tone: the key bright, the label dimmed.
    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            hintKey(key)
            Text(label).font(.caption).foregroundStyle(theme.dimmed)
        }
    }

    private func hintKey(_ key: String) -> some View {
        Text(key).font(.caption.monospaced().bold())
            .foregroundStyle(theme.foreground.opacity(0.8))
    }

    /// A hint that is also a clickable button. Like the keys it mirrors,
    /// it is inert while a text field has the focus.
    private func hintButton(
        _ key: String, _ label: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            if !fieldShown { action() }
        } label: {
            hint(key, label)
        }
        .buttonStyle(HoverButtonStyle(theme: theme, horizontalPadding: 3))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if session.screen == .editor {
                HStack {
                    if session.draft == nil {
                        hintButton("esc", "back") { session.toggleEditor() }
                        Spacer()
                        Text("click a block to edit it")
                            .font(.caption).foregroundStyle(theme.dimmed)
                    } else {
                        Button { session.submitDraft() } label: { hint("⏎", "save") }
                            .buttonStyle(HoverButtonStyle(theme: theme))
                        Spacer()
                        Button { session.cancelDraft() } label: { hint("esc", "cancel") }
                            .buttonStyle(HoverButtonStyle(theme: theme))
                    }
                }
            } else if session.screen == .settings {
                HStack {
                    hintButton("esc", "back") { session.toggleSettings() }
                    Spacer()
                }
            } else if session.negateNext {
                HStack {
                    Button {
                        session.negateNext = false
                    } label: {
                        Text("negating next")
                            .font(.caption.bold())
                            .foregroundStyle(theme.placeholder)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.placeholder.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(HoverButtonStyle(theme: theme))
                    Spacer()
                }
            } else {
                HStack {
                    hintButton("-", "negate") { session.negateNext.toggle() }
                    Spacer()
                    hintButton("⌫", "remove") { session.removeEntry() }
                    Spacer()
                    pointHint
                    Spacer()
                    hintButton("⌘E", "edit") { session.beginEdit() }
                    Spacer()
                    hintButton("⌘Z", "undo") { session.undo() }
                    Spacer()
                    hintButton("⏎", "copy") { if session.finish() { close() } }
                }
            }
            HStack {
                Button { session.toggleSettings() } label: {
                    hint("⌘,", session.screen == .settings ? "compose" : "settings")
                }
                .buttonStyle(HoverButtonStyle(theme: theme))
                Button { session.toggleEditor() } label: {
                    hint("⌘B", session.screen == .editor ? "compose" : "block editor")
                }
                .buttonStyle(HoverButtonStyle(theme: theme))
                Spacer()
                Button { NSApp.terminate(nil) } label: { hint("⌘Q", "quit") }
                    .buttonStyle(HoverButtonStyle(theme: theme))
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
    }

    /// The point hint: each arrow is its own little button.
    private var pointHint: some View {
        HStack(spacing: 2) {
            Button { if !fieldShown { session.pointUp() } } label: { hintKey("↑") }
                .buttonStyle(HoverButtonStyle(theme: theme, horizontalPadding: 3))
            Button { if !fieldShown { session.pointDown() } } label: { hintKey("↓") }
                .buttonStyle(HoverButtonStyle(theme: theme, horizontalPadding: 3))
            Text("point").font(.caption).foregroundStyle(theme.dimmed)
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !fieldShown else { return .ignored }
        let command = press.modifiers.contains(.command)

        // On the editor and settings screens only "back" keys act; block
        // keys must not add entries behind them.
        switch session.screen {
        case .editor:
            if press.key == .escape || (command && press.key.character == "b") {
                session.toggleEditor()
                return .handled
            }
            return .ignored
        case .settings:
            if press.key == .escape || (command && press.key.character == ",") {
                session.toggleSettings()
                return .handled
            }
            if command && press.key.character == "b" {
                session.toggleEditor()
                return .handled
            }
            return .ignored
        case .composer:
            break
        }

        if command {
            switch press.key.character {
            case "b":
                session.toggleEditor()
                return .handled
            case ",":
                session.toggleSettings()
                return .handled
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
            if session.finish() { close() }
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
            close()
            return .handled
        default:
            break
        }

        // Everything above may auto-repeat while held; adding is
        // deliberate, so a held block key must not pile up entries or
        // flip negation.
        if press.phase == .repeat { return .handled }

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

/// Plain button that highlights under the mouse and dims while pressed.
/// The tighter horizontal padding keeps a row of many small buttons
/// (the footer hints) inside the panel width.
struct HoverButtonStyle: ButtonStyle {
    let theme: Theme
    var horizontalPadding: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        Highlighted(
            configuration: configuration, theme: theme, horizontalPadding: horizontalPadding)
    }

    // ButtonStyle itself can't hold per-button @State; this inner
    // view carries the hover flag for each styled button.
    private struct Highlighted: View {
        let configuration: Configuration
        let theme: Theme
        let horizontalPadding: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 3)
                .background(
                    hovering ? theme.hover : .clear,
                    in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.6 : 1)
                .onHover { hovering = $0 }
        }
    }
}
