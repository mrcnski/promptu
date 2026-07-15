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

    let blocks: [Block]
    let loadError: String?

    @Published private(set) var composition = Composition()
    @Published var negateNext = false
    @Published var pending: Pending?
    /// Text being edited for the entry above the point, nil when not editing.
    @Published var editInput: String?

    init() {
        do {
            blocks = try BlocksConfig.load()
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
