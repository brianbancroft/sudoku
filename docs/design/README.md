# Design

Cheerful and graceful, with the board still the largest thing on the screen. Blush pages, raspberry emphasis, and soft cards. The pink is in the surfaces. Digits stay dark plum or deep rose so they stay readable.

## Tokens

Light and dark pairs, both pink rather than neutral gray.

- Page: `#FBEAF1` fading to `#F6E4EC`. Dark: `#3A1C2A` to `#2A1520`.
- Board and cards: `#FFF8FB` and `#FFF6F9`. Dark: `#3A1E2C` and `#432433`.
- Given digits: `#3A2430`, bold. Dark: `#FFE8F1`.
- Entered digits: `#8E2348`. Dark: `#FFC0D4`.
- Pencil marks: `#6A3E50`. Dark: `#F6D5E2`.
- Selection: `#F4C3D4`. Related houses: `#FBE4EC`. Same digit: `#F6D0E0`.
- Errors: clay wash `#F6D7CC` with `#7A2420` digits, plus a short bar. Not a bright red.
- Buttons: `#8E1E4A` with `#FFF7FA` labels. Dark button `#F3B6CC` with `#3A1524` labels.

Corners are 22 for cards, 18 for buttons and the board, 16 for the number keys. Titles and board digits use a serif. Controls use the system sans.

Motion is a short spring when the selection moves, and a few petals that drift away on a finished puzzle. Both stay still when Reduce Motion is on. Placing a digit and finishing a puzzle use the system haptic.

Contrast ratios are listed in the repository README. Every pair above is at least 4.5:1.

## Mobbin references

These are layout and tone notes, not branding to copy.

- [NYT Games list](https://mobbin.com/flows/7ff83257-0e0a-4cbe-95f0-c9b739df7a5c) — a title and one quiet line per choice. The difficulty list and pack rows follow that rhythm.
- [5 Minute Journal home](https://mobbin.com/screens/d69022ce-0e2c-48b3-8f76-7324f9c4f8a6) — warm page, soft cards, one strong button.
- [5 Minute Journal, well done](https://mobbin.com/screens/1e6374cc-ebd0-4109-bf0a-54a17b2de767) — a serif “complete” line, lots of air, a single next step.
- [Flo celebration](https://mobbin.com/screens/a74eb2ef-f615-4c98-8132-587478c8155c) — a light scatter of color around a calm message. Here that is a few petals, not a character.
- [Brilliant, lesson complete](https://mobbin.com/screens/f5881118-ee68-4f94-b0fa-c56e9bffb6f0) — time and hint count sit under the headline as plain facts.
- [Brilliant puzzle](https://mobbin.com/screens/b7da8200-dec0-4841-952d-21e8a953e815) — the board is framed, and the controls sit in a band underneath.
- [5 Minute Journal paywall](https://mobbin.com/screens/0b03c06a-63c8-43dd-87ed-58fecc57f0a1) — price inside the card, restore as its own button, no extra offer clutter.
- [OpenTable pricing](https://mobbin.com/sites/sections/0c81e36a-14f6-471d-9ce7-8930b284a9f2) — one card can be the selected one by a stronger edge, while the others stay quiet.

## Mockups

`home.png`, `game.png`, `store.png`, and `win.png` in this folder are HTML renderings of the same colors, type, and spacing as the SwiftUI screens.
