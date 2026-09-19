# Design language

Extracted from the reference desktop shell by inspecting its live DOM
(`getBoundingClientRect` + `getComputedStyle`), not from screenshots. Every
number below is a measured value. Window under measurement: 1132 × 792.

The single most important finding: **the reference uses no borders at all.**
Separation comes entirely from a ladder of background colours. There is not one
`border` in the whole tree. Our UI compensates with hairlines everywhere, which
is why it reads busier and flatter at the same time.

## 1. Surfaces

A four-step ladder. Depth is expressed by *darkening*, and the reading surface
is the darkest thing on screen — the inverse of raising cards.

| Role | Hex | Size in reference | Notes |
| --- | --- | --- | --- |
| Canvas (chat / editor) | `#010101` | 481 × 712 | darkest; content recedes |
| Floor (window, side pane) | `#0D0D0D` | 1132 × 792, 393 × 712 | app shell + secondary pane |
| Chrome (strip, sidebar, cards) | `#171717` | 1132 × 40, 258 × 712 | the main "grey" |
| Active row | `#222222` | 218 × 26 | selected nav row |
| Chip / pill / hover | `#2D2D2D` | 61 × 20 | inline tokens, raise on hover |
| Overlay wash | `rgba(255,255,255,0.12)` | 4 × 4 | faint highlight on dark |

Adjacent surface steps are ~10% apart in luminance — enough to read as a
boundary without a line.

## 2. Geometry

```
window            1132 × 792   radius 20
├─ top bar        1132 × 40
├─ strip          1132 × 40    bg #171717   (FULL WIDTH)
│   ├─ icon zone   291 × 24    icons centred inside it
│   └─ status      121 × 14    right-aligned
└─ body           1132 × 712   bg #171717
    ├─ sidebar     258 × 712
    ├─ chat        481 × 712   bg #010101   radius 10 0 0 0
    └─ detail      393 × 712   bg #0D0D0D   radius 0 10 0 0
```

The second-level strip spans the **entire window width** and sits between the
top bar and the body. It is a shell-level band, not a sidebar header.

### Sidebar
- Column: **258 px**
- Outer padding: `0 8px` (top section), `8px 8px 0` (lower section)
- Section radius: 10 px

### Rows — the core metric
| Element | Height | Radius | Padding | Gap |
| --- | --- | --- | --- | --- |
| Section header | 32 | 0 | `8px 12px` | 8 |
| Nav row | **26** | **8** | `5px 12px` | 8 |

Nav rows are 26 px tall, not the 34 px we ship. Indentation: **24 px** for a
top-level row, **48 px** for a nested one.

### Icon slots
Icons are drawn inside a fixed slot, and the glyph never fills it:

| Slot | Glyph | Use |
| --- | --- | --- |
| 24 × 24 | 16 × 16 | nav / toolbar buttons |
| 16 × 16 | 12 × 12 | inline with text |
| 18 × 18 | 18 × 18 | section markers |
| 20 × 20 | 20 × 20 | header actions |
| 28 × 28 | 24 × 24 | prominent actions |

The 24 → 16 relationship is the important one: **a 16 px glyph inside a 24 px
hit target.** We were drawing glyphs at full slot size, which is what made them
look oversized.

### Radii
```
8px      ×26   rows, cards, inputs      <- dominant
999px    ×10   pills, dots, avatars
4px      ×7    small inline marks
6px      ×1    chip
10px     ×4    window, sections, panes
```

## 3. Typography

Two families: **Geist** (primary, 53 uses) and **Inter** (secondary, 13 uses).
Everything is 11–13 px except a single 20 px title.

| Size | Weight | Colour | Uses | Sample |
| --- | --- | --- | --- | --- |
| 12 | 400 | `#C1C1C1` | 22 | message body |
| 13 | 400 | `#C1C1C1` | 19 | list titles, transcript |
| 12 | 500 | `#C1C1C1` | 14 | controls, labels |
| 13 | 500 | `#C1C1C1` | 6 | row title, user message |
| 11 | 500 | `#C1C1C1` | 2 | `CHATS` (Inter) |
| 20 | 600 | `#FFFFFF` | 2 | the one page title |
| 16 | 500 | `#FFFFFF` | 1 | section heading |

- **Line height**: 16 px for 12 px text (1.33); 15.6 px for 13 px (1.2)
- **Letter spacing**: `-0.05px` (22 uses); `-0.3px` on the 20 px title
- **Ceiling is 500.** `600` appears exactly once, on the single 20 px title.
  Body, list titles and transcript are all 400.

## 4. Text colours

| Hex | Uses | Role |
| --- | --- | --- |
| `#C1C1C1` | 31 | default body — most text is this, not white |
| `#D2D5DB` | 12 | slightly cooler, denser prose |
| `#FFFFFF` | 11 | emphasis only: active row, title, user turn |
| `#C1C1C1` @ 0.8 | 6 | muted label |
| `#C1C1C1` @ 0.75 | 4 | very muted |
| `#C1C1C1` @ 0.45 | 1 | placeholder |

Default text is a **light grey**, not white. White is reserved for the few
elements that must outrank their surroundings.

### Status
`#3EAF3F` green (online), `#AF8D3E` amber, `#979797` neutral grey.

## 5. What this means for us

1. Delete the borders. Replace every hairline separator with a surface step.
2. Adopt the ladder: `#010101` canvas → `#0D0D0D` floor → `#171717` chrome →
   `#222222` active → `#2D2D2D` chip.
3. Default text `#C1C1C1`; white only for the active row and the title.
4. Switch the UI family to Geist; keep Inter for incidental labels.
5. Rows 26 px (not 34), radius 8, indent 24/48.
6. Explicit slots: 24 px target, 16 px glyph. Never let a glyph fill its slot.
7. Sidebar 258 px. Strip full width at 40 px.
