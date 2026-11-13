import Foundation

public enum Difficulty: String, Codable, CaseIterable, Sendable, Equatable, Identifiable {
    case easy
    case medium
    case hard
    case expert

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        case .expert: "Expert"
        }
    }

    public var summary: String {
        switch self {
        case .easy: "Every digit has an open door."
        case .medium: "A few digits are hiding in plain sight."
        case .hard: "Pairs and lines start to matter."
        case .expert: "The obvious moves run out."
        }
    }

    var targetClues: Int {
        switch self {
        case .easy: 40
        case .medium: 33
        case .hard: 28
        case .expert: 23
        }
    }

    var minimumClues: Int {
        switch self {
        case .easy: 36
        case .medium: 29
        case .hard: 24
        case .expert: 17
        }
    }

    var acceptedClueRange: ClosedRange<Int> {
        switch self {
        case .easy: 34...48
        case .medium: 28...42
        case .hard: 23...36
        case .expert: 20...32
        }
    }

    /// Strongest technique still considered "inside" this difficulty while digging.
    var maximumTechnique: Technique {
        switch self {
        case .easy: .nakedSingle
        case .medium: .hiddenSingle
        case .hard: .xWing
        case .expert: .xWing
        }
    }
}

public struct SudokuPuzzle: Equatable, Sendable, Codable {
    public var givens: [Int]
    public var solution: [Int]
    public var difficulty: Difficulty
    /// Seed passed to the generator. Retries used to hit a difficulty stay inside that seed.
    public var seed: UInt64

    public init(givens: [Int], solution: [Int], difficulty: Difficulty, seed: UInt64) {
        self.givens = givens
        self.solution = solution
        self.difficulty = difficulty
        self.seed = seed
    }

    public var clueCount: Int {
        givens.reduce(0) { $0 + ($1 == 0 ? 0 : 1) }
    }
}

/// Builds a finished grid from a seed, then removes clues without giving the
/// puzzle a second solution. Difficulty is the hardest technique a logical
/// solve actually needs.
public struct SudokuGenerator: Sendable {
    public let seed: UInt64

    public init(seed: UInt64) {
        self.seed = seed
    }

    public func generate(difficulty: Difficulty) -> SudokuPuzzle {
        var closest: SudokuPuzzle?
        let attemptLimit = difficulty == .expert ? 40 : 24
        for attempt in 0..<attemptLimit {
            var rng = SplitMix64(seed: seed &+ UInt64(attempt) &* 0xD1B54A32D192ED03)
            let solution = Self.makeSolution(rng: &rng)
            let givens = Self.dig(solution: solution, difficulty: difficulty, rng: &rng)
            let puzzle = SudokuPuzzle(
                givens: givens,
                solution: solution,
                difficulty: difficulty,
                seed: seed
            )
            let rated = Self.ratedDifficulty(of: givens)
            let clues = puzzle.clueCount
            if rated == difficulty && difficulty.acceptedClueRange.contains(clues) {
                return puzzle
            }
            if rated == difficulty {
                closest = puzzle
            } else if closest == nil {
                closest = puzzle
            }
        }
        if let closest, Self.ratedDifficulty(of: closest.givens) == difficulty {
            return closest
        }
        // A unique puzzle is guaranteed even when a narrow band was elusive.
        // Keep searching a little longer before accepting a neighbor.
        for attempt in attemptLimit..<(attemptLimit + 20) {
            var rng = SplitMix64(seed: seed &+ UInt64(attempt) &* 0xD1B54A32D192ED03)
            let solution = Self.makeSolution(rng: &rng)
            let givens = Self.dig(solution: solution, difficulty: difficulty, rng: &rng)
            if Self.ratedDifficulty(of: givens) == difficulty {
                return SudokuPuzzle(givens: givens, solution: solution, difficulty: difficulty, seed: seed)
            }
        }
        if let closest {
            let found = SudokuSolver.solutions(of: closest.givens, limit: 2)
            if found.count == 1 {
                return SudokuPuzzle(
                    givens: closest.givens,
                    solution: found[0],
                    difficulty: Self.ratedDifficulty(of: closest.givens),
                    seed: seed
                )
            }
        }
        var rng = SplitMix64(seed: seed)
        let solution = Self.makeSolution(rng: &rng)
        let givens = Self.dig(solution: solution, difficulty: .easy, rng: &rng)
        return SudokuPuzzle(givens: givens, solution: solution, difficulty: .easy, seed: seed)
    }

    public static func ratedDifficulty(of givens: [Int]) -> Difficulty {
        let report = HumanSolver(values: givens).solve(allowing: .xWing)
        if report.outcome != .solved {
            guard SudokuSolver.solutionCount(of: givens, limit: 2) == 1 else {
                return .expert
            }
            return .expert
        }
        return report.hardest.difficulty
    }

    // MARK: - Completed grids

    static let canonical: [Int] = [
        1, 2, 3, 4, 5, 6, 7, 8, 9,
        4, 5, 6, 7, 8, 9, 1, 2, 3,
        7, 8, 9, 1, 2, 3, 4, 5, 6,
        2, 3, 4, 5, 6, 7, 8, 9, 1,
        5, 6, 7, 8, 9, 1, 2, 3, 4,
        8, 9, 1, 2, 3, 4, 5, 6, 7,
        3, 4, 5, 6, 7, 8, 9, 1, 2,
        6, 7, 8, 9, 1, 2, 3, 4, 5,
        9, 1, 2, 3, 4, 5, 6, 7, 8,
    ]

