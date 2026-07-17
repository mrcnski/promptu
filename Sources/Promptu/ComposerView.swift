import PromptuCore
import SwiftUI

struct ComposerView: View {
    @ObservedObject var session: Session
    /// Closes the hosting popover; injected because the view is hosted
    /// in an NSPopover, outside any SwiftUI presentation context.
    let close: () -> Void
    @FocusState private var keysFocused: Bool
    @FocusState private var fieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ThemeChoice.defaultsKey) private var themeChoice = ThemeChoice.system

    @State private var drag = ReorderDrag()

    /// Where the preview's content sits relative to its viewport,
    /// driving the edge fades that mark clipped content.
    @State private var previewContent: CGRect = .zero
    @State private var previewViewport: CGFloat = 0

    private nonisolated static let previewSpace = "preview"
    private nonisolated static let viewportSpace = "previewViewport"

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

    /// One preview row per entry, with an identity that stays with the
    /// entry across reorders so a drop settles under one animation.
    /// Duplicate entries are told apart by their occurrence number.
    private struct PreviewRow: Identifiable {
        let id: AnyHashable
        let index: Int
        let text: String
    }

    private var entryRows: [PreviewRow] {
        var seen: [String: Int] = [:]
        return session.entries.enumerated().map { index, text in
            let n = seen[text, default: 0]
            seen[text] = n + 1
            return PreviewRow(id: AnyHashable("\(n)|\(text)"), index: index, text: text)
        }
    }

    private var entryIDs: [AnyHashable] { entryRows.map(\.id) }

    /// See BlockEditorView.dragTarget — the same drag geometry, over
    /// the preview's entry rows.
    private var entryDragTarget: Int? { drag.target(in: entryIDs) }

    /// The preview as one row per entry (plus the point marker's row),
    /// reorderable by the same hand-rolled DragGesture as the block
    /// editor: grab a row's grip and the others slide to open a gap.
    private var preview: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if session.isEmpty {
                        Text("empty prompt")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(theme.dimmed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        if session.pointGap == 0 { marker }
                        ForEach(entryRows) { row in
                            entryRow(row)
                            if session.pointGap == row.index + 1 { marker }
                        }
                    }
                }
                .coordinateSpace(name: Self.previewSpace)
                .animation(ReorderDrag.settle, value: entryDragTarget)
                .onPreferenceChange(ReorderFrameKey.self) { drag.measure($0) }
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named(Self.viewportSpace))
                } action: { previewContent = $0 }
            }
            .coordinateSpace(name: Self.viewportSpace)
            // No scroll indicator: its gutter appearing as the preview
            // crosses the height cap would narrow the rows and jerk the
            // trailing grips sideways. Edge fades mark clipped content
            // instead.
            .scrollIndicators(.never)
            .frame(minHeight: 40, maxHeight: 300)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                previewViewport = $0
            }
            .overlay(alignment: .top) { edgeFade(.top) }
            .overlay(alignment: .bottom) { edgeFade(.bottom) }
            .onChange(of: session.preview) {
                // Follow the point: its marker when moved, the tail
                // otherwise. The nil anchor scrolls the minimum needed.
                if session.pointGap != nil {
                    proxy.scrollTo(Self.markerID, anchor: nil)
                } else if let last = entryRows.last {
                    proxy.scrollTo(last.id, anchor: nil)
                }
            }
        }
        .padding(8)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.dimmed.opacity(0.15)))
        // A screen switch mid-drag (⌘B under a held mouse) cancels the
        // gesture without its onEnded; don't keep a stuck drag around —
        // the marker would stay hidden and the frames frozen.
        .onDisappear { drag = ReorderDrag() }
    }

    /// A short gradient into the surface color at a clipped edge — the
    /// scrollability hint standing in for the hidden scroll indicator.
    private func edgeFade(_ edge: VerticalEdge) -> some View {
        let clipped =
            edge == .top
            ? previewContent.minY < -1
            : previewContent.maxY > previewViewport + 1
        return LinearGradient(
            colors: [theme.surface, theme.surface.opacity(0)],
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top
        )
        .frame(height: 14)
        .allowsHitTesting(false)
        .opacity(clipped ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: clipped)
    }

    private static let markerID: AnyHashable = "marker"

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
    /// full-height reorder grip overlaid on the trailing edge. The
    /// grip's icon sits on the entry's first line: pinned to the top,
    /// a re-measure of the row (selectable text can settle a beat
    /// late) can't move it, where a centered icon would jump.
    private func entryRow(_ row: PreviewRow) -> some View {
        HStack(spacing: 0) {
            Text(Compose.linePrefix() + row.text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(theme.foreground)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Grip(theme: theme).hidden()
        }
        .overlay(alignment: .trailing) {
            Grip(theme: theme, iconAlignment: .top)
                .padding(.top, 2)
                .gesture(
                    reorderGesture(
                        $drag, id: row.id, space: Self.previewSpace, order: entryIDs,
                        move: session.moveEntry))
        }
        // The dragged row rides above the rest on an opaque background,
        // so it reads as lifted while it floats over them.
        .background(
            drag.draggingID == row.id ? theme.hover : .clear,
            in: RoundedRectangle(cornerRadius: 4))
        .reorderFrame(row.id, in: Self.previewSpace)
        .offset(y: drag.offset(of: row.id, in: entryIDs, spacing: 0))
        .zIndex(drag.draggingID == row.id ? 1 : 0)
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
                        KeyBadge(theme: theme, key: block.key)
                        blockLabel(block)
                            .foregroundStyle(theme.foreground)
                            .lineLimit(1)
                    }
                    // Fill the grid cell, so the hover highlight spans
                    // the whole column.
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(HoverButtonStyle(theme: theme))
            }
        }
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
                        Text("click a block to edit it · drag to reorder")
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
            if command && press.key.character == "," {
                session.toggleSettings()
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

/// A block's key in its rounded badge, as shown in the composer grid
/// and the editor's block list.
struct KeyBadge: View {
    let theme: Theme
    let key: String

    var body: some View {
        Text(key)
            .font(.system(.body, design: .monospaced).bold())
            .foregroundStyle(theme.key)
            .frame(width: 22, height: 22)
            .background(theme.key.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
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
