import XCTest

#if SWIFT_PACKAGE
@testable import SudokuEngine
#else
@testable import Sudoku
#endif

final class SolverTests: XCTestCase {
    func testCanonicalGridIsAUniqueSolution() {
        let grid = SudokuGenerator.canonical
        XCTAssertTrue(Grid.isCompleteAndValid(grid))
        XCTAssertEqual(SudokuSolver.solutionCount(of: grid, limit: 2), 1)
        XCTAssertEqual(SudokuSolver.solve(grid), grid)
    }

    func testTransformedSolutionsStayValidAndUnique() {
        for seed in [1, 2, 99, 1_000, 9_001] as [UInt64] {
            var rng = SplitMix64(seed: seed)
            let grid = SudokuGenerator.makeSolution(rng: &rng)
            XCTAssertTrue(Grid.isCompleteAndValid(grid), Grid.description(of: grid))
            XCTAssertEqual(SudokuSolver.solutionCount(of: grid, limit: 2), 1)
        }
    }

    func testRowColumnAndBoxConflicts() {
        var values = SudokuGenerator.canonical

        values[1] = values[0]
        let rowConflicts = Grid.conflictingIndices(in: values)
        XCTAssertTrue(rowConflicts.contains(0))
        XCTAssertTrue(rowConflicts.contains(1))

        values = SudokuGenerator.canonical
        values[9] = values[0]
        let columnConflicts = Grid.conflictingIndices(in: values)
        XCTAssertTrue(columnConflicts.contains(0))
        XCTAssertTrue(columnConflicts.contains(9))

        values = SudokuGenerator.canonical
        values[10] = values[0]
        let boxConflicts = Grid.conflictingIndices(in: values)
        XCTAssertTrue(boxConflicts.contains(0))
        XCTAssertTrue(boxConflicts.contains(10))
        XCTAssertFalse(Grid.isCompleteAndValid(values))
    }

    func testEmptyGridHasNoConflictsAndMultipleSolutions() {
        let empty = [Int](repeating: 0, count: 81)
        XCTAssertTrue(Grid.conflictingIndices(in: empty).isEmpty)
        XCTAssertEqual(SudokuSolver.solutionCount(of: empty, limit: 2), 2)
    }

    func testDuplicateGivenIsUnsolvable() {
        var values = [Int](repeating: 0, count: 81)
        values[0] = 5
        values[1] = 5
        XCTAssertEqual(SudokuSolver.solutionCount(of: values, limit: 2), 0)
        XCTAssertNil(SudokuSolver.solve(values))
    }

    func testSingleEmptyCellIsANakedSingle() {
        var values = SudokuGenerator.canonical
        let missing = values[40]
        values[40] = 0
        let report = HumanSolver(values: values).solve(allowing: .nakedSingle)
        XCTAssertEqual(report.outcome, .solved)
        XCTAssertEqual(report.hardest, .nakedSingle)
        XCTAssertEqual(report.values[40], missing)
    }

    func testPeersCoverTwentyCellsAndSkipSelf() {
        let peers = Grid.peers[0]
        XCTAssertEqual(peers.count, 20)
        XCTAssertFalse(peers.contains(0))
        XCTAssertTrue(peers.contains(1))
        XCTAssertTrue(peers.contains(9))
        XCTAssertTrue(peers.contains(10))
        XCTAssertTrue(peers.contains(11))
        XCTAssertFalse(peers.contains(12))
    }
}
