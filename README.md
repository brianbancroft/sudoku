# Sudoku

A quiet Sudoku game for iPhone. Every new game is generated on the device, has one solution, and stays on the phone. There are no accounts, streaks, or purchases.

## Play

Open a puzzle from the home screen. Choose Easy, Medium, Hard, or Expert, then tap New game. The timer starts when the grid appears and pauses when you leave the game, lock the phone, or tap pause.

- Tap a cell, then a number. Tap that same number again to clear what you entered.
- Given clues are darker and heavier, and they cannot be changed.
- Notes toggles pencil marks. A mark disappears when that digit is placed in the same row, column, or box.
- The small figure under each number is how many of that digit are still missing.
- Hint describes a cell or a pattern. Reveal digit fills an answer only after you ask.
- The grid is complete when every digit is in place and the board is a valid Sudoku.

A game in progress is saved on this phone and restored the next time the app opens.

## Open in Xcode

1. Open `Sudoku.xcodeproj` on a Mac with Xcode 15 or later.
2. Choose an iPhone simulator. The app targets iOS 17 and iPhone portrait.
3. Run.

No Apple Developer team is selected, and the project does not enable paid capabilities. A simulator run does not need a signing team. To install on a phone, pick your Personal Team in Signing & Capabilities. Leave that choice out of git so the project stays free of a committed team id.

## Tests

The puzzle engine has no UI dependency. From the repository root:

```sh
swift test
```

That covers unique generation, validation, pencil marks, undo and redo, and hints. In Xcode, Product > Test runs the same files inside the `SudokuTests` target.

## Layout

`Sources/SudokuEngine` is the game. It owns the grid, the exact solver, the logical solver used for difficulty and hints, the generator, and the rules for notes, undo, and reveal. `Sudoku` is the SwiftUI app: screens, timer, and the saved game. The two stay apart so the rules can be tested without launching the interface.

Difficulty follows the hardest step the logical solver actually needs:

- Easy is naked singles.
- Medium needs a hidden single.
- Hard needs a pair, a pointing line, a box reduction, or an X-wing.
- Expert still has one solution, and those steps are not enough.

Generation is deterministic for a seed. The app picks a random seed for each new game.

## Settings

Mistake checking can be off, limited to a digit repeated in a house, or compared with this puzzle's solution. Hints, same-digit highlighting, and house highlighting can each be turned off. Defaults mark house conflicts, leave hints on, and highlight related cells.
