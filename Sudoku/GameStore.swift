import Foundation
import Observation
import SwiftUI

enum MistakeChecking: String, Codable, CaseIterable, Identifiable {
    case off
    case conflicts
    case solution

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .conflicts: "House conflicts"
        case .solution: "Check the solution"
        }
    }

    var explanation: String {
        switch self {
        case .off:
            "Nothing is marked. A finished grid still has to be a valid Sudoku."
        case .conflicts:
            "A digit that repeats in its row, column, or box is underlined."
        case .solution:
            "An entry that doesn't match this puzzle's answer is underlined. Given digits are left alone."
        }
    }
}

struct Settings: Equatable {
    var mistakes: MistakeChecking = .conflicts
    var hintsEnabled = true
    var highlightSameNumber = true
    var highlightHouses = true
    var packServerURL = ServerBaseURL.fallback

    init() {}
}

extension Settings: Codable {
    enum CodingKeys: String, CodingKey {
        case mistakes, hintsEnabled, highlightSameNumber, highlightHouses, packServerURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mistakes = try container.decodeIfPresent(MistakeChecking.self, forKey: .mistakes) ?? .conflicts
        hintsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hintsEnabled) ?? true
        highlightSameNumber = try container.decodeIfPresent(Bool.self, forKey: .highlightSameNumber) ?? true
        highlightHouses = try container.decodeIfPresent(Bool.self, forKey: .highlightHouses) ?? true
        packServerURL = try container.decodeIfPresent(String.self, forKey: .packServerURL) ?? ServerBaseURL.fallback
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mistakes, forKey: .mistakes)
        try container.encode(hintsEnabled, forKey: .hintsEnabled)
        try container.encode(highlightSameNumber, forKey: .highlightSameNumber)
        try container.encode(highlightHouses, forKey: .highlightHouses)
        try container.encode(packServerURL, forKey: .packServerURL)
    }
}

struct PackPuzzleContext: Codable, Equatable {
    var packID: String
    var packName: String
    var puzzleID: String
    var puzzleTitle: String
}

enum PlayBanner: Equatable {
    case hint(Hint)
    case note(String)
}

@MainActor
@Observable
final class GameStore {
    private(set) var game: SudokuGame?
    var settings: Settings
    var lastDifficulty: Difficulty
    var selection: Int?
    var pencilMode = false
    var banner: PlayBanner?
    var elapsed: TimeInterval = 0
    var userPaused = false
    var path: [AppRoute] = []
    var showSettings = false
    var confirmNewGame = false
    var confirmPackPlay = false
    var isGenerating = false
    var moveCount = 0
    var packContext: PackPuzzleContext?

    private var runningSince: Date?
    private var pendingDifficulty: Difficulty
    private var pendingPack: (puzzle: DownloadedPuzzle, packName: String, packID: String)?
    private let persists: Bool

    var isGameVisible: Bool {
        path.contains(.game)
    }

    init() {
        persists = true
        let snapshot = Self.load()
        settings = snapshot?.settings ?? Settings()
        lastDifficulty = snapshot?.lastDifficulty ?? .medium
        pendingDifficulty = lastDifficulty
        if let saved = snapshot?.savedGame, Self.isPlayable(saved) {
            game = SudokuGame(saved: saved)
            elapsed = snapshot?.elapsed ?? 0
            userPaused = snapshot?.userPaused ?? false
            if let selection = snapshot?.selection, Grid.isValidIndex(selection) {
                self.selection = selection
            }
            pencilMode = snapshot?.pencilMode ?? false
            packContext = snapshot?.packContext
        }
    }

    init(preview puzzle: SudokuPuzzle) {
        persists = false
        settings = Settings()
        lastDifficulty = puzzle.difficulty
        pendingDifficulty = puzzle.difficulty
        game = SudokuGame(puzzle: puzzle)
        path = [.game]
        elapsed = 72
        runningSince = Date()
        selection = nil
    }

    var hasWon: Bool { game?.isWon == true }

    var showsPause: Bool {
        userPaused && game?.isWon != true && isGameVisible
    }

    func displayedElapsed(at date: Date = .now) -> TimeInterval {
        var total = elapsed
        if let runningSince {
            let delta = date.timeIntervalSince(runningSince)
            if delta > 0 { total += delta }
        }
        return total
    }

    func formattedTime(at date: Date = .now) -> String {
        TimeFormat.clock(displayedElapsed(at: date))
    }

    func spokenTime(at date: Date = .now) -> String {
        TimeFormat.spoken(displayedElapsed(at: date))
    }

    func selectDifficulty(_ difficulty: Difficulty) {
        lastDifficulty = difficulty
        persistIfNeeded()
    }

