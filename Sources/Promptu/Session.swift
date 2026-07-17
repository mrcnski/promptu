import AppKit
import PromptuCore

/// UI state behind the menubar popover, wrapping the pure Composition.
@MainActor
final class Session: ObservableObject {
    /// A block waiting for its placeholder values, filled in one at a time.
    struct Pending {
        var block: Block
        var negated: Bool
        var names: [String]
        var values: [String: String] = [:]
        var input = ""

        var currentName: String { names[values.count] }
    }

    /// A block being created or edited in the Block Editor.
    /// originalKey identifies the block being replaced, nil when adding.
    struct Draft {
        var originalKey: String?
        var key = ""
        var desc = ""
        var text = ""
        var negative = ""
        var error: String?
    }

    let loadError: String?

    @Published private(set) var blocks: [Block]
    @Published private var composition = Composition()
    @Published var negateNext = false
    @Published var pending: Pending?
    /// Text being edited for the entry above the point, nil when not editing.
    @Published var editInput: String?
    /// Which screen the popover shows.
    @Published var screen = Screen.composer
    @Published var draft: Draft?

    enum Screen { case composer, editor, settings }

    init() {
        do {
            blocks = try BlocksConfig.loadOrSeed()
            loadError = nil
        } catch {
            blocks = []
            loadError = "Can't read \(BlocksConfig.defaultURL.path): \(error.localizedDescription)"
        }
    }

    var isEmpty: Bool { composition.entries.isEmpty }
    var preview: String { composition.preview }

    func add(_ block: Block) {
        let negated = negateNext
        negateNext = false
        let names = Compose.activePlaceholders(block, negated: negated)
        if names.isEmpty {
            composition.add(Compose.resolve(block, negated: negated))
        } else {
            pending = Pending(block: block, negated: negated, names: names)
        }
    }

    func submitPlaceholder() {
        guard var p = pending else { return }
        p.values[p.currentName] = p.input
        p.input = ""
        if p.values.count == p.names.count {
            composition.add(
                Compose.substitute(
                    Compose.resolve(p.block, negated: p.negated), values: p.values))
            pending = nil
        } else {
            pending = p
        }
    }

    func cancelPending() {
        pending = nil
    }

    func removeEntry() { composition.removeEntry() }
    func pointUp() { composition.pointUp() }
    func pointDown() { composition.pointDown() }
    func undo() { composition.undo() }
    func redo() { composition.redo() }

    func beginEdit() {
        if let entry = composition.targetEntry { editInput = entry }
    }

    /// Blank input leaves the entry unchanged; removing an entry is
    /// backspace's job.
    func submitEdit() {
        if let text = editInput, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            composition.replaceEntry(with: text)
        }
        editInput = nil
    }

    func cancelEdit() {
        editInput = nil
    }

    // MARK: - Screens

    func toggleEditor() {
        setScreen(screen == .editor ? .composer : .editor)
    }

    func toggleSettings() {
        setScreen(screen == .settings ? .composer : .settings)
    }

    /// Switching screens also drops any half-typed placeholder or entry
    /// edit, so no hidden field keeps the focus.
    private func setScreen(_ new: Screen) {
        screen = new
        draft = nil
        pending = nil
        editInput = nil
    }

    func beginDraft(_ block: Block? = nil) {
        draft = block.map {
            Draft(
                originalKey: $0.key, key: $0.key, desc: $0.desc,
                text: $0.text, negative: $0.negative ?? "")
        } ?? Draft()
    }

    func cancelDraft() {
        draft = nil
    }

    /// Validate the draft, then write the whole block list back to
    /// blocks.json; placeholders are derived from {name}s in the texts.
    func submitDraft() {
        guard var d = draft else { return }
        let key = d.key.trimmingCharacters(in: .whitespaces)
        let text = d.text.trimmingCharacters(in: .whitespaces)
        let negative = d.negative.trimmingCharacters(in: .whitespaces)
        if key.count != 1 {
            d.error = "key must be a single character"
        } else if blocks.contains(where: { $0.key == key && $0.key != d.originalKey }) {
            d.error = "key \"\(key)\" is already used"
        } else if text.isEmpty {
            d.error = "text must not be empty"
        } else {
            let block = Block(
                key: key, desc: d.desc.trimmingCharacters(in: .whitespaces), text: text,
                negative: negative.isEmpty ? nil : negative,
                placeholders: Compose.derivePlaceholders(
                    text: text, negative: negative.isEmpty ? nil : negative))
            var updated = blocks
            if let index = updated.firstIndex(where: { $0.key == d.originalKey }) {
                updated[index] = block
            } else {
                updated.append(block)
            }
            guard let error = persist(updated) else { return }
            d.error = error
        }
        draft = d
    }

    /// Move the block at `from` to index `to` (its index once the block
    /// has been removed) and save the new order. A failed save only
    /// logs — the order still holds in memory, and the next successful
    /// save writes it out.
    func moveBlock(from: Int, to: Int) {
        guard blocks.indices.contains(from), blocks.indices.contains(to) else { return }
        var updated = blocks
        updated.insert(updated.remove(at: from), at: to)
        guard updated != blocks else { return }
        blocks = updated
        do {
            try BlocksConfig.save(blocks)
        } catch {
            NSLog("promptu: can't save block order: \(error.localizedDescription)")
        }
    }

    func deleteDraftBlock() {
        guard let originalKey = draft?.originalKey else {
            draft = nil
            return
        }
        var updated = blocks
        updated.removeAll { $0.key == originalKey }
        if let error = persist(updated) { draft?.error = error }
    }

    /// Save the list to blocks.json; on success adopt it, close the
    /// draft form, and return nil. On failure return the error text.
    private func persist(_ updated: [Block]) -> String? {
        do {
            try BlocksConfig.save(updated)
            blocks = updated
            draft = nil
            return nil
        } catch {
            return "can't save: \(error.localizedDescription)"
        }
    }

    /// Copy the composed prompt to the clipboard and start over.
    /// Returns false (and does nothing) when the prompt is empty.
    func finish() -> Bool {
        guard !isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(composition.composed, forType: .string)
        composition = Composition()
        negateNext = false
        pending = nil
        editInput = nil
        return true
    }
}
