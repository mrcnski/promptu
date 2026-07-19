/// The mutable composition state: entries, the point, and undo/redo.
/// A pure port of promptu.el's session core, with the same semantics:
/// the point is a gap index between entries, stored as nil at the end,
/// and every mutation checkpoints the prior state for undo.
public struct Composition: Equatable, Sendable {
    public private(set) var entries: [String] = []

    /// The gap the point sits at: 0 is before the first entry; the end
    /// (where new entries append) is stored as nil.
    public private(set) var point: Int?

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    private struct Snapshot: Equatable, Sendable {
        var entries: [String]
        var point: Int?
    }

    public init() {}

    /// Effective gap index of the point.
    public var pointIndex: Int { point ?? entries.count }

    /// Index of the entry above the point, or nil when the point is at
    /// the start (or the prompt is empty).
    public var targetIndex: Int? { pointIndex > 0 ? pointIndex - 1 : nil }

    /// The entry above the point, the one editing and removal act on.
    public var targetEntry: String? { targetIndex.map { entries[$0] } }

    /// Whether there is a change to undo.
    public var canUndo: Bool { !undoStack.isEmpty }

    public var composed: String { Compose.compose(entries) }

    /// The composed prompt with ▮ at a moved point's gap, on its own
    /// line when the separator is multi-line.
    public var preview: String {
        let ownLine = Compose.separator.contains("\n")
        var out = ""
        if point == 0 { out += "▮" + (ownLine ? "\n" : "") }
        for (idx, entry) in entries.enumerated() {
            out += (idx == 0 ? Compose.linePrefix() : Compose.separator) + entry
            if point == idx + 1 {
                out += (ownLine ? "\n" : "") + "▮"
            }
        }
        return out
    }

    /// Move the point to gap i, clamped to the entries; the end is
    /// stored as nil.
    public mutating func setPoint(_ i: Int) {
        point = i < entries.count ? max(0, i) : nil
    }

    public mutating func pointUp() { setPoint(pointIndex - 1) }
    public mutating func pointDown() { setPoint(pointIndex + 1) }

    /// Insert resolved text at the point; the point advances past it.
    public mutating func add(_ resolved: String) {
        checkpoint()
        let i = pointIndex
        entries.insert(resolved, at: i)
        setPoint(i + 1)
    }

    /// Remove the entry above the point. No-op when nothing is above it.
    public mutating func removeEntry() {
        guard let target = targetIndex else { return }
        checkpoint()
        entries.remove(at: target)
        setPoint(target)
    }

    /// Replace the entry above the point. No-op when nothing is above it.
    public mutating func replaceEntry(with text: String) {
        guard let target = targetIndex else { return }
        checkpoint()
        entries[target] = text
    }

    /// Replace every entry with `text`, the prompt in composed form: a
    /// leading line prefix is stripped and the rest becomes one blob
    /// entry, so re-composing reproduces the text. The point ends at
    /// the end. No-op when the prompt is empty.
    public mutating func replaceAll(with text: String) {
        guard !entries.isEmpty else { return }
        checkpoint()
        let prefix = Compose.linePrefix()
        entries = [text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : text]
        point = nil
    }

    /// Move the entry at `from` to index `to` (its index once the entry
    /// has been removed); the point ends past the moved entry, as after
    /// add. No-op when the move changes nothing.
    public mutating func moveEntry(from: Int, to: Int) {
        guard entries.indices.contains(from), entries.indices.contains(to), from != to
        else { return }
        checkpoint()
        entries.insert(entries.remove(at: from), at: to)
        setPoint(to + 1)
    }

    /// Restore the state to before the last change. No-op when there is
    /// nothing to undo.
    public mutating func undo() {
        guard let state = undoStack.popLast() else { return }
        redoStack.append(Snapshot(entries: entries, point: point))
        (entries, point) = (state.entries, state.point)
    }

    /// Reapply the most recently undone change. No-op when there is
    /// nothing to redo.
    public mutating func redo() {
        guard let state = redoStack.popLast() else { return }
        undoStack.append(Snapshot(entries: entries, point: point))
        (entries, point) = (state.entries, state.point)
    }

    /// Save the current state for undo; a new change invalidates redo.
    private mutating func checkpoint() {
        undoStack.append(Snapshot(entries: entries, point: point))
        redoStack.removeAll()
    }
}