    func save() {
        persistIfNeeded()
    }

    func requestNewGame() {
        pendingDifficulty = lastDifficulty
        if let game, !game.isWon {
            confirmNewGame = true
        } else {
            startNewGame()
        }
    }

    func startNewGame() {
        let difficulty = pendingDifficulty
        guard !isGenerating else { return }
        confirmNewGame = false
        isGenerating = true
        banner = nil
        var generator = SystemRandomNumberGenerator()
        let seed = generator.next()
        Task {
            let puzzle = await Task.detached(priority: .userInitiated) {
                SudokuGenerator(seed: seed).generate(difficulty: difficulty)
            }.value
            install(puzzle)
        }
    }

    func startNewGame(matching difficulty: Difficulty) {
        lastDifficulty = difficulty
        pendingDifficulty = difficulty
        startNewGame()
    }

    func openCurrentGame() {
        guard game != nil, !isGenerating else { return }
        if !path.contains(.game) {
            path = [.game]
        }
        resumeIfAllowed()
    }

    func leaveGame() {
        noteGameClosed()
        path.removeAll { $0 == .game }
    }

    func noteGameClosed() {
        foldTime(stopping: true)
        banner = nil
        persistIfNeeded()
    }

    func requestPackPuzzle(_ puzzle: DownloadedPuzzle, packID: String, packName: String) {
        pendingPack = (puzzle, packName, packID)
        if let game, !game.isWon {
            confirmPackPlay = true
        } else {
            beginPendingPack()
        }
    }

    func beginPendingPack() {
        guard let pending = pendingPack else { return }
        confirmPackPlay = false
        let puzzle = SudokuPuzzle(
            givens: pending.puzzle.givens,
            solution: pending.puzzle.solution,
            difficulty: pending.puzzle.difficulty,
            seed: 0
        )
        install(puzzle, pack: PackPuzzleContext(
            packID: pending.packID,
            packName: pending.packName,
            puzzleID: pending.puzzle.id,
            puzzleTitle: pending.puzzle.title
        ))
        pendingPack = nil
    }

    func select(_ index: Int) {
        guard game != nil, Grid.isValidIndex(index) else { return }
        selection = selection == index ? nil : index
        persistIfNeeded()
    }

    func input(digit: Int) {
        guard var game, let selection, !game.isWon else { return }
        guard game.enterDigit(digit, at: selection, pencil: pencilMode) else { return }
        self.game = game
        afterMove()
    }

    func erase() {
        guard var game, let selection, !game.isWon else { return }
        guard game.erase(at: selection) else { return }
        self.game = game
        afterMove()
    }

    func undo() {
        guard var game, !game.isWon else { return }
        guard game.undo() else { return }
        self.game = game
        afterMove()
    }

    func redo() {
        guard var game else { return }
        guard game.redo() else { return }
        self.game = game
        afterMove()
    }

    func togglePencil() {
        pencilMode.toggle()
        persistIfNeeded()
    }

    func requestHint() {
        guard let game, !game.isWon else { return }
        guard settings.hintsEnabled else {
            banner = .note("Hints are off. You can turn them on in Settings.")
            return
        }
        if let hint = game.makeHint() {
            banner = .hint(hint)
            if let cell = hint.highlightedCells.first {
                selection = cell
            }
        } else {
            banner = .note("No hint from here.")
        }
    }

    func confirmReveal() {
        guard var game, case .hint(let hint) = banner else { return }
        guard game.reveal(hint) else { return }
        self.game = game
        afterMove()
    }

    func dismissBanner() {
        banner = nil
    }

    func togglePause() {
        guard game?.isWon != true else { return }
        if userPaused {
            userPaused = false
            resumeIfAllowed()
        } else {
            userPaused = true
            foldTime(stopping: true)
        }
        persistIfNeeded()
    }

