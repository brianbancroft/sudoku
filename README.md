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

That covers unique generation, validation, pencil marks, undo and redo, and hints. In Xcode, Product > Test runs the game tests inside the `SudokuTests` target.

The pack Worker has its own tests:

```sh
cd cloudflare
npm install
npm test
```

Those run in the Workers runtime. They check a fixture certificate chain (a throwaway test CA, not an Apple key), a purchase that unlocks a pack, and that `/admin` rejects a request with no session.

## Layout

`Sources/SudokuEngine` is the game. It owns the grid, the exact solver, the logical solver used for difficulty and hints, the generator, and the rules for notes, undo, and reveal. `Sudoku` is the SwiftUI app: screens, timer, and the saved game. `cloudflare/` is the Worker that checks a StoreKit signature and sends a purchased pack. The engine stays separate so the rules can be tested without launching the interface or the Worker.

Difficulty follows the hardest step the logical solver actually needs:

- Easy is naked singles.
- Medium needs a hidden single.
- Hard needs a pair, a pointing line, a box reduction, or an X-wing.
- Expert still has one solution, and those steps are not enough.

Generation is deterministic for a seed. The app picks a random seed for each new game.

## Puzzle packs

Packs are digital content, so the app uses StoreKit 2. There is no Stripe checkout and no link out to a payment page. The project does not contain an App Store Connect product, a signing team, or a paid capability.

The scheme points at `Sudoku/Products.storekit`. In Xcode, run on an iPhone simulator and the store uses those local products. No real charge is made.

1. In `cloudflare/`, run `npx wrangler dev --port 8787`. Copy `.dev.vars.example` to `.dev.vars` first and set `ALLOW_XCODE_JWS=true`, or the simulator's StoreKit configuration signature is rejected.
2. Run the app from Xcode on an iPhone simulator. The Debug build setting `SUDOKU_PACK_SERVER_URL` is `http://127.0.0.1:8787`.
3. Open Puzzle packs, buy Quiet Start, Hard Lines, or Long Night, and choose a puzzle.
4. Restore purchases asks StoreKit for entitlements already on this Apple ID, then downloads any pack that is not on the phone yet.

If the Worker is down, a pack that is already downloaded still opens. StoreKit remains the record of ownership. A purchase that has not downloaded yet stays unfinished until the Worker can deliver it, and `Transaction.updates` tries again. Change the server address in Settings. `http` is only accepted for `127.0.0.1` and `localhost`.

The Release build setting points at `https://sudoku-packs.example.workers.dev`. Replace that with the hostname `wrangler deploy` prints before you install a Release build on a phone. The address is also in Settings after the first launch, and a value already saved on the phone is kept.

### Pack Worker

`cloudflare/` is the pack server. It is a TypeScript Worker with one D1 database. It does not take payment. It checks the signed StoreKit transaction and then sends the puzzles. The admin pages are on the same Worker. Why the Swift process is gone is written in `docs/adr/0001-pack-server-on-cloudflare.md`.

Deploy, once, from `cloudflare/`. This does not run itself. You need a Cloudflare account you control.

```sh
cd cloudflare
npm install
npx wrangler login
npx wrangler d1 create sudoku-packs
```

Copy the `database_id` from that command into `d1_databases` in `wrangler.jsonc`. The file ships with `00000000-0000-0000-0000-000000000000` so the repo has no account id.

```sh
npx wrangler d1 migrations apply sudoku-packs --remote
npx wrangler secret put SESSION_SECRET
npx wrangler secret put ADMIN_EMAILS
npx wrangler secret put GOOGLE_CLIENT_ID
npx wrangler secret put GOOGLE_CLIENT_SECRET
npx wrangler secret put APPLE_SERVICES_ID
npx wrangler secret put APPLE_TEAM_ID
npx wrangler secret put APPLE_KEY_ID
npx wrangler secret put APPLE_PRIVATE_KEY
```

Set `PUBLIC_BASE_URL` in `wrangler.jsonc` to the `https://….workers.dev` host you are about to deploy, with no trailing slash. Then:

```sh
npx wrangler deploy
```

`ADMIN_EMAILS` is a comma-separated list, for example `you@gmail.com`. `SESSION_SECRET` is a random string of at least 32 characters. `APPLE_PRIVATE_KEY` is the Sign in with Apple `.p8`, pasted with its `BEGIN` and `END` lines. Locally, the same names go in `.dev.vars`, copied from `.dev.vars.example`. Do not commit `.dev.vars`.

Leave `ALLOW_XCODE_JWS` as `"false"` in `wrangler.jsonc`. A deployed Worker checks the JWS certificate chain against Apple Root CA - G3, then checks `bundleId` `com.brianbancroft.sudoku` and that the product id is one of the packs. Xcode's StoreKit configuration file is not signed by Apple, so simulator purchases work only while `wrangler dev` is running with `ALLOW_XCODE_JWS=true` in `.dev.vars`.

#### Google sign-in for the admin page

In Google Cloud, create an OAuth client of type Web application. You do not need a Google Cloud project id in this repo.

- Authorized redirect URI for the deployed Worker: `https://<worker-host>/admin/oauth/google/callback`
- For `wrangler dev` on this computer, also add `http://127.0.0.1:8787/admin/oauth/google/callback`

Put the client id and secret in the two Google secrets above. Open `https://<worker-host>/admin/login`. The Google account's email has to be listed in `ADMIN_EMAILS`, and Google has to say the email is verified.

#### Sign in with Apple for the admin page

This is a web Services ID for the admin page. It is not the iPhone app's signing team, and the Xcode project stays without a team id.

In the Apple Developer account, create a Services ID with Sign in with Apple, a Sign in with Apple key, and note the team id and key id.

- Return URL: `https://<worker-host>/admin/oauth/apple/callback`
- Domains and subdomains: the Worker hostname, without `https://`
- For local admin sign-in, Apple requires an HTTPS return URL, so use the deployed Worker rather than `wrangler dev` for Apple. Google works on localhost.

`APPLE_SERVICES_ID` is the Services ID (it looks like a reverse-DNS identifier). `APPLE_TEAM_ID` is the 10-character team id. `APPLE_KEY_ID` is the key id. `APPLE_PRIVATE_KEY` is that key's `.p8`. None of these belong in the iOS target.

#### Point the app at the Worker

- Simulator: Debug already uses `http://127.0.0.1:8787`. Run `npx wrangler dev --port 8787` with `ALLOW_XCODE_JWS=true`.
- Phone: set the Release build setting `SUDOKU_PACK_SERVER_URL` to `https://<worker-host>`, or type that address into Settings. `Info.plist` reads the build setting into `SudokuPackServerURL`.

### What real App Store sales need later

- An Apple Developer Program membership, a signing team chosen only on your Mac, and a bundle id that matches `com.brianbancroft.sudoku`.
- Paid Apps agreement, tax, and banking in App Store Connect.
- Three non-consumable products with the same ids as `Products.storekit`: `com.brianbancroft.sudoku.pack.starter`, `com.brianbancroft.sudoku.pack.hard`, and `com.brianbancroft.sudoku.pack.expert`.
- The Worker deployed as above, with `ALLOW_XCODE_JWS` left false. Production and Sandbox transactions are verified from the JWS `x5c` chain to Apple Root CA - G3. No App Store Server API key is required for that check.
- The phone pointed at that `https` host.

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
