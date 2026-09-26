# Design language

The single source of truth for how snippet looks and moves, on phone and
desktop. `lib/theme.dart` implements exactly this; if the two disagree, the
code is wrong. Supersedes the earlier DOM-measured reference and the
2026-09-15 audit.

Benchmark for feel: the Claude app. Every tap answers instantly, panels track
the finger, motion is short and interruptible, and nothing stutters.

## Principles

1. **One system, two densities.** Phone and desktop share every colour, type
   role, radius and curve. Only touch targets and gutters differ.
2. **Depth from surfaces, not lines.** Hierarchy comes from the surface ladder.
   Lines exist only where a boundary carries meaning (inputs, dividers inside
   a list card, the diff gutter).
3. **Opaque everywhere.** No window vibrancy, no backdrop blur. Overlays lift
   with a surface step and a soft shadow.
4. **Colour means something.** Blue is interaction. Green, amber and red are
   state. Nothing decorative borrows either.
5. **Motion is feedback, not decoration.** It confirms input, shows where
   something came from, and never makes anyone wait.

## Colour — dark only

### Surfaces

| Token | Hex | Use |
| --- | --- | --- |
| `canvas` | `#0F0F10` | Reading planes: chat, editor, file viewer, diff |
| `base` | `#151516` | App shell, sidebar, secondary panes, page backgrounds |
| `raised` | `#1C1C1E` | Cards, list groups, composer, selected row |
| `overlay` | `#232325` | Menus, sheets, dialogs, popovers, inputs |
| `hover` | `#2A2A2D` | Hover and pressed fill on any of the above |
| `line` | `#2A2A2D` | Input outline, in-card dividers |
| `lineStrong` | `#36363A` | Focused-but-not-primary outline, table rules |

Adjacent steps are 6–7 RGB points apart, which reads as a boundary without a
line. Tokens from the old ladder map onto these (see `theme.dart`) until each
screen is migrated.

### Text

| Token | Hex | On canvas | Use |
| --- | --- | --- | --- |
| `fg1` | `#EDEDEF` | 16.5:1 | Titles, active row, user's own message |
| `fg2` | `#C8C8CC` | 11.8:1 | **Default body text** |
| `fg3` | `#9A9AA2` | 7.1:1 | Secondary text, metadata, icons at rest |
| `fg4` | `#6E6E76` | 3.9:1 | Placeholder, disabled only — never content |

### Accent — mascot blue

The accent is the mascot's blue (`#3B7DF7`), split into two roles because no
single blue works as both a button fill with a white label and as text on
near-black.

| Token | Hex | Contrast | Use |
| --- | --- | --- | --- |
| `accentFill` | `#2F6FEB` | white label 4.6:1 | Primary buttons, switches on, send |
| `accentFillHover` | `#2A63D6` | white label 5.4:1 | Hover/pressed primary |
| `accent` | `#6EA2FF` | 7.6:1 on canvas | Links, selected icons, focus ring, active tab |
| `accentBg` | accent @ 14% | — | Selected row tint, active chip |

Why blue: it is the brand's own colour; it is the established "interactive"
hue in the tools snippet sits beside (VS Code, GitHub, Geist, Zed), so it
needs no learning; and it is the hue farthest from all three status colours.

### Status

| Token | Hex | Use |
| --- | --- | --- |
| `ok` | `#39C57E` | Online, completed, added (mascot green) |
| `run` | `#D4982F` | Running, busy, modified |
| `danger` | `#F06464` | Failed, destructive, deleted |

Each has a `…Bg` at 13% for tinted badges. Status colour always pairs with a
label or glyph; colour is never the only channel.

## Typography

Geist for UI, JetBrains Mono for code, paths and identifiers. Both bundled —
never fetched at runtime.

| Role | Size / line | Weight | Use |
| --- | --- | --- | --- |
| `pageTitle` | 22 / 28 | 600 | One per page |
| `sectionTitle` | 17 / 24 | 600 | Sheet and section headings |
| `rowTitle` | 15 / 20 | 500 | List rows, card titles |
| `body` | 15 / 22 | 400 | Chat and reading text (16 on phones) |
| `ui` | 14 / 20 | 400 | Controls, form text, secondary copy |
| `label` | 13 / 18 | 500 | Buttons, tabs, field labels |
| `meta` | 12 / 16 | 400 | Timestamps, counts, captions |
| `caption` | 11 / 14 | 400 | Dense secondary hints, counters beside controls |
| `caps` | 11 / 14 | 500, +0.5 tracking | Overline section labels, sparingly |
| `code` | 13 / 20 | 400 | Code blocks, diffs, terminal |
| `codeSmall` | 12 / 16 | 400 | Inline paths, ids, hashes |

Three weights: 400, 500, 600. No 700. No half-pixel sizes. Counters and timers
use tabular figures.

## Space, shape, size

- **Spacing scale (px):** 2, 4, 6, 8, 12, 16, 20, 24, 32, 40. Nothing else.
- **Radius:** `xs` 4 (inline marks), `sm` 6 (buttons, inputs, chips),
  `md` 10 (cards, rows, list groups), `lg` 14 (sheets, dialogs, menus),
  `pill` 999. A nested radius is the outer radius minus the inset.
- **Rows:** 36 desktop, 52 phone. **Touch target:** 44 minimum on phones.
- **Icons:** 14 inline, 16 default, 20 prominent — always centred in a slot
  larger than the glyph.
- **Gutters:** 16 phone, 20 desktop pane.
- **Shadow (overlays only):** black 45%, blur 24, y 8.

## Motion

Only `transform` and `opacity` animate. Never blur, never layout-affecting
size on a hot path.

| Token | Duration | Curve | Use |
| --- | --- | --- | --- |
| `press` | 100ms | ease-out | Scale to 0.97 on pointer **down** |
| `quick` | 150ms | ease-out | Hover, colour, icon swaps |
| `enter` | 240ms | `cubic(0.32, 0.72, 0, 1)` | Sheets, panels, menus arriving |
| `exit` | 180ms | ease-in | Leaving — always shorter than entering |
| `page` | 260ms | `cubic(0.32, 0.72, 0, 1)` | Route push/pop |

Rules:

- **Instant acknowledgement.** Every control reacts on pointer down.
- **Interruptible.** Sheets and drawers follow the finger and settle with the
  release velocity; a new gesture mid-animation takes over, never queues.
- **Optimistic.** A sent message, a staged file or a toggled switch shows its
  new state immediately; the network confirms or reverts it.
- **No spinner flash.** Loading indicators appear only after 300ms; content
  that returns sooner just appears. Prefer skeletons shaped like the content.
- **Reduced motion.** Drop movement and scale, keep short fades.
- **Frame budget.** Nothing on screen may rebuild a whole page per token,
  tick or keystroke. Streaming, timers and inputs update the smallest widget
  that shows them.
