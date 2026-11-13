import Foundation

/// A puzzle downloaded from the pack server. The free generator does not use this type.
struct DownloadedPuzzle: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var givens: [Int]
    var solution: [Int]
    var difficulty: Difficulty
}

struct DownloadedPack: Codable, Equatable, Identifiable {
    var id: String
    var puzzles: [DownloadedPuzzle]
}

struct PackListing: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var summary: String
    var difficultyMix: String
    var puzzleCount: Int
    var productID: String
}

enum PackProduct {
    static let starter = "com.brianbancroft.sudoku.pack.starter"
    static let hard = "com.brianbancroft.sudoku.pack.hard"
    static let expert = "com.brianbancroft.sudoku.pack.expert"
    static let all = [starter, hard, expert]

    /// Shown if the puzzle server has not answered yet. Ids match the server catalog.
    static let fallback: [PackListing] = [
        PackListing(
            id: "quiet-start",
            name: "Quiet Start",
            summary: "Six puzzles for a calm sitting. Four easy, two medium.",
            difficultyMix: "4 easy · 2 medium",
            puzzleCount: 6,
            productID: starter
        ),
        PackListing(
            id: "hard-lines",
            name: "Hard Lines",
            summary: "Six hard puzzles, where pairs and lines start to matter.",
            difficultyMix: "6 hard",
            puzzleCount: 6,
            productID: hard
        ),
        PackListing(
            id: "long-night",
            name: "Long Night",
            summary: "Four expert puzzles with no short path.",
            difficultyMix: "4 expert",
            puzzleCount: 4,
            productID: expert
        ),
    ]
}

enum ServerBaseURL {
    /// Placeholder until the Worker hostname from `wrangler deploy` is pasted into the Release build setting.
    static let placeholder = "https://sudoku-packs.example.workers.dev"
    static let local = "http://127.0.0.1:8787"

    /// `SudokuPackServerURL` comes from Info.plist. Debug builds substitute localhost. Release builds substitute the workers.dev placeholder.
    static var fallback: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "SudokuPackServerURL") as? String,
           let normalized = normalized(configured) {
            return normalized
        }
        return placeholder
    }

    /// http is only allowed for this computer. https is allowed for a pack server you host later.
    /// This never accepts a payment URL.
    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else { return nil }
        switch scheme {
        case "http":
            guard host == "127.0.0.1" || host == "localhost" else { return nil }
        case "https":
            guard !host.isEmpty else { return nil }
        default:
            return nil
        }
        var result = "\(scheme)://\(host)"
        if let port = components.port {
            result += ":\(port)"
        }
        return result
    }
}

enum DeviceIdentity {
    private static let key = "com.brianbancroft.sudoku.deviceID"

    static func current() -> String {
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}
