# UI/UX audit — 2026-09-15

Measured against the installed `better-ui` (Jakub Krehel) and `emil-design-eng`
(Emil Kowalski) skills. Findings cite source lines; every claim below was read
from the current tree, not inferred.

Scope: `snippet-mobile` (Flutter, 37,632 LOC) and `snippet-service` TUI
(`src/tui`, 15,349 LOC).

## Verified defects

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH | `lib/` (whole app) | No `prefers-reduced-motion` handling anywhere | Gate the 3 infinite pulses + 4 switchers on `MediaQuery.disableAnimations` | Users who ask the OS for reduced motion still get perpetual animation. Verified absent: no `disableAnimations` / `accessibleNavigation` / `reduceMotion` token exists in `lib/` or `test/`. |
| HIGH | `lib/widgets.dart:1137` (`IconBtn`) | Tap area = raw `SizedBox(width: size, height: size)`; **default 38px**, and 40 call sites override to 22–36 | Clamp the hit area to `M.minTarget` (44) independent of the visual box | `M.minTarget = 44` exists (`lib/theme.dart:312`) but `IconBtn` never consults it. A 22px control on a phone is an unreliable tap. In use: 28×17, 32×14, 26×8, 30×7, 34×2, 36×2, 24, 22. Mobile-reachable offenders: `session.dart:3493` (22, composer chip), `session.dart:1973` (28, recording panel), `session.dart:2792` (36, mobile term tab). |
| MEDIUM | `lib/theme.dart` | No motion tokens at all; **11 distinct durations ≤400ms** (50,120,140,150,160,170,180,200,220,300,400) scattered inline | One `Motion` token table (durations + curves) that every site consumes | Same transition reads differently across screens because each picked its own number. The radius/type layers are tokenised; motion never was. |
| MEDIUM | 94 `InkWell`/`Material` sites | Ripple is the only press feedback; exactly **one** site scales (`file_tree_sidebar_panel.dart:572`) | Shared pressable helper: `scale(0.97)` on `:active`, 160ms `ease-out` | Ripple confirms release, not press. Scale-on-press is the tactile confirmation that the interface heard the tap. |
| LOW | 197 radius usages | `R.card = R.md = R.sm = 8`, `xs = 4`, `chip = 6`, `sheetTop = 10`; nested panels reuse the outer radius regardless of inner padding | Inner radius = outer − padding (concentric) | Mismatched nested radii is the most common cause of an interface feeling subtly off. Needs a per-site pass; not quantified yet. |

## Checked, and NOT a defect

Recording these so they are not "fixed" into regressions later.

- **`switchOutCurve: Curves.easeInCubic`** (`desktop_shell.dart:4756,5101,6627`,
  `session.dart:2574`) is **correct**. Flutter drives the outgoing child 1→0;
  `easeInCubic` is steep at x=1, so the exit *starts* fast and settles — the
  right exit shape. The skill's blanket "never ease-in" targets entrances. Do
  not change these.
- **Theme-switch transition smear** is **N/A**. `theme.dart:195` —
  "AMOLED Black — the only remaining preset". With one theme there is no flip to
  smear.
- **TUI motion** is fine: 10 braille frames at `frame / 2` on an 80ms tick
  (`tui/mod.rs:4604`, `tui/transcript.rs:388`) ≈ 160ms/frame. No action.

## TUI

The known "painfully slow" symptom is a **deployment gap, not a code gap**. The
cached-`Store` fix is built (`target/release/snippet`, sha `daa82b34…`) but
`~/.cargo/bin/snippet` (sha `332d5a0f…`) is still the old binary, so the running
TUI did not get it. Install is the outstanding step.

## Recommended sequence

Foundation first — everything above depends on it and it is where the drift
compounds:

1. `Motion` token table in `theme.dart` (durations + curves), consumed app-wide.
2. Reduce-motion helper; gate the 3 infinite pulses and 4 `AnimatedSwitcher`s.
3. `IconBtn` hit-target floor at `M.minTarget`; fix the 22–36px mobile sites.
4. Shared pressable helper with `scale(0.97)`.
5. Concentric-radii pass (per-site).
6. TUI: install the perf build.

## Verification limits

**Nothing here is visually verified.** There is no macOS toolchain and no way to
run Flutter on this box — only `flutter analyze`, `flutter test` and an APK
build are confirmable, and all three have previously passed code with real
runtime defects. Every finding above is from reading source. Any change must be
confirmed against a device or screenshot before it is called done.
