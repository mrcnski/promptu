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

    public var composed: String { Compose.compose(entries) }

    /// The composed prompt with ▮ at a moved point's gap, on its own
    /// line when the separator is multi-line.
    public var preview: String {
        previewLines.map(\.text).joined(separator: "\n")
    }

    /// The preview split into lines, each paired with the gap a block
    /// dropped on that line inserts at: an entry's lines carry the
    /// entry's own slot (insert before it), the ▮ marker's line the
    /// point's gap.
    public var previewLines: [(text: String, gap: Int)] {
        var lines: [(text: String, gap: Int)] = [(text: "", gap: 0)]
        func append(_ segment: String, gap: Int) {
            var parts = segment.components(separatedBy: "\n")
            lines[lines.count - 1].text += parts.removeFirst()
            for part in parts { lines.append((text: part, gap: gap)) }
        }
        let ownLine = Compose.separator.contains("\n")
        if point == 0 { append(ownLine ? "▮\n" : "▮", gap: 0) }
        for (idx, entry) in entries.enumerated() {
            append((idx == 0 ? Compose.linePrefix() : Compose.separator) + entry, gap: idx)
            if point == idx + 1 {
                append(ownLine ? "\n▮" : "▮", gap: idx + 1)
            }
        }
        return lines
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
