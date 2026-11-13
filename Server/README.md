# Puzzle pack server

A small Swift HTTP server for the Sudoku app. It does not take payment. The iPhone app buys packs with StoreKit 2, then sends the signed transaction here to download the puzzles.

Vapor or Hummingbird would pull in a large server stack for four JSON routes. This server is the engine plus a short localhost listener, so `swift test` in this folder runs with the same toolchain as the game.

From the repository root:

```sh
swift test --filter SudokuServerTests
swift run SudokuServer
```

The server target lives in this folder and is part of the root Swift package, so the checkout directory name does not matter. The process listens on `http://127.0.0.1:8787`. Override the port with `PORT`. Run it from the repository root so entitlements land in `Server/data/entitlements.json` (or set `ENTITLEMENTS_PATH`). That file is local state, not a secret, and it is gitignored.

`SUDOKU_IAP_MODE` defaults to `dev`. Dev mode accepts StoreKit configuration transactions whose payload says `"environment":"Xcode"`. It checks the JWS shape, the bundle id, the product id, and that the purchase is not revoked. It does not treat that as Apple's production signature. Do not expose this process beyond your computer.

`SUDOKU_IAP_MODE=production` rejects Xcode transactions and refuses Production or Sandbox transactions until Apple verification is configured outside this repo. See the main README.
