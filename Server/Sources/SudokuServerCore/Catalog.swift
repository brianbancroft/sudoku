import Foundation
import SudokuEngine

/// Pack metadata and the seeds used to build each puzzle.
/// The same seeds are what the tests validate, so a pack does not change between runs.
enum PackCatalog {
    static let bundleID = "com.brianbancroft.sudoku"

    static let packs: [PackDefinition] = [
        PackDefinition(
            id: "quiet-start",
            name: "Quiet Start",
            summary: "Six puzzles for a calm sitting. Four easy, two medium.",
            difficultyMix: "4 easy · 2 medium",
            productID: "com.brianbancroft.sudoku.pack.starter",
            puzzles: [
                PuzzleSpec(difficulty: .easy, seed: 1),
                PuzzleSpec(difficulty: .easy, seed: 2),
                PuzzleSpec(difficulty: .easy, seed: 5),
                PuzzleSpec(difficulty: .easy, seed: 7),
                PuzzleSpec(difficulty: .medium, seed: 1),
                PuzzleSpec(difficulty: .medium, seed: 2),
            ]
        ),
        PackDefinition(
            id: "hard-lines",
            name: "Hard Lines",
            summary: "Six hard puzzles, where pairs and lines start to matter.",
            difficultyMix: "6 hard",
            productID: "com.brianbancroft.sudoku.pack.hard",
            puzzles: [
                PuzzleSpec(difficulty: .hard, seed: 1),
                PuzzleSpec(difficulty: .hard, seed: 2),
                PuzzleSpec(difficulty: .hard, seed: 5),
                PuzzleSpec(difficulty: .hard, seed: 7),
                PuzzleSpec(difficulty: .hard, seed: 8),
                PuzzleSpec(difficulty: .hard, seed: 11),
            ]
        ),
        PackDefinition(
            id: "long-night",
            name: "Long Night",
            summary: "Four expert puzzles with no short path.",
            difficultyMix: "4 expert",
            productID: "com.brianbancroft.sudoku.pack.expert",
            puzzles: [
                PuzzleSpec(difficulty: .expert, seed: 1),
                PuzzleSpec(difficulty: .expert, seed: 2),
                PuzzleSpec(difficulty: .expert, seed: 5),
                PuzzleSpec(difficulty: .expert, seed: 7),
            ]
        ),
    ]

    static var productIDs: Set<String> {
        Set(packs.map(\.productID))
    }

    static func pack(id: String) -> PackDefinition? {
        packs.first { $0.id == id }
    }

    static func pack(productID: String) -> PackDefinition? {
        packs.first { $0.productID == productID }
    }

    static var summaries: [PackSummary] {
        packs.map { definition in
            PackSummary(
                id: definition.id,
                name: definition.name,
                summary: definition.summary,
                difficultyMix: definition.difficultyMix,
                puzzleCount: definition.puzzles.count,
                productID: definition.productID
            )
        }
    }
}

struct PuzzleSpec: Equatable, Sendable {
    var difficulty: Difficulty
    var seed: UInt64
}

struct PackDefinition: Equatable, Sendable {
    var id: String
    var name: String
    var summary: String
    var difficultyMix: String
    var productID: String
    var puzzles: [PuzzleSpec]
}

struct PackSummary: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var summary: String
    var difficultyMix: String
    var puzzleCount: Int
    var productID: String
}

struct StoredPuzzle: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var givens: [Int]
    var solution: [Int]
    var difficulty: Difficulty
}

struct StoredPack: Codable, Equatable, Sendable {
    var id: String
    var puzzles: [StoredPuzzle]
}

/// Builds pack grids with the same generator the app uses for free games.
final class PackLibrary: @unchecked Sendable {
    private var cache: [String: StoredPack] = [:]
    private let lock = NSLock()

    func contents(id: String) -> StoredPack? {
        lock.lock()
        if let cached = cache[id] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard let definition = PackCatalog.pack(id: id) else { return nil }
        let built = Self.build(definition)
        lock.lock()
        cache[id] = built
        lock.unlock()
        return built
    }

    func allContents() -> [StoredPack] {
        PackCatalog.packs.compactMap { contents(id: $0.id) }
    }

    private static func build(_ definition: PackDefinition) -> StoredPack {
        let puzzles = definition.puzzles.enumerated().map { index, spec in
            let puzzle = SudokuGenerator(seed: spec.seed).generate(difficulty: spec.difficulty)
            return StoredPuzzle(
                id: "\(definition.id)-\(index + 1)",
                title: "Puzzle \(index + 1)",
                givens: puzzle.givens,
                solution: puzzle.solution,
                difficulty: puzzle.difficulty
            )
        }
        return StoredPack(id: definition.id, puzzles: puzzles)
    }
}
