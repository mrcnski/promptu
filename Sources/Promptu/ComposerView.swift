import AppKit
import PromptuCore
import SwiftUI

struct ComposerView: View {
    @ObservedObject var session: Session
    @ObservedObject var updateChecker: UpdateChecker
    /// Closes the hosting popover; injected because the view is hosted
    /// in an NSPopover, outside any SwiftUI presentation context.
    let close: () -> Void
    @FocusState private var keysFocused: Bool
    @FocusState private var fieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ThemeChoice.defaultsKey) private var themeChoice = ThemeChoice.system

    /// Non-nil while an ESC waits out its meta-prefix grace window;
    /// runs the deferred lone-ESC action when it fires.
    @State private var pendingEscape: DispatchWorkItem?

    /// The grid's badge lamp: which block key is wearing the
    /// just-pressed green. With hands on the keyboard, nothing else in
    /// the grid confirms which block a press landed on.
    @StateObject private var keyFlash = Flash()

    /// The footer's lamp, keyed by hint label — the keyboard's
    /// counterpart of the buttons' hover. Callers only fire it for a
    /// hint whose action applies — a grayed hint stays quiet, like the
    /// button it mirrors — and skip keys that replace the view under
    /// the flash (negate's row swap, copy's panel close, the screen
    /// switches).
    @StateObject private var hintFlash = Flash()

    private var theme: Theme { themeChoice.theme(for: colorScheme) }
    private var fieldShown: Bool {
        session.pending != nil || session.editInput != nil || session.draft != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let update = updateChecker.available {
                updateNotice(update)
            }
            if session.screen == .editor {
                pageRow
                BlockEditorView(session: session, theme: theme, fieldFocused: $fieldFocused)
            } else if session.screen == .settings {
                SettingsView(theme: theme, session: session, updateChecker: updateChecker)
            } else if session.screen == .history {
                HistoryView(session: session, theme: theme)
            } else if let error = session.loadError {
                preview
                Text(error).foregroundStyle(theme.error).font(.caption)
            } else {
                preview
                pageRow
                // The grid keeps its slot while a field is shown, so a
                // submit swaps content without resizing the panel: a
                // resize repaints the window a frame ahead of the new
                // content, which reads as an app-wide flash.
                ZStack(alignment: .topLeading) {
                    blockGrid
                        .opacity(fieldShown ? 0 : 1)
                        .allowsHitTesting(!fieldShown)
                    if session.editInput != nil {
                        editField
                    } else if session.pending != nil {
                        placeholderField
                    }
                }
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

    /// The live prompt, reorderable by dragging a row's grip. The
    /// history screen shows the same view, read-only, so a recalled
    /// prompt looks the same before and after.
    private var preview: some View {
        PromptPreview(
            entries: session.entries, theme: theme, pointGap: session.pointGap,
            move: session.moveEntry)
    }

    /// The active page's name between ◀ ▶ cycling buttons, over the
    /// block grid and the editor list. Absent with a single page —
    /// there is nothing to cycle to.
    @ViewBuilder
    private var pageRow: some View {
        if session.pages.count > 1 {
            HStack(spacing: 2) {
                pageArrow("◀", -1)
                Text(session.pageName).font(.caption).foregroundStyle(theme.dimmed)
                pageArrow("▶", 1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// A dismissible banner, atop every screen, linking to a newer
    /// release on GitHub. Raised by the once-a-day update check.
    private func updateNotice(_ update: UpdateChecker.Update) -> some View {
        HStack(spacing: 6) {
            Button { NSWorkspace.shared.open(update.url) } label: {
                Text("v\(update.version) available →")
                    .font(.caption.bold())
                    .foregroundStyle(theme.foreground)
            }
            .buttonStyle(HoverButtonStyle(theme: theme, horizontalPadding: 4))
            Spacer()
            Button { updateChecker.dismiss() } label: {
                Text("✕").font(.caption).foregroundStyle(theme.dimmed)
            }
            .buttonStyle(HoverButtonStyle(theme: theme, horizontalPadding: 4))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(theme.notice.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(theme.notice.opacity(0.3)))
    }

    private func pageArrow(_ label: String, _ delta: Int) -> some View {
        Button { if !fieldShown { session.cyclePage(delta) } } label: {
            Text(label).font(.caption2).foregroundStyle(theme.foreground.opacity(0.8))
        }
        .buttonStyle(HoverButtonStyle(theme: theme, horizontalPadding: 3))
        .opacity(fieldShown ? 0.4 : 1)
        .allowsHitTesting(!fieldShown)
    }

    /// Two columns of blocks, or one when any label on the page needs
    /// the width — the preset pages' fuller sentences would truncate
    /// in a half-width cell.
    private var gridColumns: [GridItem] {
        let long = session.blocks.contains { label in
            let hints = Compose.placeholderHints(label) ?? ""
            return label.desc.count + hints.count > 20
        }
        let column = GridItem(.flexible(), alignment: .leading)
        return long ? [column] : [column, column]
    }

    private var blockGrid: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 3) {
            ForEach(session.blocks) { block in
                Button {
                    session.add(block)
                } label: {
                    HStack(spacing: 8) {
                        KeyBadge(
                            theme: theme, key: block.key,
                            flashed: keyFlash.lit == block.key)
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
        .fieldChrome(theme)
        .focused($fieldFocused)
        .onSubmit {
            let block = session.pending?.block
            // Flash only once the last placeholder lands and the grid
            // returns; a mid-block submit just advances to the next
            // placeholder behind the still-open field.
            session.submitPlaceholder()
            if session.pending == nil, let block { keyFlash.fire(block.key) }
        }
        .onExitCommand { session.cancelPending() }
    }

    private var editField: some View {
        EditField(
            session: session, theme: theme, fieldFocused: $fieldFocused,
            metaPrefixArmed: { pendingEscape != nil })
    }

    /// Keys while a text field is focused. Emacs meta keys —
    /// ⌥B/⌥F/⌥D/⌥⏎, or the ESC-prefixed pairs ESC b/f/d/⏎, ESC being
    /// Emacs' meta prefix — are forwarded to the field editor. The ESC
    /// prefix matters beyond habit: terminal-scoped remap tools
    /// deliver exactly that pair for a physical ⌥B (Keyboard Maestro
    /// types "Esc, b"), and they cannot see an LSUIElement app as
    /// frontmost to stand down. A lone ESC still cancels the field
    /// once the grace window passes; ESC ESC cancels immediately.
    /// The field-editor selectors behind the meta keys: word motion
    /// M-b/M-f/M-d, and M-⏎ inserting the newline that a plain Return
    /// (submit) can't type.
    private nonisolated static let fieldCommands: [Character: Selector] = [
        "b": #selector(NSStandardKeyBindingResponding.moveWordBackward(_:)),
        "f": #selector(NSStandardKeyBindingResponding.moveWordForward(_:)),
        "d": #selector(NSStandardKeyBindingResponding.deleteWordForward(_:)),
        "\r": #selector(NSStandardKeyBindingResponding.insertNewlineIgnoringFieldEditor(_:)),
    ]

    private func handleFieldKey(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape && press.modifiers.isEmpty {
            if pendingEscape != nil {
                clearPendingEscape()
                cancelField()
            } else {
                armPendingEscape { cancelField() }
            }
            return .handled
        }
        let meta =
            press.modifiers == [.option]
            || (pendingEscape != nil && press.modifiers.isEmpty)
        guard meta, let selector = Self.fieldCommands[press.key.character],
            let responder = NSApp.keyWindow?.firstResponder
        else { return .ignored }
        clearPendingEscape()
        responder.doCommand(by: selector)
        return .handled
    }

    /// Keys on the block editor's list (the form's field has the
    /// focus while a draft is open, so these never see its presses).
    /// ↑↓ move the selection and ⏎ opens it for editing; ←/→ cycle
    /// pages, as on the composer.
    private func handleEditorKey(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape {
            session.toggleEditor()
            return .handled
        }
        // ⌃P/⌃N move the selection, as everywhere else in the app.
        if press.modifiers.contains(.control) {
            switch press.key.character {
            case "p":
                session.moveEditorSelection(-1)
                return .handled
            case "n":
                session.moveEditorSelection(1)
                return .handled
            default:
                return .ignored
            }
        }
        switch press.key {
        case .upArrow:
            session.moveEditorSelection(-1)
            return .handled
        case .downArrow:
            session.moveEditorSelection(1)
            return .handled
        case .leftArrow, .rightArrow:
            session.cyclePage(press.key == .leftArrow ? -1 : 1)
            return .handled
        case .return:
            session.editSelectedBlock()
            return .handled
        default:
            return .ignored
        }
    }

    /// Keys on the history screen. ⏎ loads the selection into the
    /// composer, where ⏎ copies it as always; ⌘⏎ copies it outright,
    /// leaving the prompt in progress where it is.
    private func handleHistoryKey(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape {
            session.toggleHistory()
            return .handled
        }
        // ⌃P/⌃N move the selection, as they move the point on the
        // composer: the same Emacs pair for "up and down a list".
        if press.modifiers.contains(.control) {
            switch press.key.character {
            case "p":
                session.moveHistorySelection(-1)
                return .handled
            case "n":
                session.moveHistorySelection(1)
                return .handled
            default:
                return .ignored
            }
        }
        switch press.key {
        case .upArrow:
            session.moveHistorySelection(-1)
            return .handled
        case .downArrow:
            session.moveHistorySelection(1)
            return .handled
        case .return:
            if press.modifiers.contains(.command) {
                if session.copyHistory(session.historySelection) { close() }
            } else {
                session.recall(session.historySelection)
            }
            return .handled
        case .delete, KeyEquivalent("\u{7F}"):
            if !session.history.isEmpty { hintFlash.fire("⌫") }
            session.deleteHistory(at: session.historySelection)
            return .handled
        default:
            return .ignored
        }
    }

    /// The deferred lone-ESC action; non-nil while the meta-prefix
    /// grace window is open.
    private func armPendingEscape(_ action: @escaping () -> Void) {
        let work = DispatchWorkItem {
            pendingEscape = nil
            action()
        }
        pendingEscape = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private func clearPendingEscape() {
        pendingEscape?.cancel()
        pendingEscape = nil
    }

    private func cancelField() {
        if session.editInput != nil {
            session.cancelEdit()
        } else if session.pending != nil {
            session.cancelPending()
        } else if session.draft != nil {
            session.cancelDraft()
        }
    }

    /// One "key action" hint, two-tone: the key bright, the label
    /// dimmed — both knocked out to the panel background while the
    /// hint's flash chip is lit, or neither would read on solid green.
    private func hint(_ key: String, _ label: String, lit: Bool = false) -> some View {
        HStack(spacing: 3) {
            hintKey(key, lit: lit)
            Text(label).font(.caption)
                .foregroundStyle(lit ? theme.background : theme.dimmed)
        }
    }

    /// Not monospaced, though a key elsewhere is: the footer's keys are
    /// mostly symbols (⌘ ⌫ ⏎ ⇧ ↑), and SF Mono draws those noticeably
    /// larger than the label beside them at the same size, which read as
    /// the rows using different font sizes. Weight and color still set
    /// the key apart from its label.
    private func hintKey(_ key: String, lit: Bool = false) -> some View {
        Text(key).font(.caption.bold())
            .foregroundStyle(lit ? theme.background : theme.foreground.opacity(0.8))
    }

    /// A hint that is also a clickable button. Like the keys it mirrors,
    /// it is inert — and grayed out — while a text field has the focus
    /// or while `enabled` says its action can't apply right now.
    private func hintButton(
        _ key: String, _ label: String, enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        let available = enabled && !fieldShown
        let lit = hintFlash.lit == key
        return Button {
            if available { action() }
        } label: {
            hint(key, label, lit: lit)
        }
        .buttonStyle(HoverButtonStyle(theme: theme, horizontalPadding: 3))
        .modifier(HintFlashChrome(theme: theme, lit: lit, available: available))
    }

    /// A hint that is always available, unlike hintButton. Both use the
    /// footer's tighter padding: every row's first item has to sit on
    /// the same left edge, and the padding is what sets it.
    private func footerButton(
        _ key: String, _ label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { hint(key, label) }
            .buttonStyle(HoverButtonStyle(theme: theme, horizontalPadding: 3))
    }

    /// A short vertical rule separating the footer's hint clusters.
    private var hintDivider: some View {
        Divider().frame(height: 12).overlay(theme.dimmed.opacity(0.3))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if session.screen == .editor {
                HStack {
                    if session.draft == nil {
                        hintButton("esc", "back") { session.toggleEditor() }
                        Spacer()
                        hintDivider
                        Spacer()
                        hintButton("⏎", "edit", enabled: !session.blocks.isEmpty) {
                            session.editSelectedBlock()
                        }
                        Spacer()
                        Text("click to edit · drag to reorder")
                            .font(.caption).foregroundStyle(theme.dimmed)
                    } else {
                        footerButton("⏎", "save") { session.submitDraft() }
                        Spacer()
                        footerButton("esc", "cancel") { session.cancelDraft() }
                    }
                }
            } else if session.screen == .settings {
                HStack {
                    hintButton("esc", "back") { session.toggleSettings() }
                    Spacer()
                }
            } else if session.screen == .history {
                let stocked = !session.history.isEmpty
                HStack {
                    hintButton("esc", "back") { session.toggleHistory() }
                    Spacer()
                    hintDivider
                    Spacer()
                    hintButton("⏎", "load", enabled: stocked) {
                        session.recall(session.historySelection)
                    }
                    Spacer()
                    hintButton("⌘⏎", "copy", enabled: stocked) {
                        if session.copyHistory(session.historySelection) { close() }
                    }
                    Spacer()
                    hintButton("⌫", "forget", enabled: stocked) {
                        session.deleteHistory(at: session.historySelection)
                    }
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
                    .buttonStyle(HoverButtonStyle(theme: theme, horizontalPadding: 3))
                    Spacer()
                }
            } else {
                HStack {
                    hintButton("-", "negate") { session.negateNext.toggle() }
                    Spacer()
                    hintDivider
                    Spacer()
                    hintButton("⌫", "remove", enabled: session.hasTarget) {
                        session.removeEntry()
                    }
                    Spacer()
                    hintButton("⌘E", "edit", enabled: session.hasTarget) {
                        session.beginEdit()
                    }
                    Spacer()
                    hintButton("⇧⌘E", "edit all", enabled: !session.isEmpty) {
                        session.beginEditAll()
                    }
                    Spacer()
                    hintDivider
                    Spacer()
                    pointHint
                }
            }
            // The two whole-prompt actions get their own row: sharing
            // one with the four screen buttons ran them past the
            // panel's width.
            if session.screen == .composer {
                HStack {
                    hintButton("⌘Z", "undo", enabled: session.canUndo) { session.undo() }
                    hintButton("⇧⌘Z", "redo", enabled: session.canRedo) { session.redo() }
                    Spacer()
                    hintButton("⏎", "copy", enabled: !session.isEmpty) {
                        if session.finish() { close() }
                    }
                }
            }
            HStack {
                footerButton("⌘,", session.screen == .settings ? "compose" : "settings") {
                    session.toggleSettings()
                }
                footerButton("⌘B", session.screen == .editor ? "compose" : "blocks") {
                    session.toggleEditor()
                }
                footerButton("⌘Y", session.screen == .history ? "compose" : "history") {
                    session.toggleHistory()
                }
                footerButton("⌘Q", "quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
                Spacer()
            }
        }
    }

    /// The point hint: each arrow is its own little button, grayed out
    /// when the point can't move that way.
    private var pointHint: some View {
        HStack(spacing: 2) {
            pointArrow("↑", enabled: session.canPointUp) { session.pointUp() }
            pointArrow("↓", enabled: session.canPointDown) { session.pointDown() }
            Text("point").font(.caption).foregroundStyle(theme.dimmed)
                .opacity(session.isEmpty || fieldShown ? 0.4 : 1)
        }
    }

    private func pointArrow(
        _ key: String, enabled: Bool, move: @escaping () -> Void
    ) -> some View {
        let available = enabled && !fieldShown
        let lit = hintFlash.lit == key
        return Button { if available { move() } } label: { hintKey(key, lit: lit) }
            .buttonStyle(HoverButtonStyle(theme: theme, horizontalPadding: 3))
            .modifier(HintFlashChrome(theme: theme, lit: lit, available: available))
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !fieldShown else { return handleFieldKey(press) }
        let command = press.modifiers.contains(.command)

        // The screen switches work from every screen, so they are
        // handled once, ahead of the per-screen keys. Repeating them
        // per screen is what left ⌘Y live on some screens and dead on
        // others.
        //
        // Case-folded throughout: shift capitalizes the character
        // (⇧⌘E, ⇧⌘Z).
        if command {
            switch press.key.character.lowercased() {
            case "b":
                session.toggleEditor()
                return .handled
            case ",":
                session.toggleSettings()
                return .handled
            case "y":
                session.toggleHistory()
                return .handled
            default:
                break
            }
        }

        // Off the composer only that screen's own keys act; block keys
        // must not add entries behind it.
        switch session.screen {
        case .editor:
            return handleEditorKey(press)
        case .settings:
            if press.key == .escape {
                session.toggleSettings()
                return .handled
            }
            return .ignored
        case .history:
            return handleHistoryKey(press)
        case .composer:
            break
        }

        if command {
            switch press.key.character.lowercased() {
            case "e":
                if press.modifiers.contains(.shift) {
                    if !session.isEmpty { hintFlash.fire("⇧⌘E") }
                    session.beginEditAll()
                } else {
                    if session.hasTarget { hintFlash.fire("⌘E") }
                    session.beginEdit()
                }
                return .handled
            case "z":
                if press.modifiers.contains(.shift) {
                    if session.canRedo { hintFlash.fire("⇧⌘Z") }
                    session.redo()
                } else {
                    if session.canUndo { hintFlash.fire("⌘Z") }
                    session.undo()
                }
                return .handled
            default:
                return .ignored
            }
        }

        // ⌥↑/⌥↓ walk history in place — Emacs promptu's M-p/M-n. Plain
        // ⌥ presses are free here: block keys reject every modifier.
        if press.modifiers == [.option] {
            switch press.key {
            case .upArrow:
                session.stepHistory(1)
                return .handled
            case .downArrow:
                session.stepHistory(-1)
                return .handled
            default:
                return .ignored
            }
        }

        if press.modifiers.contains(.control) {
            switch press.key.character {
            case "p":
                if session.canPointUp { hintFlash.fire("↑") }
                session.pointUp()
                return .handled
            case "n":
                if session.canPointDown { hintFlash.fire("↓") }
                session.pointDown()
                return .handled
            default: return .ignored
            }
        }

        switch press.key {
        case .return:
            if session.finish() { close() }
            return .handled
        case .upArrow:
            if session.canPointUp { hintFlash.fire("↑") }
            session.pointUp()
            return .handled
        case .downArrow:
            if session.canPointDown { hintFlash.fire("↓") }
            session.pointDown()
            return .handled
        case .leftArrow:
            session.cyclePage(-1)
            return .handled
        case .rightArrow:
            session.cyclePage(1)
            return .handled
        // Backspace arrives as DEL (U+7F), not KeyEquivalent.delete (U+8).
        case .delete, KeyEquivalent("\u{7F}"):
            if session.hasTarget { hintFlash.fire("⌫") }
            session.removeEntry()
            return .handled
        case .escape:
            // The same meta-prefix grace as in the fields, so a
            // terminal-style "Esc, b" pair doesn't close the panel and
            // leak a stray block key.
            if pendingEscape != nil {
                clearPendingEscape()
                close()
            } else {
                armPendingEscape { close() }
            }
            return .handled
        default:
            break
        }

        // A plain key inside the grace window is ESC-prefixed: consume
        // it as (unused) meta input rather than a block key.
        if pendingEscape != nil {
            clearPendingEscape()
            return .handled
        }

        // Block keys are plain characters: a modified press (⌥B — say,
        // an Emacs word-motion habit) must not add a block.
        if !press.modifiers.isDisjoint(with: [.option, .control, .command]) {
            return .ignored
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
            // A block with placeholders opens its field over the grid,
            // so an immediate flash would burn out unseen; it flashes
            // on the field's submit instead (see placeholderField).
            if session.pending == nil { keyFlash.fire(block.key) }
            return .handled
        }
        return .ignored
    }
}

/// The entry-edit field. Its live text is local state, committed only
/// on submit: routing keystrokes through the session would re-render
/// the whole panel per key, and the field's end-editing write-back on
/// teardown would fight submitEdit's close (the old enter-twice bug).
///
/// A TextEditor (a real NSTextView) at a fixed height, after two
/// hand-rolled shapes failed: unbounded, a large prompt grew the panel
/// past the screen; a TextField in a capped ScrollView either sat at
/// the full cap around one line (a bare ScrollView is greedy) or,
/// pinned to the text's measured height, resized the panel per wrapped
/// line — flashing the whole app each time — and never followed the
/// caret past the cap. The text view scrolls internally and keeps the
/// caret visible on its own; the fixed height means typing never
/// resizes the panel. Whole-prompt edits get a taller box than single
/// entries — a blob wants reading room a one-liner doesn't.
///
/// A text view inserts a newline on Return, so submit needs the
/// interception below; it must stand down for ⌥⏎ and while the ESC
/// meta prefix is armed (metaPrefixArmed), letting both fall through
/// to handleFieldKey's newline forwarding — or ESC ⏎ (a remap tool's
/// physical ⌥⏎) would submit instead of inserting.
private struct EditField: View {
    @ObservedObject var session: Session
    let theme: Theme
    @FocusState.Binding var fieldFocused: Bool
    /// Reads ComposerView's ESC-prefix state at keypress time; a
    /// stored value would be stale by the ⏎ of an ESC ⏎ pair.
    let metaPrefixArmed: () -> Bool
    @State private var text = ""

    private static let entryHeight: CGFloat = 64
    private static let wholePromptHeight: CGFloat = 160

    /// What the open edit acts on — the field itself looks the same
    /// for an entry and for the whole prompt.
    private var caption: String {
        if session.editingAll {
            return "editing whole prompt · saves as a single entry · ⌥⏎ newline"
        }
        let count = session.entries.count
        let target = (session.pointGap ?? count) - 1
        return target == count - 1
            ? "editing last entry · ⌥⏎ newline"
            : "editing entry \(target + 1) of \(count) · ⌥⏎ newline"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $text)
                .font(.body)
                .foregroundStyle(theme.foreground)
                .scrollContentBackground(.hidden)
                .focused($fieldFocused)
                .frame(
                    height: session.editingAll ? Self.wholePromptHeight : Self.entryHeight
                )
                .onAppear { text = session.editInput ?? "" }
                .onKeyPress(keys: [.return], phases: .down) { press in
                    guard press.modifiers.isEmpty, !metaPrefixArmed() else { return .ignored }
                    session.submitEdit(text)
                    return .handled
                }
                .onExitCommand { session.cancelEdit() }
                .onChange(of: fieldFocused) { _, focused in
                    guard focused else { return }
                    // Select-all parity with the TextField this box
                    // replaced — typing over the old text is the common
                    // case. macOS 14's TextEditor has no selection API,
                    // so reach the text view through the responder
                    // chain once focus has landed.
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil)
                        }
                    }
                }
                .padding(6)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6).strokeBorder(theme.key.opacity(0.45)))
            Text(caption)
                .font(.caption).foregroundStyle(theme.dimmed)
        }
    }
}

/// Shared chrome for the panel's text fields: the surface background
/// plus a key-tinted border, so an editable field stands out from the
/// flat boxes around it.
struct FieldChrome: ViewModifier {
    let theme: Theme

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .foregroundStyle(theme.foreground)
            .padding(6)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6).strokeBorder(theme.key.opacity(0.45)))
    }
}

extension View {
    func fieldChrome(_ theme: Theme) -> some View { modifier(FieldChrome(theme: theme)) }
}

/// A block's key in its rounded badge, as shown in the composer grid
/// and the editor's block list.
struct KeyBadge: View {
    let theme: Theme
    let key: String
    /// Wearing the just-pressed confirmation green (see `Flash`); the
    /// editor's list never lights it.
    var flashed: Bool = false

    var body: some View {
        Text(key)
            .font(.system(.body, design: .monospaced).bold())
            .foregroundStyle(flashed ? theme.background : theme.key)
            .frame(width: 22, height: 22)
            .background(
                flashed ? theme.success : theme.key.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 5))
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