    func checkpoint() {
        guard runningSince != nil else { return }
        foldTime(stopping: false)
        persistIfNeeded()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if isGameVisible { resumeIfAllowed() }
        case .inactive, .background:
            foldTime(stopping: true)
            persistIfNeeded()
        @unknown default:
            break
        }
    }

    var markedErrors: Set<Int> {
        guard let game else { return [] }
        switch settings.mistakes {
        case .off:
            return []
        case .conflicts:
            return game.conflicts
        case .solution:
            return game.solutionMismatches
        }
    }

    var relatedCells: Set<Int> {
        guard settings.highlightHouses, let selection else { return [] }
        return Set(Grid.peers[selection])
    }

    var sameNumberCells: Set<Int> {
        guard settings.highlightSameNumber, let game, let selection else { return [] }
        let value = game.values[selection]
        guard value != 0 else { return [] }
        var cells = Set<Int>()
        for index in game.values.indices where index != selection && game.values[index] == value {
            cells.insert(index)
        }
        return cells
    }

    var hintCells: Set<Int> {
        guard case .hint(let hint) = banner else { return [] }
        return Set(hint.highlightedCells)
    }

    var hintHouseCells: Set<Int> {
        guard case .hint(let hint) = banner, let house = hint.house else { return [] }
        return Set(house.cells)
    }

    var emphasisDigit: Int? {
        guard case .hint(let hint) = banner else { return nil }
        return hint.emphasisDigit
    }

    var inputEnabled: Bool {
        guard let game, let selection, !game.isWon else { return false }
        return !game.isGiven(selection)
    }

    private func install(_ puzzle: SudokuPuzzle, pack: PackPuzzleContext? = nil) {
        game = SudokuGame(puzzle: puzzle)
        packContext = pack
        selection = nil
        pencilMode = false
        banner = nil
        elapsed = 0
        runningSince = Date()
        userPaused = false
        isGenerating = false
        if !path.contains(.game) {
            path.append(.game)
        }
        moveCount += 1
        persistIfNeeded()
    }

    private func afterMove() {
        banner = nil
        if game?.isWon == true {
            foldTime(stopping: true)
            userPaused = false
        }
        moveCount += 1
        persistIfNeeded()
    }

    private func resumeIfAllowed() {
        guard isGameVisible, !userPaused, game?.isWon != true, runningSince == nil else { return }
        runningSince = Date()
    }

    private func foldTime(stopping: Bool) {
        if let start = runningSince {
            let delta = Date().timeIntervalSince(start)
            if delta > 0 { elapsed += delta }
            runningSince = stopping ? nil : Date()
        }
    }

    private func persistIfNeeded() {
        guard persists else { return }
        let snapshot = Snapshot(
            version: 1,
            savedGame: game?.saved(),
            elapsed: displayedElapsed(),
            userPaused: userPaused,
            selection: selection,
            pencilMode: pencilMode,
            settings: settings,
            lastDifficulty: lastDifficulty,
            packContext: packContext
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func isPlayable(_ saved: SavedGame) -> Bool {
        saved.values.count == Grid.cellCount
            && saved.notes.count == Grid.cellCount
            && saved.puzzle.givens.count == Grid.cellCount
            && saved.puzzle.solution.count == Grid.cellCount
    }

    private static func load() -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private static let storageKey = "com.brianbancroft.sudoku.session"
}

private struct Snapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, savedGame, elapsed, userPaused, selection, pencilMode, settings, lastDifficulty, packContext
    }

    var version: Int
    var savedGame: SavedGame?
    var elapsed: TimeInterval
    var userPaused: Bool
    var selection: Int?
    var pencilMode: Bool
    var settings: Settings
    var lastDifficulty: Difficulty
    var packContext: PackPuzzleContext?

    init(
        version: Int,
        savedGame: SavedGame?,
        elapsed: TimeInterval,
        userPaused: Bool,
        selection: Int?,
        pencilMode: Bool,
        settings: Settings,
        lastDifficulty: Difficulty,
        packContext: PackPuzzleContext?
    ) {
        self.version = version
        self.savedGame = savedGame
        self.elapsed = elapsed
        self.userPaused = userPaused
        self.selection = selection
        self.pencilMode = pencilMode
        self.settings = settings
        self.lastDifficulty = lastDifficulty
        self.packContext = packContext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        savedGame = try container.decodeIfPresent(SavedGame.self, forKey: .savedGame)
        elapsed = try container.decodeIfPresent(TimeInterval.self, forKey: .elapsed) ?? 0
        userPaused = try container.decodeIfPresent(Bool.self, forKey: .userPaused) ?? false
        selection = try container.decodeIfPresent(Int.self, forKey: .selection)
        pencilMode = try container.decodeIfPresent(Bool.self, forKey: .pencilMode) ?? false
        settings = try container.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        lastDifficulty = try container.decodeIfPresent(Difficulty.self, forKey: .lastDifficulty) ?? .medium
        packContext = try container.decodeIfPresent(PackPuzzleContext.self, forKey: .packContext)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(savedGame, forKey: .savedGame)
        try container.encode(elapsed, forKey: .elapsed)
        try container.encode(userPaused, forKey: .userPaused)
        try container.encodeIfPresent(selection, forKey: .selection)
        try container.encode(pencilMode, forKey: .pencilMode)
        try container.encode(settings, forKey: .settings)
        try container.encode(lastDifficulty, forKey: .lastDifficulty)
        try container.encodeIfPresent(packContext, forKey: .packContext)
    }
}
