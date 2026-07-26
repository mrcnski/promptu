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

    /// One block-list page: a *.json in the config directory.
    /// blocks.json is page zero; ←/→ cycles the composer between
    /// pages, and the Block Editor edits the one showing.
    struct Page {
        let name: String
        let url: URL
        var blocks: [Block]
    }

    let loadError: String?

    @Published private(set) var pages: [Page]
    @Published private(set) var pageIndex: Int
    @Published private var composition = Composition()
    @Published var negateNext = false
    @Published var pending: Pending?
    /// The entry text an open edit started from, nil when no edit is
    /// open. Only the seed: the field keeps its live text locally and
    /// commits it through submitEdit.
    @Published var editInput: String?
    /// Which screen the popover shows.
    @Published var screen = Screen.composer
    @Published var draft: Draft?

    /// The prompts already copied, newest first.
    @Published private(set) var history: History
    /// Whether copying records the prompt. Off leaves what is already
    /// stored in place — erasing it is `clearHistory`'s job, not a
    /// side effect of flipping a switch.
    @Published private(set) var historyOn: Bool
    /// Which row the history screen has selected.
    @Published private(set) var historySelection = 0
    /// How far a ⌥↑/⌥↓ walk through history has gone, nil when not
    /// walking — the next walk then starts over at the newest prompt.
    @Published private(set) var historyIndex: Int?

    private static let historyKey = "promptHistory"
    private static let historyDisabledKey = "historyDisabled"

    enum Screen { case composer, editor, settings, history }

    init() {
        // Seed the bundled preset pages once: deleting one afterwards
        // removes the page for good instead of it returning next launch.
        let store = UserDefaults.standard
        if !store.bool(forKey: "presetsSeeded") {
            store.set(true, forKey: "presetsSeeded")
            try? Presets.seed()
        }

        // Plain nested arrays of strings, so the list is a property
        // list and needs no encoding of its own.
        history = History(store.array(forKey: Self.historyKey) as? [[String]] ?? [])
        historyOn = !store.bool(forKey: Self.historyDisabledKey)

        var pages: [Page] = []
        var loadError: String?
        for url in Presets.pageURLs() {
            let name =
                url == BlocksConfig.defaultURL
                ? "basic blocks" : url.deletingPathExtension().lastPathComponent
            if url == BlocksConfig.defaultURL {
                do {
                    pages.append(Page(name: name, url: url, blocks: try BlocksConfig.loadOrSeed()))
                } catch {
                    pages.append(Page(name: name, url: url, blocks: []))
                    loadError = "Can't read \(url.path): \(error.localizedDescription)"
                }
            } else if let blocks = try? BlocksConfig.load(url) {
                pages.append(Page(name: name, url: url, blocks: blocks))
            } else {
                // A broken preset page must not take the panel down.
                NSLog("promptu: can't read page \(url.path), skipping")
            }
        }
        self.pages = pages
        self.loadError = loadError
        pageIndex = min(max(store.integer(forKey: "pageIndex"), 0), pages.count - 1)
    }

    /// The active page's blocks — what the grid, key lookup, and Block
    /// Editor all act on.
    var blocks: [Block] { pages[pageIndex].blocks }
    var pageName: String { pages[pageIndex].name }

    /// Cycle the active page by `delta`, wrapping; the choice persists
    /// across launches.
    func cyclePage(_ delta: Int) {
        guard pages.count > 1 else { return }
        pageIndex = (pageIndex + delta + pages.count) % pages.count
        UserDefaults.standard.set(pageIndex, forKey: "pageIndex")
    }

    var isEmpty: Bool { composition.entries.isEmpty }
    var preview: String { composition.preview }
    var entries: [String] { composition.entries }
    /// The gap the point sits at, nil at the end (no marker shown).
    var pointGap: Int? { composition.point }

    /// Whether an entry sits above the point — the one remove and
    /// edit act on.
    var hasTarget: Bool { composition.targetEntry != nil }
    var canUndo: Bool { composition.canUndo }
    var canPointUp: Bool { composition.pointIndex > 0 }
    var canPointDown: Bool { composition.point != nil }

    func moveEntry(from: Int, to: Int) {
        leaveHistory()
        composition.moveEntry(from: from, to: to)
    }

    func add(_ block: Block) {
        leaveHistory()
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

    func removeEntry() {
        leaveHistory()
        composition.removeEntry()
    }
    func pointUp() { composition.pointUp() }
    func pointDown() { composition.pointDown() }
    func undo() {
        leaveHistory()
        composition.undo()
    }
    func redo() {
        leaveHistory()
        composition.redo()
    }

    /// Whether the open edit spans the whole prompt: submitting then
    /// replaces every entry with the field's text.
    private(set) var editingAll = false

    func beginEdit() {
        if let entry = composition.targetEntry {
            editingAll = false
            editInput = entry
        }
    }

    /// Edit the whole prompt as one text, in its composed form.
    /// Submitting collapses the entries into a single blob entry — the
    /// edited text no longer maps onto the individual entries.
    func beginEditAll() {
        guard !isEmpty else { return }
        editingAll = true
        editInput = composition.composed
    }

    /// Blank input leaves the prompt unchanged; removing an entry is
    /// backspace's job.
    func submitEdit(_ text: String) {
        leaveHistory()
        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            editingAll
                ? composition.replaceAll(with: text)
                : composition.replaceEntry(with: text)
        }
        editInput = nil
    }

    func cancelEdit() {
        editInput = nil
    }

    // MARK: - History

    /// Record a copied prompt, when history is on.
    private func recordHistory(_ entries: [String]) {
        guard historyOn else { return }
        history.record(entries)
        saveHistory()
    }

    private func saveHistory() {
        UserDefaults.standard.set(history.prompts, forKey: Self.historyKey)
    }

    /// Turn recording on or off. What is already stored survives the
    /// switch — see `historyOn`.
    func setHistoryOn(_ on: Bool) {
        historyOn = on
        UserDefaults.standard.set(!on, forKey: Self.historyDisabledKey)
    }

    func moveHistorySelection(_ delta: Int) {
        guard !history.isEmpty else { return }
        historySelection = min(max(historySelection + delta, 0), history.count - 1)
    }

    /// Forget one past prompt — the way to drop a single prompt whose
    /// typed values shouldn't be sitting on disk.
    func deleteHistory(at index: Int) {
        history.remove(at: index)
        saveHistory()
        historySelection = min(historySelection, max(history.count - 1, 0))
    }

    func clearHistory() {
        history.clear()
        saveHistory()
        historySelection = 0
    }

    /// Load a past prompt into the composition and show it. Undoable:
    /// ⌘Z brings back whatever was in progress.
    func recall(_ index: Int) {
        guard history.prompts.indices.contains(index) else { return }
        composition.load(history.prompts[index], checkpoint: true)
        negateNext = false
        setScreen(.composer)
    }

    /// Copy a past prompt to the clipboard without touching the
    /// composition: the prompt in progress is not this one's to throw
    /// away, and finish would clear it past recovering. Copying
    /// re-records it, so reuse moves it back to the front.
    func copyHistory(_ index: Int) -> Bool {
        guard history.prompts.indices.contains(index) else { return false }
        copyToClipboard(history.prompts[index])
        return true
    }

    /// Walk through past prompts in the composer: `delta` +1 older, -1
    /// newer. Only the first step checkpoints (see `Composition.load`),
    /// and stepping back past the newest prompt spends that checkpoint
    /// to restore the prompt that was in progress.
    func stepHistory(_ delta: Int) {
        guard !history.isEmpty else { return }
        guard let index = historyIndex else {
            guard delta > 0 else { return }
            composition.load(history.prompts[0], checkpoint: true)
            historyIndex = 0
            return
        }
        let next = index + delta
        if next < 0 {
            composition.undo()
            historyIndex = nil
        } else if next < history.count {
            composition.load(history.prompts[next], checkpoint: false)
            historyIndex = next
        }
    }

    /// End a history walk: any edit, or a change of screen, makes the
    /// next ⌥↑ start over from the newest prompt.
    private func leaveHistory() { historyIndex = nil }

    // MARK: - Screens

    func toggleEditor() {
        setScreen(screen == .editor ? .composer : .editor)
    }

    func toggleSettings() {
        setScreen(screen == .settings ? .composer : .settings)
    }

    /// Opening always starts at the newest prompt: the selection is
    /// where you are looking, not a setting worth remembering.
    func toggleHistory() {
        if screen != .history { historySelection = 0 }
        setScreen(screen == .history ? .composer : .history)
    }

    /// Switching screens also drops any half-typed placeholder or entry
    /// edit, so no hidden field keeps the focus.
    private func setScreen(_ new: Screen) {
        leaveHistory()
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
        pages[pageIndex].blocks = updated
        do {
            try BlocksConfig.save(updated, to: pages[pageIndex].url)
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

    /// Save the list to the active page's file; on success adopt it,
    /// close the draft form, and return nil. On failure return the
    /// error text.
    private func persist(_ updated: [Block]) -> String? {
        do {
            try BlocksConfig.save(updated, to: pages[pageIndex].url)
            pages[pageIndex].blocks = updated
            draft = nil
            return nil
        } catch {
            return "can't save: \(error.localizedDescription)"
        }
    }

    /// Compose the entries onto the clipboard and record them. Copying
    /// is the one moment a prompt is worth keeping — recording on close
    /// would fill history with abandoned drafts.
    private func copyToClipboard(_ entries: [String]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Compose.compose(entries), forType: .string)
        recordHistory(entries)
    }

    /// Copy the composed prompt to the clipboard and start over.
    /// Returns false (and does nothing) when the prompt is empty.
    func finish() -> Bool {
        guard !isEmpty else { return false }
        copyToClipboard(composition.entries)
        leaveHistory()
        composition = Composition()
        negateNext = false
        pending = nil
        editInput = nil
        return true
    }
}
