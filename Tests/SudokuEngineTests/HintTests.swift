import XCTest

#if SWIFT_PACKAGE
@testable import SudokuEngine
#else
@testable import Sudoku
#endif

final class HintTests: XCTestCase {
    func testFirstHintDoesNotFillTheCell() {
        let game = Fixture.game(seed: 4, difficulty: .easy)
        let before = game.values
        let hint = game.makeHint()
        XCTAssertNotNil(hint)
        XCTAssertEqual(game.values, before)
        XCTAssertNoDecimalDigits(hint?.message ?? "")
        XCTAssertNotNil(hint?.reveal)
    }

    func testConfirmingAHintPlacesTheSolutionDigitAndUndoReversesIt() {
        var game = Fixture.game(seed: 4, difficulty: .easy)
        guard let hint = game.makeHint(), let reveal = hint.reveal else {
            return XCTFail("Expected a revealable hint")
        }
        XCTAssertTrue(game.reveal(hint))
        XCTAssertEqual(game.values[reveal.index], reveal.digit)
        XCTAssertEqual(game.values[reveal.index], game.puzzle.solution[reveal.index])
        XCTAssertEqual(game.hintsUsed, 1)
        XCTAssertTrue(game.undo())
        XCTAssertNotEqual(game.values[reveal.index], reveal.digit)
        XCTAssertEqual(game.hintsUsed, 0)
        XCTAssertTrue(game.redo())
        XCTAssertEqual(game.hintsUsed, 1)
    }

    func testEasyHintIsANakedSingleAndNamesNoDigit() {
        let game = Fixture.game(seed: 8, difficulty: .easy)
        let hint = game.makeHint()
        XCTAssertEqual(hint?.kind, .nakedSingle)
        XCTAssertEqual(hint?.highlightedCells.count, 1)
        XCTAssertNoDecimalDigits(hint?.message ?? "")
        if let index = hint?.highlightedCells.first {
            XCTAssertEqual(game.values[index], 0)
            XCTAssertEqual(hint?.emphasisDigit, game.puzzle.solution[index])
        }
    }

    func testIncorrectEntryIsPointedOutWithoutRevealingUntilAsked() {
        var game = Fixture.game(seed: 6, difficulty: .medium)
        let index = game.values.firstIndex(of: 0)!
        let wrong = (1...9).first { $0 != game.puzzle.solution[index] }!
        XCTAssertTrue(game.enterDigit(wrong, at: index, pencil: false))
        let before = game.values
        let hint = game.makeHint()
        XCTAssertEqual(hint?.kind, .incorrectEntry)
        XCTAssertEqual(hint?.highlightedCells, [index])
        XCTAssertNil(hint?.emphasisDigit)
        XCTAssertEqual(hint?.reveal?.digit, game.puzzle.solution[index])
        XCTAssertNoDecimalDigits(hint?.message ?? "")
        XCTAssertEqual(game.values, before)

        XCTAssertTrue(game.reveal(hint!))
        XCTAssertEqual(game.values[index], game.puzzle.solution[index])
    }

    func testMediumHintEventuallyShowsAHiddenSingle() {
        var game = Fixture.game(seed: 9, difficulty: .medium)
        var sawHiddenSingle = false
        for _ in 0..<81 {
            guard let hint = game.makeHint() else { break }
            XCTAssertNoDecimalDigits(hint.message)
            if hint.kind == .hiddenSingle {
                sawHiddenSingle = true
                XCTAssertNotNil(hint.house)
                XCTAssertNotNil(hint.emphasisDigit)
                break
            }
            XCTAssertEqual(hint.kind, .nakedSingle)
            XCTAssertTrue(game.reveal(hint))
        }
        XCTAssertTrue(sawHiddenSingle)
    }

    func testHintOnAFinishedPuzzleIsNil() {
        var game = Fixture.game(seed: 2, difficulty: .easy)
        for index in 0..<81 where game.values[index] == 0 {
            _ = game.enterDigit(game.puzzle.solution[index], at: index, pencil: false)
        }
        XCTAssertTrue(game.isWon)
        XCTAssertNil(game.makeHint())
        XCTAssertFalse(game.reveal(Hint(
            kind: .nakedSingle,
            message: "Done",
            highlightedCells: [0],
            house: nil,
            emphasisDigit: 1,
            reveal: CellPlacement(index: 0, digit: 1)
        )))
    }
}