    static func makeSolution(rng: inout SplitMix64) -> [Int] {
        var digitMap = Array(1...9)
        rng.shuffle(&digitMap)

        var bandOrder = [0, 1, 2]
        rng.shuffle(&bandOrder)
        var rowsInBand = [[0, 1, 2], [0, 1, 2], [0, 1, 2]]
        for band in 0..<3 { rng.shuffle(&rowsInBand[band]) }

        var stackOrder = [0, 1, 2]
        rng.shuffle(&stackOrder)
        var columnsInStack = [[0, 1, 2], [0, 1, 2], [0, 1, 2]]
        for stack in 0..<3 { rng.shuffle(&columnsInStack[stack]) }

        var rows: [Int] = []
        for band in bandOrder {
            for offset in rowsInBand[band] {
                rows.append(band * 3 + offset)
            }
        }
        var columns: [Int] = []
        for stack in stackOrder {
            for offset in columnsInStack[stack] {
                columns.append(stack * 3 + offset)
            }
        }

        let transpose = rng.next() & 1 == 1
        var grid = [Int](repeating: 0, count: Grid.cellCount)
        for row in 0..<9 {
            for column in 0..<9 {
                let source = canonical[rows[row] * 9 + columns[column]]
                let digit = digitMap[source - 1]
                if transpose {
                    grid[column * 9 + row] = digit
                } else {
                    grid[row * 9 + column] = digit
                }
            }
        }
        return grid
    }

    // MARK: - Digging

    private static func dig(solution: [Int], difficulty: Difficulty, rng: inout SplitMix64) -> [Int] {
        var grid = solution
        var pairs = symmetricPairs()
        rng.shuffle(&pairs)
        for pair in pairs {
            if clueCount(grid) <= difficulty.targetClues { break }
            _ = remove(pair, from: &grid, solution: solution, difficulty: difficulty)
        }

        var order = Array(0..<Grid.cellCount)
        rng.shuffle(&order)
        for index in order where grid[index] != 0 {
            if clueCount(grid) <= difficulty.targetClues { break }
            _ = remove([index], from: &grid, solution: solution, difficulty: difficulty)
        }

        if difficulty != .easy {
            forceAboveEasyBand(&grid, solution: solution, difficulty: difficulty, rng: &rng)
        }
        return grid
    }

    /// Keeps taking clues away when the puzzle is still easier than requested,
    /// and puts a clue back when a removal jumps past the requested band.
    private static func forceAboveEasyBand(
        _ grid: inout [Int],
        solution: [Int],
        difficulty: Difficulty,
        rng: inout SplitMix64
    ) {
        var order = grid.indices.filter { grid[$0] != 0 }
        rng.shuffle(&order)
        for index in order {
            if clueCount(grid) <= difficulty.minimumClues { break }
            if band(of: grid, solution: solution) == difficulty { break }
            let saved = grid[index]
            grid[index] = 0
            if band(of: grid, solution: solution) == nil {
                grid[index] = saved
                continue
            }
            let rating = band(of: grid, solution: solution)
            if let rating, difficultyRank(rating) > difficultyRank(difficulty) {
                grid[index] = saved
            }
        }
    }

    /// Difficulty actually required, or nil when the grid is not the unique solution.
    private static func band(of grid: [Int], solution: [Int]) -> Difficulty? {
        let report = HumanSolver(values: grid).solve(allowing: .xWing)
        if report.outcome == .solved {
            return report.values == solution ? report.hardest.difficulty : nil
        }
        let found = SudokuSolver.solutions(of: grid, limit: 2)
        guard found.count == 1, found[0] == solution else { return nil }
        return .expert
    }

    private static func difficultyRank(_ difficulty: Difficulty) -> Int {
        switch difficulty {
        case .easy: 0
        case .medium: 1
        case .hard: 2
        case .expert: 3
        }
    }

    private static func remove(
        _ cells: [Int],
        from grid: inout [Int],
        solution: [Int],
        difficulty: Difficulty
    ) -> Bool {
        let nextCount = clueCount(grid) - cells.count
        guard nextCount >= difficulty.minimumClues else { return false }
        var saved: [(Int, Int)] = []
        for index in cells where grid[index] != 0 {
            saved.append((index, grid[index]))
            grid[index] = 0
        }
        guard !saved.isEmpty else { return false }
        if keepsContract(grid, solution: solution, difficulty: difficulty) {
            return true
        }
        for (index, value) in saved {
            grid[index] = value
        }
        return false
    }

    private static func keepsContract(_ grid: [Int], solution: [Int], difficulty: Difficulty) -> Bool {
        switch difficulty {
        case .easy:
            let report = HumanSolver(values: grid).solve(allowing: .nakedSingle)
            return report.outcome == .solved && report.values == solution
        case .medium:
            let report = HumanSolver(values: grid).solve(allowing: .hiddenSingle)
            return report.outcome == .solved && report.values == solution
        case .hard:
            let report = HumanSolver(values: grid).solve(allowing: .xWing)
            return report.outcome == .solved && report.values == solution
        case .expert:
            let found = SudokuSolver.solutions(of: grid, limit: 2)
            return found.count == 1 && found[0] == solution
        }
    }

    private static func symmetricPairs() -> [[Int]] {
        var pairs: [[Int]] = []
        var seen = Set<Int>()
        for index in 0..<Grid.cellCount {
            if seen.contains(index) { continue }
            let opposite = 80 - index
            seen.insert(index)
            seen.insert(opposite)
            if index == opposite {
                pairs.append([index])
            } else {
                pairs.append([index, opposite])
            }
        }
        return pairs
    }

    private static func clueCount(_ grid: [Int]) -> Int {
        grid.reduce(0) { $0 + ($1 == 0 ? 0 : 1) }
    }
}
