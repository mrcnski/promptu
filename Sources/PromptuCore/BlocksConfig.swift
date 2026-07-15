import Foundation

/// Loads the block list shared with Emacs promptu.
public enum BlocksConfig {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/promptu/blocks.json")
    }

    public static func load(_ url: URL = defaultURL) throws -> [Block] {
        try JSONDecoder().decode([Block].self, from: Data(contentsOf: url))
    }
}
