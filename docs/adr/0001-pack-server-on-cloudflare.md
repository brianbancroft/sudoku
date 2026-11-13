# Pack delivery moves to a Cloudflare Worker

The puzzle packs need a host that can check a StoreKit 2 signature and hand the grids to a phone that already paid. The first server was a small Swift process on the Mac. It was the right size for a simulator, and it stopped at the edge of a real purchase: production mode refused every Sandbox and Production transaction because no Apple key lived in the repo.

That process cannot be the one a phone calls. Two verifiers, one in Swift and one on the host, would drift the first time a claim check changed. The Swift program is removed. `SudokuEngine` stays, and it is still what generates a free game on the phone and what produced the seeded pack grids.

The replacement is one Worker in `cloudflare/`. D1 holds packs, puzzles, entitlements, admin users, sessions, and the short-lived OAuth state. The public routes are the same four the app already calls: health, catalog, entitlements, and pack download. An admin page on the same Worker lists and edits packs, hides a pack from the catalog, and shows purchases. Sign-in is Google or Sign in with Apple, and the email has to be on `ADMIN_EMAILS`. The session cookie is HttpOnly and SameSite=Lax, and it is signed with `SESSION_SECRET`. Forms send a CSRF token.

StoreKit signatures are checked against the public Apple Root CA - G3 certificate that ships in the Worker. Xcode's StoreKit configuration file is not signed by that root. `ALLOW_XCODE_JWS=true` in `.dev.vars` is the only switch that accepts those local transactions, and the committed Worker config leaves it off. A deployed Worker therefore rejects a simulator purchase. `wrangler dev` on `http://127.0.0.1:8787` is the local stand-in for the old Swift process.

Nothing in this change creates a Cloudflare account, a D1 database, or an OAuth client. `database_id` in `wrangler.jsonc` is a placeholder of zeros.
