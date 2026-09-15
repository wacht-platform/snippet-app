import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/theme.dart';

/// Accent candidates for the dark UI, rendered so a hue can be compared rather
/// than imagined. Surfaces, ink and status hues are held fixed; only the accent
/// (and its derived alpha tokens) moves.
const _candidates = <(String, Color)>[
  ('Current blue', Color(0xFF4E88FF)),
  ('Indigo', Color(0xFF716AFB)),
  ('Violet', Color(0xFF8D5DFB)),
  ('Purple', Color(0xFFA94CFA)),
  ('Magenta', Color(0xFFEC4899)),
  ('Cyan', Color(0xFF22B8CF)),
  ('Teal', Color(0xFF14B8A6)),
  ('Slate', Color(0xFF94A3B8)),
];

/// Rebuild the shipping preset with one accent swapped, mirroring `_dark`'s
/// own derivation so the preview shows what the real tokens would be.
ThemePreset _withAccent(Color accent) {
  final b = allPresets[0];
  final hsl = HSLColor.fromColor(accent);
  final hover = hsl
      .withLightness((hsl.lightness + 0.10).clamp(0.0, 1.0))
      .toColor()
      .withValues(alpha: accent.a);
  return ThemePreset(
    name: 'preview',
    label: 'Preview',
    bg: b.bg,
    canvas: b.canvas,
    floor: b.floor,
    surface1: b.surface1,
    surface2: b.surface2,
    surface3: b.surface3,
    fg1: b.fg1,
    fg2: b.fg2,
    fg3: b.fg3,
    fg4: b.fg4,
    border: b.border,
    border2: b.border2,
    accent: accent,
    accentHover: hover,
    accentFg: b.accentFg,
    accentBg: accent.withValues(alpha: 0.14),
    accentLine: accent.withValues(alpha: 0.38),
    accentRing: accent.withValues(alpha: 0.45),
    ok: b.ok,
    okBg: b.okBg,
    run: b.run,
    runBg: b.runBg,
    danger: b.danger,
    dangerBg: b.dangerBg,
    diffAddBg: b.diffAddBg,
    diffDelBg: b.diffDelBg,
    diffAddFg: b.diffAddFg,
    diffDelFg: b.diffDelFg,
    diffGutter: b.diffGutter,
  );
}

void main() {
  testWidgets('accent candidates', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(920, 720) * 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ACCENT CANDIDATES',
                  style: sans(13, weight: W.label, color: AppColors.fg1)),
              const SizedBox(height: 4),
              Text(
                'Per row: primary button (white ink) · same button (dark ink) · '
                'selected chip · focus edge · "Needs you" state',
                style: sans(11, color: AppColors.fg4),
              ),
              const SizedBox(height: 16),
              for (final (name, hex) in _candidates) _row(name, hex),
            ],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/accent_candidates.png'));
  });
}

Widget _row(String name, Color hex) {
  final p = _withAccent(hex);
  final code = hex.toARGB32().toRadixString(16).substring(2).toUpperCase();
  return Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Row(children: [
      SizedBox(
        width: 150,
        child: Text('$name\n#$code',
            style: sans(11, weight: W.label, color: AppColors.fg2)),
      ),
      _button(p.accent, Colors.white),
      const SizedBox(width: 8),
      _button(p.accent, const Color(0xFF0C0C0C)),
      const SizedBox(width: 12),
      Container(
        width: 104,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.accentBg,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: p.accentLine),
        ),
        child:
            Text('Send to', style: sans(11.5, weight: W.label, color: p.accent)),
      ),
      const SizedBox(width: 10),
      Container(
        width: 54,
        height: 26,
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: p.accentLine),
        ),
      ),
      const SizedBox(width: 10),
      Text('Needs you', style: sans(11.5, weight: W.label, color: p.accent)),
      const SizedBox(width: 8),
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
      ),
    ]),
  );
}

Widget _button(Color fill, Color ink) => Container(
      width: 84,
      height: 28,
      alignment: Alignment.center,
      decoration:
          BoxDecoration(color: fill, borderRadius: BorderRadius.circular(R.chip)),
      child: Text('Approve', style: sans(11.5, weight: W.label, color: ink)),
    );
