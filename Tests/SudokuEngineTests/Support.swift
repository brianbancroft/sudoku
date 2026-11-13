import XCTest

#if SWIFT_PACKAGE
@testable import SudokuEngine
#else
@testable import Sudoku
#endif

enum Fixture {
    static func puzzle(seed: UInt64 = 1, difficulty: Difficulty = .easy) -> SudokuPuzzle {
        SudokuGenerator(seed: seed).generate(difficulty: difficulty)
    }

    static func game(seed: UInt64 = 1, difficulty: Difficulty = .easy) -> SudokuGame {
        SudokuGame(puzzle: puzzle(seed: seed, difficulty: difficulty))
    }
}

func XCTAssertNoDecimalDigits(
    _ message: String,
    _ comment: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertNil(
        message.rangeOfCharacter(from: .decimalDigits),
        "Hint copy should not name a digit. \(comment) Message: \(message)",
        file: file,
        line: line
    )
}
