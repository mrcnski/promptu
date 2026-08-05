/// Dotted numeric version comparison for the GitHub update check.
public enum Version {
    /// Whether `candidate` names a newer release than `current`,
    /// comparing dotted numeric fields ("0.10.0" beats "0.4.0") left to
    /// right, missing fields read as 0 ("1.0" equals "1.0.0"). A leading
    /// "v" (as in a git tag) is ignored, and any non-numeric field reads
    /// as 0 — so a malformed tag never spuriously beats the running
    /// build.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = fields(candidate)
        let b = fields(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func fields(_ version: String) -> [Int] {
        let trimmed =
            version.hasPrefix("v") || version.hasPrefix("V")
            ? String(version.dropFirst()) : version
        return trimmed.split(separator: ".").map { Int($0) ?? 0 }
    }
}
