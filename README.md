# Sudoku

A quiet Sudoku game for iPhone. Every new game is generated on the device, has one solution, and stays on the phone. There are no accounts and no streaks. Optional puzzle packs are bought with Apple In-App Purchase. The generator on the home screen stays free.

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

That covers unique generation, validation, pencil marks, undo and redo, hints, pack puzzles, and the pack server. In Xcode, Product > Test runs the game tests inside the `SudokuTests` target. `swift test` also runs `SudokuServerTests`.

## Layout

`Sources/SudokuEngine` is the game. It owns the grid, the exact solver, the logical solver used for difficulty and hints, the generator, and the rules for notes, undo, and reveal. `Sudoku` is the SwiftUI app: screens, timer, and the saved game. The two stay apart so the rules can be tested without launching the interface.

Difficulty follows the hardest step the logical solver actually needs:

- Easy is naked singles.
- Medium needs a hidden single.
- Hard needs a pair, a pointing line, a box reduction, or an X-wing.
- Expert still has one solution, and those steps are not enough.

Generation is deterministic for a seed. The app picks a random seed for each new game.

## Puzzle packs

Packs are digital content, so the app uses StoreKit 2. There is no Stripe checkout and no link out to a payment page. The project does not contain an App Store Connect product, a signing team, or a paid capability.

The scheme points at `Sudoku/Products.storekit`. In Xcode, run on an iPhone simulator and the store uses those local products. No real charge is made.

1. Start the pack server (below) on the Mac.
2. Run the app. The simulator reaches the Mac at `http://127.0.0.1:8787`.
3. Open Puzzle packs, buy Quiet Start, Hard Lines, or Long Night, and choose a puzzle.
4. Restore purchases asks StoreKit for entitlements already on this Apple ID, then downloads any pack that is not on the phone yet.

If the server is down, a pack that is already downloaded still opens. StoreKit remains the record of ownership. A purchase that has not downloaded yet stays unfinished until the server can deliver it, and `Transaction.updates` tries again. Change the server address in Settings. `http` is only accepted for `127.0.0.1` and `localhost`.

### Pack server

The server is a small Swift program in `Server/`. It is not Vapor or Hummingbird: four JSON routes do not need that stack, and the tests run with the same toolchain as the engine. It does not take payment. It checks the signed StoreKit transaction and then sends the puzzles.

```sh
swift test --filter SudokuServerTests
swift run SudokuServer
```

`swift run` listens on `http://127.0.0.1:8787`. `PORT` changes the port. Granted transactions are recorded in `data/entitlements.json`, which is gitignored.

`SUDOKU_IAP_MODE` defaults to `dev`. Dev mode accepts Xcode StoreKit configuration transactions (`"environment":"Xcode"`) after checking the JWS shape, bundle id `com.brianbancroft.sudoku`, a known product id, and that the purchase is not revoked. That is not Apple's production signature. Do not put this process on the public internet.

`SUDOKU_IAP_MODE=production` rejects Xcode transactions and refuses Sandbox and Production transactions until verification is configured outside the repo. No Apple key is committed.

### What real App Store sales need later

- An Apple Developer Program membership, a signing team chosen only on your Mac, and a bundle id that matches `com.brianbancroft.sudoku`.
- Paid Apps agreement, tax, and banking in App Store Connect.
- Three non-consumable products with the same ids as `Products.storekit`: `com.brianbancroft.sudoku.pack.starter`, `com.brianbancroft.sudoku.pack.hard`, and `com.brianbancroft.sudoku.pack.expert`.
- A hosted copy of this server with `SUDOKU_IAP_MODE=production`. Verify each JWS with Apple's App Store Server API (Get Transaction Info), using an issuer id, a key id, and a `.p8` that stays out of the repo. Or check the certificate chain in the JWS against Apple Root CA - G3.
- The phone's Settings field pointed at that `https` host.

## Settings

Mistake checking can be off, limited to a digit repeated in a house, or compared with this puzzle's solution. Hints, same-digit highlighting, and house highlighting can each be turned off. Defaults mark house conflicts, leave hints on, and highlight related cells. Errors also draw a short bar under the digit, so the mark is not color alone.

## Color

The interface is blush and raspberry in both light and dark mode. Digits and controls were checked against WCAG 2.1 AA (4.5:1 for text). Measured pairs:

| Pair | Light | Dark |
| --- | --- | --- |
| Given digits on the board | 13.6:1 | 12.9:1 |
| Entered digits on the board | 8.1:1 | 9.8:1 |
| Pencil marks on the board | 8.3:1 | 11.1:1 |
| Secondary text on the page | 6.7:1 | 6.3:1 |
| Button label on the raspberry button | 8.2:1 | 9.4:1 |
| Error digit on the error wash | 7.4:1 | 8.3:1 |
| Entered digit on the selection wash | 5.5:1 | 6.1:1 |

The screen mockups live in `docs/design/`.
