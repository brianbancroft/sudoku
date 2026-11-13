import XCTest

#if SWIFT_PACKAGE
@testable import SudokuEngine
#else
@testable import Sudoku
#endif

final class GeneratorTests: XCTestCase {
    func testASpreadOfSeedsMatchesTheRequestedDifficulty() {
        let seeds: [UInt64] = [2, 5, 13, 21, 34, 55, 89, 144]
        for seed in seeds {
            for difficulty in Difficulty.allCases {
                let puzzle = SudokuGenerator(seed: seed).generate(difficulty: difficulty)
                XCTAssertEqual(
                    SudokuGenerator.ratedDifficulty(of: puzzle.givens),
                    difficulty,
                    "seed \(seed) \(difficulty.rawValue) clues \(puzzle.clueCount)"
                )
                XCTAssertEqual(SudokuSolver.solutions(of: puzzle.givens, limit: 2), [puzzle.solution])
            }
        }
    }

    func testSameSeedIsDeterministic() {
        let first = SudokuGenerator(seed: 42).generate(difficulty: .medium)
        let second = SudokuGenerator(seed: 42).generate(difficulty: .medium)
        XCTAssertEqual(first, second)
    }

    func testDifferentSeedsCanDiffer() {
        let first = SudokuGenerator(seed: 1).generate(difficulty: .easy)
        let second = SudokuGenerator(seed: 2).generate(difficulty: .easy)
        XCTAssertNotEqual(first.givens, second.givens)
    }

    func testGeneratedPuzzlesAreUniqueAndMatchTheirDifficulty() {
        let seeds: [UInt64] = [1, 7, 42]
        for difficulty in Difficulty.allCases {
            for seed in seeds {
                let puzzle = SudokuGenerator(seed: seed).generate(difficulty: difficulty)
                assertPlayable(puzzle, requested: difficulty)
            }
        }
    }

    func testExpertPuzzleIsNotSolvedByListedTechniques() {
        let puzzle = SudokuGenerator(seed: 11).generate(difficulty: .expert)
        let report = HumanSolver(values: puzzle.givens).solve(allowing: .xWing)
        XCTAssertNotEqual(report.outcome, .solved)
        XCTAssertEqual(SudokuSolver.solutions(of: puzzle.givens, limit: 2), [puzzle.solution])
    }

    func testEasyPuzzleNeedsOnlyNakedSingles() {
        let puzzle = SudokuGenerator(seed: 3).generate(difficulty: .easy)
        let report = HumanSolver(values: puzzle.givens).solve(allowing: .nakedSingle)
        XCTAssertEqual(report.outcome, .solved)
        XCTAssertEqual(report.values, puzzle.solution)
        XCTAssertLessThanOrEqual(report.hardest, .nakedSingle)
    }

    private func assertPlayable(_ puzzle: SudokuPuzzle, requested: Difficulty) {
        XCTAssertEqual(puzzle.givens.count, 81)
        XCTAssertEqual(puzzle.solution.count, 81)
        XCTAssertEqual(puzzle.difficulty, requested)
        XCTAssertGreaterThan(puzzle.clueCount, 16)
        XCTAssertLessThan(puzzle.clueCount, 60)
        XCTAssertNotEqual(puzzle.givens, puzzle.solution)

        for index in 0..<81 where puzzle.givens[index] != 0 {
            XCTAssertEqual(puzzle.givens[index], puzzle.solution[index])
        }
        XCTAssertTrue(Grid.isCompleteAndValid(puzzle.solution))
        XCTAssertTrue(Grid.conflictingIndices(in: puzzle.givens).isEmpty)
        XCTAssertEqual(
            SudokuSolver.solutions(of: puzzle.givens, limit: 2),
            [puzzle.solution],
            "Seed \(puzzle.seed) \(requested.rawValue)\n\(Grid.description(of: puzzle.givens))"
        )
        XCTAssertEqual(SudokuGenerator.ratedDifficulty(of: puzzle.givens), requested)
    }
}
