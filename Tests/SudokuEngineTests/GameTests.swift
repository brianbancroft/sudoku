import XCTest

#if SWIFT_PACKAGE
@testable import SudokuEngine
#else
@testable import Sudoku
#endif

final class GameTests: XCTestCase {
    func testGivenCellsAreLocked() {
        var game = Fixture.game()
        let given = game.values.firstIndex { $0 != 0 }!
        let before = game.values[given]
        XCTAssertFalse(game.enterDigit(before == 1 ? 2 : 1, at: given, pencil: false))
        XCTAssertFalse(game.enterDigit(1, at: given, pencil: true))
        XCTAssertFalse(game.erase(at: given))
        XCTAssertEqual(game.values[given], before)
        XCTAssertFalse(game.canUndo)
    }

    func testSecondTapClearsAPlayerEntry() {
        var game = Fixture.game()
        let index = game.values.firstIndex(of: 0)!
        let digit = game.puzzle.solution[index]
        XCTAssertTrue(game.enterDigit(digit, at: index, pencil: false))
        XCTAssertEqual(game.values[index], digit)
        XCTAssertTrue(game.enterDigit(digit, at: index, pencil: false))
        XCTAssertEqual(game.values[index], 0)
        XCTAssertTrue(game.undo())
        XCTAssertEqual(game.values[index], digit)
    }

    func testPencilToggleAndHouseRejection() {
        var game = Fixture.game()
        let index = game.values.firstIndex(of: 0)!
        let allowed = (1...9).first { digit in
            !Grid.peers[index].contains { game.values[$0] == digit }
        }!
        XCTAssertTrue(game.enterDigit(allowed, at: index, pencil: true))
        XCTAssertEqual(game.noteDigits(at: index), [allowed])
        XCTAssertTrue(game.enterDigit(allowed, at: index, pencil: true))
        XCTAssertTrue(game.noteDigits(at: index).isEmpty)

        let blocked = game.values[Grid.peers[index].first { game.values[$0] != 0 }!]
        XCTAssertFalse(game.enterDigit(blocked, at: index, pencil: true))
        XCTAssertFalse(game.noteDigits(at: index).contains(blocked))
    }

    func testPlacingADigitClearsThatMarkInTheHouseAndUndoRestoresIt() {
        let givens = [Int](repeating: 0, count: 81)
        let puzzle = SudokuPuzzle(
            givens: givens,
            solution: SudokuGenerator.canonical,
            difficulty: .easy,
            seed: 0
        )
        var game = SudokuGame(puzzle: puzzle)
        let target = 0
        let digit = 1
        let peer = 1
        let outsider = 80

        XCTAssertTrue(game.enterDigit(digit, at: peer, pencil: true))
        XCTAssertTrue(game.enterDigit(2, at: peer, pencil: true))
        XCTAssertTrue(game.enterDigit(digit, at: outsider, pencil: true))
        XCTAssertEqual(game.noteDigits(at: peer), [1, 2])

        XCTAssertTrue(game.enterDigit(digit, at: target, pencil: false))
        XCTAssertEqual(game.values[target], digit)
        XCTAssertTrue(game.noteDigits(at: target).isEmpty)
        XCTAssertEqual(game.noteDigits(at: peer), [2])
        XCTAssertEqual(game.noteDigits(at: outsider), [digit])

        XCTAssertTrue(game.undo())
        XCTAssertEqual(game.values[target], 0)
        XCTAssertEqual(game.noteDigits(at: peer), [1, 2])
        XCTAssertEqual(game.noteDigits(at: outsider), [digit])
        XCTAssertTrue(game.redo())
        XCTAssertEqual(game.values[target], digit)
        XCTAssertEqual(game.noteDigits(at: peer), [2])
    }

    func testNewMoveDropsRedo() {
        var game = Fixture.game()
        let holes = game.values.indices.filter { game.values[$0] == 0 }
        XCTAssertTrue(game.enterDigit(game.puzzle.solution[holes[0]], at: holes[0], pencil: false))
        XCTAssertTrue(game.undo())
        XCTAssertTrue(game.canRedo)
        XCTAssertTrue(game.enterDigit(game.puzzle.solution[holes[1]], at: holes[1], pencil: false))
        XCTAssertFalse(game.canRedo)
    }

    func testUndoOfNothingIsSafe() {
        var game = Fixture.game()
        XCTAssertFalse(game.undo())
        XCTAssertFalse(game.redo())
    }

    func testRemainingCountsTrackPlacedDigits() {
        var game = Fixture.game()
        let before = game.remainingCounts
        let index = game.values.firstIndex(of: 0)!
        let digit = game.puzzle.solution[index]
        XCTAssertTrue(game.enterDigit(digit, at: index, pencil: false))
        XCTAssertEqual(game.remainingCounts[digit - 1], before[digit - 1] - 1)
    }

    func testPlayingTheSolutionWinsAndRoundTrips() {
        var game = Fixture.game(seed: 5, difficulty: .easy)
        for index in 0..<81 where game.values[index] == 0 {
            XCTAssertTrue(game.enterDigit(game.puzzle.solution[index], at: index, pencil: false))
        }
        XCTAssertTrue(game.isWon)
        XCTAssertTrue(game.solutionMismatches.isEmpty)
        XCTAssertFalse(game.enterDigit(1, at: 0, pencil: false))

        let data = try! JSONEncoder().encode(game.saved())
        let saved = try! JSONDecoder().decode(SavedGame.self, from: data)
        let restored = SudokuGame(saved: saved)
        XCTAssertEqual(restored, game)
    }

    func testWrongEntryIsASolutionMismatchWithoutAHouseConflict() {
        var game = Fixture.game()
        let index = game.values.firstIndex(of: 0)!
        let wrong = (1...9).first { digit in
            digit != game.puzzle.solution[index]
                && !Grid.peers[index].contains { game.values[$0] == digit }
        }!
        XCTAssertTrue(game.enterDigit(wrong, at: index, pencil: false))
        XCTAssertTrue(game.solutionMismatches.contains(index))
        XCTAssertFalse(game.conflicts.contains(index))
        XCTAssertFalse(game.isWon)
    }
}
