
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform.dart';

// ---------------------------------------------------------------------------
// Theme presets — each one defines every color the app uses. Ported from the
// TUI's 13 presets (src/tui/theme.rs) plus mobile-specific surface/diff slots.
// ---------------------------------------------------------------------------

class ThemePreset {
  final String name;
  final String label;

  // Surfaces (darkest → lightest)
  final Color bg;
  final Color canvas;
  final Color floor;
  final Color surface1;
  final Color surface2;
  final Color surface3;

  // Foreground (brightest → faintest)
  final Color fg1;
  final Color fg2;
  final Color fg3;
  final Color fg4;

  // Borders
  final Color border;
  final Color border2;

  // Accent
  final Color accent;
  final Color accentHover;
  final Color accentFg;
  final Color accentBg;
  final Color accentLine;
  final Color accentRing;
  final Color accentFill;
  final Color accentFillHover;

  // Status
  final Color ok;
  final Color okBg;
  final Color run;
  final Color runBg;
  final Color danger;
  final Color dangerBg;

  // Diff
  final Color diffAddBg;
  final Color diffDelBg;
  final Color diffAddFg;
  final Color diffDelFg;
  final Color diffGutter;

  const ThemePreset({
    required this.name,
    required this.label,
    required this.bg,
    required this.canvas,
    required this.floor,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.fg1,
    required this.fg2,
    required this.fg3,
    required this.fg4,
    required this.border,
    required this.border2,
    required this.accent,
    required this.accentHover,
    required this.accentFg,
    required this.accentBg,
    required this.accentLine,
    required this.accentRing,
    required this.accentFill,
    required this.accentFillHover,
    required this.ok,
    required this.okBg,
    required this.run,
    required this.runBg,
    required this.danger,
    required this.dangerBg,
    required this.diffAddBg,
    required this.diffDelBg,
    required this.diffAddFg,
    required this.diffDelFg,
    required this.diffGutter,
  });
}

// Helper: build the palette. Surfaces follow a "surface ladder" — hierarchy
// comes from surface lift + hairlines, not drop shadows. Text follows a strict
// brightness ladder so fg1 > fg2 > fg3 > fg4 always holds.
ThemePreset _palette({
  required String name,
  required String label,
  required Color bg,
  required Color surface1,
  required Color surface2,
  required Color surface3,
  required Color border,
  required Color border2,
  required Color accent,
  required Color accentFg,
  Color fg1 = const Color(0xFFFFFFFF),
  Color fg2 = const Color(0xFFDCDCDC),
  Color fg3 = const Color(0xFFABABAB),
  Color fg4 = const Color(0xFF7A7A7A),
}) {
  final hover = _lighten(accent, 0.06);
  const ok = Color(0xFF34D399);
  const run = Color(0xFFF59E0B);
  const danger = Color(0xFFFF5C5C);
  return ThemePreset(
    name: name,
    label: label,
    bg: bg,
    canvas: bg,
    floor: bg,
    surface1: surface1,
    surface2: surface2,
    surface3: surface3,
    fg1: fg1,
    fg2: fg2,
    fg3: fg3,
    fg4: fg4,
    border: border,
    border2: border2,
    accent: accent,
    accentHover: hover,
    accentFg: accentFg,
    accentBg: accent.withValues(alpha: 0.14),
    accentLine: accent.withValues(alpha: 0.38),
    accentRing: accent.withValues(alpha: 0.45),
    accentFill: accent,
    accentFillHover: hover,
    ok: ok,
    okBg: ok.withValues(alpha: 0.13),
    run: run,
    runBg: run.withValues(alpha: 0.13),
    danger: danger,
    dangerBg: danger.withValues(alpha: 0.13),
    diffAddBg: ok.withValues(alpha: 0.10),
    diffDelBg: danger.withValues(alpha: 0.10),
    diffAddFg: const Color(0xFF6EE7B7),
    diffDelFg: const Color(0xFFFF8A8A),
    diffGutter: border2,
  );
}

final _ember = _palette(
  name: 'ember',
  label: 'Charcoal Violet',
  bg: const Color(0xFF0B0B0B),
  surface1: const Color(0xFF151515),
  surface2: const Color(0xFF1F1F1F),
  surface3: const Color(0xFF2B2B2B),
  border: const Color(0xFF222222),
  border2: const Color(0xFF303030),
  accent: const Color(0xFFA78BFA),
  accentFg: const Color(0xFF140E2E),
);

final _stone = _palette(
  name: 'stone',
  label: 'Warm Stone',
  bg: const Color(0xFF121110),
  surface1: const Color(0xFF1B1917),
  surface2: const Color(0xFF221F1B),
  surface3: const Color(0xFF2A2621),
  border: const Color(0xFF262320),
  border2: const Color(0xFF332F2A),
  accent: const Color(0xFF9DB0FF),
  accentFg: const Color(0xFF10142A),
  fg1: const Color(0xFFEDE7DD),
  fg2: const Color(0xFFCFC8BC),
  fg3: const Color(0xFFA39C90),
  fg4: const Color(0xFF7A7368),
);

final _amber = _palette(
  name: 'amber',
  label: 'Obsidian Amber',
  bg: const Color(0xFF0D0B09),
  surface1: const Color(0xFF171411),
  surface2: const Color(0xFF211D18),
  surface3: const Color(0xFF2D2720),
  border: const Color(0xFF26211B),
  border2: const Color(0xFF362F26),
  accent: const Color(0xFFF59E0B),
  accentFg: const Color(0xFF1F1200),
);

final _midnight = _palette(
  name: 'midnight',
  label: 'Midnight Cyan',
  bg: const Color(0xFF080C10),
  surface1: const Color(0xFF10161E),
  surface2: const Color(0xFF17202B),
  surface3: const Color(0xFF202C3B),
  border: const Color(0xFF1D2733),
  border2: const Color(0xFF2A3848),
  accent: const Color(0xFF38BDF8),
  accentFg: const Color(0xFF041A26),
);

final _emerald = _palette(
  name: 'emerald',
  label: 'Forest Emerald',
  bg: const Color(0xFF080D0B),
  surface1: const Color(0xFF101915),
  surface2: const Color(0xFF17241E),
  surface3: const Color(0xFF203129),
  border: const Color(0xFF1C2B24),
  border2: const Color(0xFF293E34),
  accent: const Color(0xFF34D399),
  accentFg: const Color(0xFF032015),
);

final _rose = _palette(
  name: 'rose',
  label: 'Carbon Rose',
  bg: const Color(0xFF0E0A0C),
  surface1: const Color(0xFF181215),
  surface2: const Color(0xFF231A1F),
  surface3: const Color(0xFF30232A),
  border: const Color(0xFF281D23),
  border2: const Color(0xFF382931),
  accent: const Color(0xFFFB7185),
  accentFg: const Color(0xFF28060C),
);

final _tokyo = _palette(
  name: 'tokyo',
  label: 'Tokyo Night',
  bg: const Color(0xFF0F111A),
  surface1: const Color(0xFF161926),
  surface2: const Color(0xFF1E2233),
  surface3: const Color(0xFF282E44),
  border: const Color(0xFF23283B),
  border2: const Color(0xFF323952),
  accent: const Color(0xFF7AA2F7),
  accentFg: const Color(0xFF08132B),
  fg1: const Color(0xFFE6EDF8),
  fg2: const Color(0xFFC0CAF5),
  fg3: const Color(0xFF9AA5CE),
  fg4: const Color(0xFF6B7499),
);

final _mocha = _palette(
  name: 'mocha',
  label: 'Catppuccin Mocha',
  bg: const Color(0xFF11111B),
  surface1: const Color(0xFF181825),
  surface2: const Color(0xFF1E1E2E),
  surface3: const Color(0xFF313244),
  border: const Color(0xFF292A3C),
  border2: const Color(0xFF3B3D54),
  accent: const Color(0xFFCBA6F7),
  accentFg: const Color(0xFF1E1030),
  fg1: const Color(0xFFCDD6F4),
  fg2: const Color(0xFFBAC2DE),
  fg3: const Color(0xFFA6ADC8),
  fg4: const Color(0xFF6C7086),
);

final _nord = _palette(
  name: 'nord',
  label: 'Nordic Frost',
  bg: const Color(0xFF11151C),
  surface1: const Color(0xFF191F28),
  surface2: const Color(0xFF222A36),
  surface3: const Color(0xFF2E3846),
  border: const Color(0xFF27303D),
  border2: const Color(0xFF374354),
  accent: const Color(0xFF88C0D0),
  accentFg: const Color(0xFF081C24),
  fg1: const Color(0xFFECEFF4),
  fg2: const Color(0xFFD8DEE9),
  fg3: const Color(0xFF9AA5B8),
  fg4: const Color(0xFF6C788C),
);

final _gruvbox = _palette(
  name: 'gruvbox',
  label: 'Gruvbox Warm',
  bg: const Color(0xFF141311),
  surface1: const Color(0xFF1D1B18),
  surface2: const Color(0xFF282521),
  surface3: const Color(0xFF36312C),
  border: const Color(0xFF2E2A25),
  border2: const Color(0xFF403A33),
  accent: const Color(0xFFFABD2F),
  accentFg: const Color(0xFF221600),
  fg1: const Color(0xFFEBDBB2),
  fg2: const Color(0xFFD5C4A1),
  fg3: const Color(0xFFA89984),
  fg4: const Color(0xFF7C6F64),
);

final _crimsonNoir = _palette(
  name: 'crimson-noir',
  label: 'Crimson Noir',
  bg: const Color(0xFF0A0A0A),
  surface1: const Color(0xFF141414),
  surface2: const Color(0xFF1A1A1A),
  surface3: const Color(0xFF2B2B2B),
  border: const Color(0xFF222222),
  border2: const Color(0xFF333333),
  accent: const Color(0xFFFF1914),
  accentFg: const Color(0xFFFFFFFF),
  fg1: const Color(0xFFEEEDEE),
  fg2: const Color(0xFFC9C9C9),
  fg3: const Color(0xFF969696),
  fg4: const Color(0xFF686868),
);

final _desertAdobe = _palette(
  name: 'desert-adobe',
  label: 'Desert Adobe',
  bg: const Color(0xFF161412),
  surface1: const Color(0xFF1E1A17),
  surface2: const Color(0xFF25201C),
  surface3: const Color(0xFF362E26),
  border: const Color(0xFF2B241F),
  border2: const Color(0xFF413629),
  accent: const Color(0xFFE2A962),
  accentFg: const Color(0xFF1A1208),
  fg1: const Color(0xFFDCD1C0),
  fg2: const Color(0xFFC0B5A4),
  fg3: const Color(0xFF968C7D),
  fg4: const Color(0xFF6E665A),
);

final _graphiteSilver = _palette(
  name: 'graphite-silver',
  label: 'Graphite Silver',
  bg: const Color(0xFF131313),
  surface1: const Color(0xFF1A1A1A),
  surface2: const Color(0xFF232323),
  surface3: const Color(0xFF303030),
  border: const Color(0xFF262626),
  border2: const Color(0xFF383838),
  accent: const Color(0xFFF4F4F4),
  accentFg: const Color(0xFF111111),
  fg1: const Color(0xFFE8E8E8),
  fg2: const Color(0xFFB4B4B4),
  fg3: const Color(0xFF888888),
  fg4: const Color(0xFF606060),
);

final _sageMist = _palette(
  name: 'sage-mist',
  label: 'Sage Mist',
  bg: const Color(0xFF181B18),
  surface1: const Color(0xFF1E221E),
  surface2: const Color(0xFF242823),
  surface3: const Color(0xFF313A33),
  border: const Color(0xFF282D27),
  border2: const Color(0xFF384039),
  accent: const Color(0xFFADC7AD),
  accentFg: const Color(0xFF111811),
  fg1: const Color(0xFFCED5CE),
  fg2: const Color(0xFFB6BFB6),
  fg3: const Color(0xFF8C968C),
  fg4: const Color(0xFF656E65),
);

final _terracottaStudio = _palette(
  name: 'terracotta-studio',
  label: 'Terracotta Studio',
  bg: const Color(0xFF161616),
  surface1: const Color(0xFF1C1C1C),
  surface2: const Color(0xFF222222),
  surface3: const Color(0xFF32302E),
  border: const Color(0xFF292826),
  border2: const Color(0xFF3A3835),
  accent: const Color(0xFFD65F3B),
  accentFg: const Color(0xFF1A0904),
  fg1: const Color(0xFFD5D2CD),
  fg2: const Color(0xFFB4B1AC),
  fg3: const Color(0xFF8C8984),
  fg4: const Color(0xFF66635F),
);

final _volcanicCinder = _palette(
  name: 'volcanic-cinder',
  label: 'Volcanic Cinder',
  bg: const Color(0xFF141111),
  surface1: const Color(0xFF1B1616),
  surface2: const Color(0xFF221B1B),
  surface3: const Color(0xFF352325),
  border: const Color(0xFF2B2021),
  border2: const Color(0xFF42272A),
  accent: const Color(0xFFFF6138),
  accentFg: const Color(0xFF1E0700),
  fg1: const Color(0xFFDCCCC7),
  fg2: const Color(0xFFBEB1AB),
  fg3: const Color(0xFF948782),
  fg4: const Color(0xFF6B605C),
);

final _steelCobalt = _palette(
  name: 'steel-cobalt',
  label: 'Steel Cobalt',
  bg: const Color(0xFF10151B),
  surface1: const Color(0xFF161B23),
  surface2: const Color(0xFF1B2029),
  surface3: const Color(0xFF243144),
  border: const Color(0xFF212936),
  border2: const Color(0xFF2E3C52),
  accent: const Color(0xFF60A5FE),
  accentFg: const Color(0xFF061529),
  fg1: const Color(0xFFC5CEDA),
  fg2: const Color(0xFFA5B0BD),
  fg3: const Color(0xFF7D8896),
  fg4: const Color(0xFF586270),
);

final _copperHearth = _palette(
  name: 'copper-hearth',
  label: 'Copper Hearth',
  bg: const Color(0xFF161210),
  surface1: const Color(0xFF1C1614),
  surface2: const Color(0xFF221A17),
  surface3: const Color(0xFF362822),
  border: const Color(0xFF2C211D),
  border2: const Color(0xFF44312A),
  accent: const Color(0xFFED9353),
  accentFg: const Color(0xFF1F0E03),
  fg1: const Color(0xFFDED0C4),
  fg2: const Color(0xFFBFB4A7),
  fg3: const Color(0xFF948A7E),
  fg4: const Color(0xFF6B6359),
);

final _orchidNebula = _palette(
  name: 'orchid-nebula',
  label: 'Orchid Nebula',
  bg: const Color(0xFF13101E),
  surface1: const Color(0xFF191528),
  surface2: const Color(0xFF1F1A31),
  surface3: const Color(0xFF30264B),
  border: const Color(0xFF28213F),
  border2: const Color(0xFF382B59),
  accent: const Color(0xFFFE6FE1),
  accentFg: const Color(0xFF260520),
  fg1: const Color(0xFFDBD3EE),
  fg2: const Color(0xFFB4ABCD),
  fg3: const Color(0xFF8A80A6),
  fg4: const Color(0xFF62597D),
);

final _deepIndigo = _palette(
  name: 'deep-indigo',
  label: 'Deep Indigo',
  bg: const Color(0xFF111622),
  surface1: const Color(0xFF161C2A),
  surface2: const Color(0xFF1C2232),
  surface3: const Color(0xFF27314A),
  border: const Color(0xFF232B3F),
  border2: const Color(0xFF313E5B),
  accent: const Color(0xFF88A7F1),
  accentFg: const Color(0xFF0A1329),
  fg1: const Color(0xFFCED6E9),
  fg2: const Color(0xFFADB8CF),
  fg3: const Color(0xFF828FA8),
  fg4: const Color(0xFF5B677E),
);

final _arcticSlate = _palette(
  name: 'arctic-slate',
  label: 'Arctic Slate',
  bg: const Color(0xFF0F141B),
  surface1: const Color(0xFF141A22),
  surface2: const Color(0xFF18202A),
  surface3: const Color(0xFF233040),
  border: const Color(0xFF1F2936),
  border2: const Color(0xFF2C3B4E),
  accent: const Color(0xFF96B7D7),
  accentFg: const Color(0xFF091520),
  fg1: const Color(0xFFCBD4DD),
  fg2: const Color(0xFFB1BCC9),
  fg3: const Color(0xFF8592A1),
  fg4: const Color(0xFF5E6A78),
);

final _pineCanopy = _palette(
  name: 'pine-canopy',
  label: 'Pine Canopy',
  bg: const Color(0xFF141A16),
  surface1: const Color(0xFF19201B),
  surface2: const Color(0xFF1D2620),
  surface3: const Color(0xFF2A372E),
  border: const Color(0xFF243028),
  border2: const Color(0xFF334438),
  accent: const Color(0xFFA2C2A0),
  accentFg: const Color(0xFF0E1A0E),
  fg1: const Color(0xFFC7D2C6),
  fg2: const Color(0xFFB0BBB0),
  fg3: const Color(0xFF869186),
  fg4: const Color(0xFF5F695F),
);

final _fernCloister = _palette(
  name: 'fern-cloister',
  label: 'Fern Cloister',
  bg: const Color(0xFF101710),
  surface1: const Color(0xFF161F16),
  surface2: const Color(0xFF1C261B),
  surface3: const Color(0xFF273726),
  border: const Color(0xFF223021),
  border2: const Color(0xFF30452F),
  accent: const Color(0xFF99D58F),
  accentFg: const Color(0xFF0A1C08),
  fg1: const Color(0xFFC9D5C3),
  fg2: const Color(0xFFADBBA8),
  fg3: const Color(0xFF83917E),
  fg4: const Color(0xFF5B6757),
);

final _cyberSynth = _palette(
  name: 'cyber-synth',
  label: 'Cyber Synth',
  bg: const Color(0xFF0C0D15),
  surface1: const Color(0xFF131420),
  surface2: const Color(0xFF1A1A27),
  surface3: const Color(0xFF282940),
  border: const Color(0xFF222336),
  border2: const Color(0xFF323352),
  accent: const Color(0xFFFF26E0),
  accentFg: const Color(0xFF24001E),
  fg1: const Color(0xFFDADCF0),
  fg2: const Color(0xFFB8BCD6),
  fg3: const Color(0xFF8B90AD),
  fg4: const Color(0xFF626682),
);

final _velvetRose = _palette(
  name: 'velvet-rose',
  label: 'Velvet Rose',
  bg: const Color(0xFF181216),
  surface1: const Color(0xFF1F171C),
  surface2: const Color(0xFF251C21),
  surface3: const Color(0xFF382831),
  border: const Color(0xFF2E2229),
  border2: const Color(0xFF402C38),
  accent: const Color(0xFFEF7AA3),
  accentFg: const Color(0xFF260813),
  fg1: const Color(0xFFE0CED6),
  fg2: const Color(0xFFC0AFB8),
  fg3: const Color(0xFF96858E),
  fg4: const Color(0xFF6E5E66),
);

final _burgundyStudy = _palette(
  name: 'burgundy-study',
  label: 'Burgundy Study',
  bg: const Color(0xFF181012),
  surface1: const Color(0xFF1F1518),
  surface2: const Color(0xFF261B1D),
  surface3: const Color(0xFF382428),
  border: const Color(0xFF302124),
  border2: const Color(0xFF42282C),
  accent: const Color(0xFFD26457),
  accentFg: const Color(0xFF210805),
  fg1: const Color(0xFFDDCCC2),
  fg2: const Color(0xFFBEADA4),
  fg3: const Color(0xFF94847B),
  fg4: const Color(0xFF6B5D55),
);

final _tealEstuary = _palette(
  name: 'teal-estuary',
  label: 'Teal Estuary',
  bg: const Color(0xFF0E1618),
  surface1: const Color(0xFF131D1F),
  surface2: const Color(0xFF182425),
  surface3: const Color(0xFF1F3336),
  border: const Color(0xFF1E2E30),
  border2: const Color(0xFF284044),
  accent: const Color(0xFF3CD3C3),
  accentFg: const Color(0xFF03211D),
  fg1: const Color(0xFFC6D8D9),
  fg2: const Color(0xFFA4B8B7),
  fg3: const Color(0xFF7B8F8E),
  fg4: const Color(0xFF556766),
);

final _crtTerminal = _palette(
  name: 'crt-terminal',
  label: 'CRT Terminal',
  bg: const Color(0xFF0B120C),
  surface1: const Color(0xFF101B10),
  surface2: const Color(0xFF162414),
  surface3: const Color(0xFF1F361C),
  border: const Color(0xFF1C3019),
  border2: const Color(0xFF284624),
  accent: const Color(0xFF73F255),
  accentFg: const Color(0xFF062102),
  fg1: const Color(0xFFB3E4AB),
  fg2: const Color(0xFF97C48F),
  fg3: const Color(0xFF6E9967),
  fg4: const Color(0xFF4A6E44),
);

final _borealGlow = _palette(
  name: 'boreal-glow',
  label: 'Boreal Glow',
  bg: const Color(0xFF0B1016),
  surface1: const Color(0xFF11161E),
  surface2: const Color(0xFF161C26),
  surface3: const Color(0xFF1F2C3D),
  border: const Color(0xFF1C2532),
  border2: const Color(0xFF28374A),
  accent: const Color(0xFF7DF4B7),
  accentFg: const Color(0xFF052113),
  fg1: const Color(0xFFD2DAE2),
  fg2: const Color(0xFFABBAC5),
  fg3: const Color(0xFF80909C),
  fg4: const Color(0xFF596873),
);

final _saffronTwilight = _palette(
  name: 'saffron-twilight',
  label: 'Saffron Twilight',
  bg: const Color(0xFF12131F),
  surface1: const Color(0xFF181827),
  surface2: const Color(0xFF1E1D2F),
  surface3: const Color(0xFF2D2B43),
  border: const Color(0xFF27263D),
  border2: const Color(0xFF363452),
  accent: const Color(0xFFFFC12F),
  accentFg: const Color(0xFF241800),
  fg1: const Color(0xFFD9D5C9),
  fg2: const Color(0xFFB6B3A6),
  fg3: const Color(0xFF8C897D),
  fg4: const Color(0xFF646257),
);

final _amethystGloaming = _palette(
  name: 'amethyst-gloaming',
  label: 'Amethyst Gloaming',
  bg: const Color(0xFF161121),
  surface1: const Color(0xFF1C152A),
  surface2: const Color(0xFF221A33),
  surface3: const Color(0xFF312649),
  border: const Color(0xFF2B2140),
  border2: const Color(0xFF3B2E57),
  accent: const Color(0xFFC4A1EF),
  accentFg: const Color(0xFF190D29),
  fg1: const Color(0xFFD4CBE5),
  fg2: const Color(0xFFB3AAC9),
  fg3: const Color(0xFF8980A1),
  fg4: const Color(0xFF625978),
);

final _harbourMist = _palette(
  name: 'harbour-mist',
  label: 'Harbour Mist',
  bg: const Color(0xFF21222D),
  surface1: const Color(0xFF272937),
  surface2: const Color(0xFF2F3242),
  surface3: const Color(0xFF3D4156),
  border: const Color(0xFF373B4E),
  border2: const Color(0xFF484D66),
  accent: const Color(0xFFF7F7EF),
  accentFg: const Color(0xFF1B1C26),
  fg1: const Color(0xFFF7F8F0),
  fg2: const Color(0xFFE6E6DE),
  fg3: const Color(0xFFB8BAC7),
  fg4: const Color(0xFF888B9C),
);

final _oceanicAbyss = _palette(
  name: 'oceanic-abyss',
  label: 'Oceanic Abyss',
  bg: const Color(0xFF07101A),
  surface1: const Color(0xFF0B1522),
  surface2: const Color(0xFF0F1B29),
  surface3: const Color(0xFF162B40),
  border: const Color(0xFF142436),
  border2: const Color(0xFF1D354F),
  accent: const Color(0xFF56E7C0),
  accentFg: const Color(0xFF032118),
  fg1: const Color(0xFFD0DCE8),
  fg2: const Color(0xFFA1B3C1),
  fg3: const Color(0xFF748899),
  fg4: const Color(0xFF4E6170),
);

final _volcanicBasalt = _palette(
  name: 'volcanic-basalt',
  label: 'Volcanic Basalt',
  bg: const Color(0xFF15181A),
  surface1: const Color(0xFF1A1E20),
  surface2: const Color(0xFF202527),
  surface3: const Color(0xFF283336),
  border: const Color(0xFF262C2E),
  border2: const Color(0xFF333C3F),
  accent: const Color(0xFF87D9C5),
  accentFg: const Color(0xFF081F1A),
  fg1: const Color(0xFFD2DADB),
  fg2: const Color(0xFFACB7B7),
  fg3: const Color(0xFF828E8E),
  fg4: const Color(0xFF5B6666),
);

final _amberPhosphor = _palette(
  name: 'amber-phosphor',
  label: 'Amber Phosphor',
  bg: const Color(0xFF130F09),
  surface1: const Color(0xFF1B150B),
  surface2: const Color(0xFF231A0E),
  surface3: const Color(0xFF362812),
  border: const Color(0xFF2E2212),
  border2: const Color(0xFF473313),
  accent: const Color(0xFFFFB427),
  accentFg: const Color(0xFF241500),
  fg1: const Color(0xFFEED8B8),
  fg2: const Color(0xFFC8B292),
  fg3: const Color(0xFF998467),
  fg4: const Color(0xFF6E5D45),
);

final List<ThemePreset> allPresets = [
  _ember,
  _stone,
  _crimsonNoir,
  _desertAdobe,
  _graphiteSilver,
  _sageMist,
  _terracottaStudio,
  _volcanicCinder,
  _steelCobalt,
  _copperHearth,
  _orchidNebula,
  _deepIndigo,
  _arcticSlate,
  _pineCanopy,
  _fernCloister,
  _cyberSynth,
  _velvetRose,
  _burgundyStudy,
  _tealEstuary,
  _crtTerminal,
  _borealGlow,
  _saffronTwilight,
  _amethystGloaming,
  _harbourMist,
  _oceanicAbyss,
  _volcanicBasalt,
  _amberPhosphor,
  _tokyo,
  _mocha,
  _nord,
  _gruvbox,
  _amber,
  _midnight,
  _emerald,
  _rose,
];

class AccentPreset {
  final String name;
  final String label;
  final Color accent;
  final Color accentFg;
  const AccentPreset({
    required this.name,
    required this.label,
    required this.accent,
    required this.accentFg,
  });
}

const List<AccentPreset> allAccents = [
  AccentPreset(
    name: 'white',
    label: 'Pure White',
    accent: Color(0xFFFFFFFF),
    accentFg: Color(0xFF0A0A0A),
  ),
  AccentPreset(
    name: 'violet',
    label: 'Violet',
    accent: Color(0xFFA78BFA),
    accentFg: Color(0xFF140E2E),
  ),
  AccentPreset(
    name: 'periwinkle',
    label: 'Periwinkle',
    accent: Color(0xFF9DB0FF),
    accentFg: Color(0xFF10142A),
  ),
  AccentPreset(
    name: 'sky',
    label: 'Electric Sky',
    accent: Color(0xFF38BDF8),
    accentFg: Color(0xFF041A26),
  ),
  AccentPreset(
    name: 'cyan',
    label: 'Frost Cyan',
    accent: Color(0xFF22D3EE),
    accentFg: Color(0xFF041E24),
  ),
  AccentPreset(
    name: 'emerald',
    label: 'Emerald',
    accent: Color(0xFF34D399),
    accentFg: Color(0xFF032015),
  ),
  AccentPreset(
    name: 'lime',
    label: 'Acid Lime',
    accent: Color(0xFFA3E635),
    accentFg: Color(0xFF142103),
  ),
  AccentPreset(
    name: 'amber',
    label: 'Solar Amber',
    accent: Color(0xFFF59E0B),
    accentFg: Color(0xFF1F1200),
  ),
  AccentPreset(
    name: 'orange',
    label: 'Tangerine',
    accent: Color(0xFFFB923C),
    accentFg: Color(0xFF241002),
  ),
  AccentPreset(
    name: 'rose',
    label: 'Coral Rose',
    accent: Color(0xFFFB7185),
    accentFg: Color(0xFF28060C),
  ),
  AccentPreset(
    name: 'lavender',
    label: 'Mauve Lavender',
    accent: Color(0xFFCBA6F7),
    accentFg: Color(0xFF1E1030),
  ),
];

ThemePreset _withAccentOverride(ThemePreset base, AccentPreset? override) {
  if (override == null) return base;
  final a = override.accent;
  final hover = _lighten(a, 0.06);
  return ThemePreset(
    name: base.name,
    label: base.label,
    bg: base.bg,
    canvas: base.canvas,
    floor: base.floor,
    surface1: base.surface1,
    surface2: base.surface2,
    surface3: base.surface3,
    fg1: base.fg1,
    fg2: base.fg2,
    fg3: base.fg3,
    fg4: base.fg4,
    border: base.border,
    border2: base.border2,
    accent: a,
    accentHover: hover,
    accentFg: override.accentFg,
    accentBg: a.withValues(alpha: 0.14),
    accentLine: a.withValues(alpha: 0.38),
    accentRing: a.withValues(alpha: 0.45),
    accentFill: a,
    accentFillHover: hover,
    ok: base.ok,
    okBg: base.okBg,
    run: base.run,
    runBg: base.runBg,
    danger: base.danger,
    dangerBg: base.dangerBg,
    diffAddBg: base.diffAddBg,
    diffDelBg: base.diffDelBg,
    diffAddFg: base.diffAddFg,
    diffDelFg: base.diffDelFg,
    diffGutter: base.diffGutter,
  );
}

class FontPreset {
  final String family;
  final String label;
  final String description;
  const FontPreset({
    required this.family,
    required this.label,
    required this.description,
  });
}

const List<FontPreset> allFonts = [
  FontPreset(
    family: 'Cove',
    label: 'Cove',
    description: 'Rounded geometric with single-storey a',
  ),
  FontPreset(
    family: 'Geist',
    label: 'Geist',
    description: 'Crisp technical neo-grotesque',
  ),
  FontPreset(
    family: 'Inter',
    label: 'Inter',
    description: 'Classic high-legibility interface neo-grotesque',
  ),
  FontPreset(
    family: 'PlusJakartaSans',
    label: 'Plus Jakarta Sans',
    description: 'Sharp modern geometric grotesque',
  ),
  FontPreset(
    family: 'DMSans',
    label: 'DM Sans',
    description: 'Clean low-contrast geometric sans',
  ),
  FontPreset(
    family: 'SpaceGrotesk',
    label: 'Space Grotesk',
    description: 'Proportional technical display grotesque',
  ),
  FontPreset(
    family: 'IBMPlexSans',
    label: 'IBM Plex Sans',
    description: 'Engineered grotesque with crisp terminals',
  ),
  FontPreset(
    family: 'Manrope',
    label: 'Manrope',
    description: 'Modern semi-condensed geometric sans',
  ),
  FontPreset(
    family: 'Outfit',
    label: 'Outfit',
    description: 'Balanced geometric UI sans',
  ),
  FontPreset(
    family: 'Halden',
    label: 'Halden',
    description: 'Neutral neo-grotesque interface workhorse',
  ),
  FontPreset(
    family: 'Tessera',
    label: 'Tessera',
    description: 'Squared technical grotesque',
  ),
  FontPreset(
    family: 'Beacon',
    label: 'Beacon',
    description: 'High-legibility sans with tailed l and serifed I',
  ),
  FontPreset(
    family: 'Pebble',
    label: 'Pebble',
    description: 'Warm soft-square geometric sans',
  ),
  FontPreset(
    family: 'Mallow',
    label: 'Mallow',
    description: 'Friendly rounded sans with single-storey a',
  ),
  FontPreset(
    family: 'Rondel',
    label: 'Rondel',
    description: 'Poised geometric sans with tall ascenders',
  ),
  FontPreset(
    family: 'Alder',
    label: 'Alder',
    description: 'Warm humanist sans with open forms',
  ),
];

const List<FontPreset> allMonoFonts = [
  FontPreset(
    family: 'GeistMono',
    label: 'Geist Mono',
    description: 'Technical Swiss monospace',
  ),
  FontPreset(
    family: 'JetBrainsMono',
    label: 'JetBrains Mono',
    description: 'Developer monospace with tall x-height',
  ),
  FontPreset(
    family: 'FiraCode',
    label: 'Fira Code',
    description: 'Classic programming monospace',
  ),
  FontPreset(
    family: 'IBMPlexMono',
    label: 'IBM Plex Mono',
    description: 'Engineered technical monospace',
  ),
  FontPreset(
    family: 'SourceCodePro',
    label: 'Source Code Pro',
    description: 'Clean open-counter coding monospace',
  ),
  FontPreset(
    family: 'Inconsolata',
    label: 'Inconsolata',
    description: 'Humanist programmer monospace',
  ),
  FontPreset(
    family: 'Signal',
    label: 'Signal',
    description: 'Clean sans monospace with slab i, l and r',
  ),
  FontPreset(
    family: 'Fathom',
    label: 'Fathom',
    description: 'Squared geometric monospace with square dots',
  ),
  FontPreset(
    family: 'Tally',
    label: 'Tally',
    description: 'Warm slab monospace for code and logs',
  ),
];

// ---------------------------------------------------------------------------
// Color helpers
// ---------------------------------------------------------------------------

Color _lighten(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
      .toColor()
      .withValues(alpha: c.a);
}

// ---------------------------------------------------------------------------
// ThemeManager — singleton, persists theme & font to SharedPreferences
// ---------------------------------------------------------------------------

class ThemeManager extends ChangeNotifier {
  static const _prefsKey = 'theme_index';
  static const _accentPrefsKey = 'accent_name';
  static const _fontPrefsKey = 'ui_font_family';
  static const _monoFontPrefsKey = 'mono_font_family';

  static final ThemeManager instance = ThemeManager._();
  ThemeManager._();

  int _themeIndex = 0;
  int _accentIndex = -1; // -1 = use theme's built-in accent
  int _fontIndex = 0;
  int _monoFontIndex = 0;

  int get themeIndex => _themeIndex;
  int get accentIndex => _accentIndex;
  int get fontIndex => _fontIndex;
  int get monoFontIndex => _monoFontIndex;

  /// Combined cache key so markdown style caches invalidate on theme, accent, sans, or mono change.
  int get index =>
      _themeIndex * 100000 +
      (_accentIndex + 1) * 1000 +
      _fontIndex * 20 +
      _monoFontIndex;

  ThemePreset get baseTheme =>
      allPresets[_themeIndex.clamp(0, allPresets.length - 1)];
  AccentPreset? get customAccent =>
      _accentIndex >= 0 && _accentIndex < allAccents.length
          ? allAccents[_accentIndex]
          : null;
  ThemePreset get current => _withAccentOverride(baseTheme, customAccent);
  FontPreset get currentFont => allFonts[_fontIndex.clamp(0, allFonts.length - 1)];
  FontPreset get currentMonoFont =>
      allMonoFonts[_monoFontIndex.clamp(0, allMonoFonts.length - 1)];

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    final savedTheme = p.getInt(_prefsKey) ?? 0;
    _themeIndex = savedTheme.clamp(0, allPresets.length - 1);
    final savedAccent = p.getString(_accentPrefsKey);
    if (savedAccent != null && savedAccent.isNotEmpty) {
      _accentIndex = allAccents.indexWhere((a) => a.name == savedAccent);
    } else {
      _accentIndex = -1;
    }
    final savedFont = p.getString(_fontPrefsKey);
    if (savedFont != null) {
      final fi = allFonts.indexWhere((f) => f.family == savedFont);
      if (fi >= 0) _fontIndex = fi;
    }
    final savedMono = p.getString(_monoFontPrefsKey);
    if (savedMono != null) {
      final mi = allMonoFonts.indexWhere((f) => f.family == savedMono);
      if (mi >= 0) _monoFontIndex = mi;
    }
    notifyListeners();
  }

  Future<void> setIndex(int i) async {
    if (i < 0 || i >= allPresets.length || i == _themeIndex) return;
    _themeIndex = i;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_prefsKey, i);
    } catch (_) {}
  }

  Future<void> setName(String name) async {
    final i = allPresets.indexWhere((p) => p.name == name);
    if (i >= 0) await setIndex(i);
  }

  Future<void> setAccentName(String? name) async {
    final next = (name == null || name.isEmpty)
        ? -1
        : allAccents.indexWhere((a) => a.name == name);
    if (next == _accentIndex) return;
    _accentIndex = next;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      if (next < 0) {
        await p.remove(_accentPrefsKey);
      } else {
        await p.setString(_accentPrefsKey, allAccents[next].name);
      }
    } catch (_) {}
  }

  Future<void> setFontFamily(String family) async {
    final i = allFonts.indexWhere((f) => f.family == family);
    if (i < 0 || i == _fontIndex) return;
    _fontIndex = i;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_fontPrefsKey, family);
    } catch (_) {}
  }

  Future<void> setMonoFontFamily(String family) async {
    final i = allMonoFonts.indexWhere((f) => f.family == family);
    if (i < 0 || i == _monoFontIndex) return;
    _monoFontIndex = i;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_monoFontPrefsKey, family);
    } catch (_) {}
  }
}

/// Convenience accessor — same as `ThemeManager.instance.current`.
ThemePreset get currentTheme => ThemeManager.instance.current;

// ---------------------------------------------------------------------------
// AppColors — dynamic getters that read from the active theme preset. Every
// `AppColors.xxx` call site works unchanged; the value shifts when the user
// picks a different theme.
// ---------------------------------------------------------------------------

class AppColors {
  // Surfaces
  static Color get bg => currentTheme.bg;
  static Color get canvas => kMobile
      ? currentTheme.canvas
      : currentTheme.canvas.withValues(alpha: 0.78);
  static Color get floor => currentTheme.floor;
  static Color get surface1 => currentTheme.surface1;
  static Color get surface2 => currentTheme.surface2;
  static Color get surface3 => currentTheme.surface3;

  static Color get base => currentTheme.bg;
  static Color get raised => currentTheme.surface1;
  static Color get overlay => currentTheme.surface2;
  static Color get hover => currentTheme.surface3;
  static Color get line => currentTheme.border;
  static Color get lineStrong => currentTheme.border2;

  static const Color scrim = Color(0x99000000);
  static Color get windowBg => kMobile
      ? currentTheme.bg
      : Color.lerp(currentTheme.bg, currentTheme.surface1, 0.45)!
          .withValues(alpha: 0.92);
  static Color get sidebarPanel => kMobile
      ? currentTheme.surface1
      : currentTheme.surface1.withValues(alpha: 0.92);
  static Color get glassSurface => currentTheme.surface2;
  static Color get glassBorder => currentTheme.border;

  // Foreground
  static Color get fg1 => currentTheme.fg1;
  static Color get fg2 => currentTheme.fg2;
  static Color get fg3 => currentTheme.fg3;
  static Color get fg4 => currentTheme.fg4;

  // Borders
  static Color get border => currentTheme.border;
  static Color get border2 => currentTheme.border2;

  // Accent
  static Color get accent => currentTheme.accent;
  static Color get accentHover => currentTheme.accentHover;
  static Color get accentFg => currentTheme.accentFg;
  static Color get accentBg => currentTheme.accentBg;
  static Color get accentLine => currentTheme.accentLine;
  static Color get accentRing => currentTheme.accentRing;
  static Color get accentFill => currentTheme.accentFill;
  static Color get accentFillHover => currentTheme.accentFillHover;

  // Status
  static Color get ok => currentTheme.ok;
  static Color get okBg => currentTheme.okBg;
  static Color get run => currentTheme.run;
  static Color get runBg => currentTheme.runBg;
  static Color get danger => currentTheme.danger;
  static Color get dangerBg => currentTheme.dangerBg;

  // Diff
  static Color get diffAddBg => currentTheme.diffAddBg;
  static Color get diffDelBg => currentTheme.diffDelBg;
  static Color get diffAddFg => currentTheme.diffAddFg;
  static Color get diffDelFg => currentTheme.diffDelFg;
  static Color get diffGutter => currentTheme.diffGutter;
}

Color get readingBg => AppColors.canvas;

// ---------------------------------------------------------------------------
// Radius — small and precise. Large radii read consumer/toy; a developer tool
// wants edges that feel engineered.
// ---------------------------------------------------------------------------

class R {
  static const xs = 4.0;
  static const sm = 6.0;
  static const chip = 6.0;
  static const md = 8.0;
  static const card = 10.0;
  static const lg = 12.0;
  static const sheetTop = 20.0;
  static const pill = 999.0;
}

AnimationStyle get sheetMotion => AnimationStyle(
      duration: Motion.open,
      reverseDuration: Motion.close,
      curve: Motion.enter,
      reverseCurve: Motion.exit,
    );

/// The only spacing values the app uses.
class S {
  static const s2 = 2.0;
  static const s4 = 4.0;
  static const s6 = 6.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const s24 = 24.0;
  static const s32 = 32.0;
  static const s40 = 40.0;
}

/// Overlays lift with a surface step plus this shadow; nothing else casts one.
List<BoxShadow> get overlayShadow => const [
      BoxShadow(color: Color(0x73000000), blurRadius: 24, offset: Offset(0, 8)),
    ];

// ---------------------------------------------------------------------------
// Motion — the ONE place durations and curves are decided.
//
// Transitions used to pick their own number at each call site (11 distinct
// durations under 400ms), so the same gesture read differently on different
// screens. The stock Flutter curves are also too weak to read as intentional;
// these are the stronger custom variants.
// ---------------------------------------------------------------------------

class Motion {
  /// Pointer-down acknowledgement — the fastest thing in the app.
  static const press = Duration(milliseconds: 100);

  /// Hover, colour and icon swaps.
  static const quick = Duration(milliseconds: 150);

  /// A small surface appearing or changing: pills, chips, inline rows.
  static const fast = Duration(milliseconds: 180);

  /// Panels, drawers, switches.
  static const base = Duration(milliseconds: 220);

  /// Sheets, menus and dialogs arriving.
  static const open = Duration(milliseconds: 240);

  /// Anything leaving — always shorter than it took to arrive.
  static const close = Duration(milliseconds: 180);

  /// Route push and pop.
  static const page = Duration(milliseconds: 260);

  /// A deliberate, infrequent change. Never for a repeated interaction.
  static const slow = Duration(milliseconds: 300);

  /// One direction of the looping "working" breath on a live status glyph.
  static const pulse = Duration(milliseconds: 1150);

  /// Fast start, long soft settle — the iOS sheet curve.
  static const enter = Cubic(0.32, 0.72, 0, 1);

  static const exit = Curves.easeInCubic;

  static const move = Curves.easeInOut;
}

/// True when the platform asks for motion to be reduced.
///
/// Reduced motion means FEWER and gentler animations, not zero: opacity and
/// colour still help a person follow what changed, while position, scale and
/// looping motion are dropped. Every animated state change keeps a static cue
/// (colour, icon, label) regardless — motion is never the only channel.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

// ---------------------------------------------------------------------------
// Mobile metrics.
//
// The design language is one system at two densities, not two designs. Phones
// scale UP for touch (a 44pt minimum target) and down in density; they do NOT
// change the palette, the weight ramp, or the zero-border rule.
//
// These lived as inline `kMobile ? a : b` ternaries scattered across a 5k-line
// screen, which is how the two densities drifted apart. One table instead.
// ---------------------------------------------------------------------------

class M {
  /// Phone content follows the desktop pane/composer inset: 16px. Touch targets
  /// grow on mobile; the visual gutter does not become a second design system.
  static const gutter = 16.0;

  /// Touch geometry. These are hit areas, not typography scales.
  static const navRow = 52.0;
  static const minTarget = 44.0;
  static const appBarHeight = 56.0;

  /// Editorial hierarchy: page titles create a clear entry point, while section
  /// titles and row labels step down without collapsing into the same visual size.
  static const pageTitle = 24.0;
  static const sectionTitle = 18.0;

  /// Reading text is intentionally larger than compact metadata. The 15px row
  /// title keeps navigation scannable without competing with conversation prose.
  static const rowTitle = 15.0;
  static const body = 17.0;
  static const meta = 12.0;
  static const monoMeta = 10.0;

  /// Phone row geometry: a 52px visual rhythm with a >=44px target, rather than
  /// turning every row into a card.
  static const rowHeight = 52.0;
  static const rowPadH = 12.0;

  /// Legacy shell-strip metrics remain for narrow desktop only; phone navigation
  /// no longer renders that strip.
  static const tabStripHeight = 56.0;
  static const tabIconSize = 28.0;
  static const tabActionSize = 52.0;
}

/// Inset between a pane's edge and the composer card.
///
/// Measured: the reference's card sits at x274 inside a pane starting at x258 —
/// 16px a side. The composer was previously full-bleed when embedded, which is
/// why it stuck to the sides of the shell.
const double kComposerGutter = 16;

// ---------------------------------------------------------------------------
// Typography — Geist for UI, Geist Mono for code.
//
// The ceiling is 500. `600` exists as `strong` only for the single large page
// title; everything else is 400 with 500 reserved for controls and row titles,
// so weight reads as meaning rather than decoration.
// ---------------------------------------------------------------------------

/// Role weights — prefer these over raw `FontWeight.wNNN` so the ramp stays
/// consistent across the app.
class W {
  static const body = FontWeight.w400;
  static const label = FontWeight.w500;
  static const title = FontWeight.w500;
  static const strong = FontWeight.w600;
}

/// Phones keep every face at its regular weight: hierarchy comes from size,
/// ink and space rather than from heavier strokes.
FontWeight weightFor(FontWeight w) =>
    kMobile && w.value >= FontWeight.w600.value
        ? FontWeight.w500
        : FontWeight.w400;

/// Geist is drawn with comfortable default spacing, so body text keeps it and
/// only larger sizes tighten, up to -2% from 28px.
double _tracking(double size) =>
    size <= 13 ? 0 : size * -0.02 * ((size - 13) / 15).clamp(0.0, 1.0);

TextStyle sans(double size,
        {FontWeight weight = W.body,
        double? height,
        double? spacing,
        Color? color,
        bool tabular = false}) =>
    TextStyle(
      fontFamily: kSansFamily,
      fontSize: size,
      fontWeight: weightFor(weight),
      height: height ?? 1.33,
      letterSpacing: spacing ?? _tracking(size),
      color: color ?? AppColors.fg2,
      // Proportional digits have different widths, so a ticking timer or a
      // counter shimmers and reflows as it updates. Geist ships `tnum`
      // (verified in the font's GSUB table), so this is a real substitution.
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );

TextStyle display(double size,
        {FontWeight weight = W.title, Color? color, double? height}) =>
    TextStyle(
      fontFamily: kSansFamily,
      fontSize: size,
      fontWeight: weightFor(weight),
      height: height ?? 1.15,
      letterSpacing: _tracking(size),
      color: color ?? AppColors.fg1,
    );

TextStyle mono(double size,
        {FontWeight weight = W.body,
        double? height,
        double? spacing,
        Color? color,
        bool tabular = true}) =>
    // A monospace face is fixed-width already, so `tabular` defaults on and is
    // accepted only so call sites can share one signature with `sans()`.
    TextStyle(
      fontFamily: monoFamily,
      fontFamilyFallback: const ['GeistMono', 'monospace'],
      fontSize: size,
      fontWeight: weightFor(weight),
      height: height ?? 1.45,
      letterSpacing: spacing,
      color: color ?? AppColors.fg1,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );

/// The ONE uppercase label style: small, 500, with POSITIVE tracking.
///
/// Small capitals need a little positive letter-spacing or the letters crowd
/// together. `_tracking()` is built for sentence-case UI text and runs tight
/// from 13px up, so uppercase labels pass their own `spacing:`.
/// Five call sites had drifted into three different treatments (no spacing,
/// `0.4`, `0.5`) with three different inks; this is the single replacement.
TextStyle caps(double size,
        {Color? color, double spacing = 0.5, FontWeight weight = W.label}) =>
    sans(size, weight: weight, color: color, spacing: spacing);

String get kSansFamily => ThemeManager.instance.currentFont.family;
const kSerifFamily = 'Literata';

/// The agent's own writing on a phone: a screen serif at a reading size, so a
/// long answer reads like a page rather than a wall of UI text.
TextStyle serif(double size,
        {FontWeight weight = W.body, double? height, Color? color}) =>
    TextStyle(
      fontFamily: kSerifFamily,
      fontSize: size,
      fontWeight: weightFor(weight),
      height: height ?? 1.6,
      color: color ?? AppColors.fg1,
    );
const kMonoFamily = 'GeistMono';

String get monoFamily => ThemeManager.instance.currentMonoFont.family;

/// Type roles. Screens use these, not raw sizes.
class TS {
  static TextStyle pageTitle([Color? c]) => kMobile
      ? sans(28,
          weight: FontWeight.w700,
          height: 34 / 28,
          spacing: -0.8,
          color: c ?? AppColors.fg1)
      : sans(18, weight: W.strong, height: 24 / 18, color: c ?? AppColors.fg1);
  static TextStyle sectionTitle([Color? c]) => kMobile
      ? sans(18,
          weight: W.strong,
          height: 24 / 18,
          spacing: -0.3,
          color: c ?? AppColors.fg1)
      : sans(15, weight: W.strong, height: 20 / 15, color: c ?? AppColors.fg1);
  static TextStyle rowTitle([Color? c]) => kMobile
      ? sans(16,
          weight: W.strong,
          height: 21 / 16,
          spacing: -0.2,
          color: c ?? AppColors.fg1)
      : sans(13, weight: W.label, height: 18 / 13, color: c ?? AppColors.fg1);
  static TextStyle body([Color? c]) => sans(kMobile ? 16 : 14,
      height: kMobile ? 24 / 16 : 22 / 14, color: c ?? AppColors.fg2);
  static TextStyle ui([Color? c]) => kMobile
      ? sans(14, height: 20 / 14, color: c ?? AppColors.fg2)
      : sans(13, height: 18 / 13, color: c ?? AppColors.fg2);
  static TextStyle label([Color? c]) => kMobile
      ? sans(13, weight: W.label, height: 18 / 13, color: c ?? AppColors.fg2)
      : sans(12, weight: W.label, height: 16 / 12, color: c ?? AppColors.fg2);
  static TextStyle meta([Color? c]) =>
      sans(12, height: 16 / 12, color: c ?? AppColors.fg3, tabular: true);
  static TextStyle caption([Color? c]) =>
      sans(11, height: 14 / 11, color: c ?? AppColors.fg3);
  static TextStyle overline([Color? c]) =>
      caps(11, color: c ?? AppColors.fg3).copyWith(height: 14 / 11);

  /// The agent's prose: the body sans a step up, with reading line height.
  static TextStyle reading([Color? c]) => kMobile
      ? sans(16, height: 26 / 16, color: c ?? AppColors.fg1)
      : sans(14, height: 22 / 14, color: c ?? AppColors.fg1);
  static TextStyle code([Color? c]) =>
      mono(13, height: 20 / 13, color: c ?? AppColors.fg2);
  static TextStyle codeSmall([Color? c]) =>
      mono(12, height: 16 / 12, color: c ?? AppColors.fg3);
}

// ---------------------------------------------------------------------------
// Material ThemeData — derived from the active palette.
// ---------------------------------------------------------------------------

ThemeData buildAppTheme() {
  final c = currentTheme;
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: kSansFamily,
    brightness:
        c.bg.computeLuminance() > 0.18 ? Brightness.light : Brightness.dark,
    colorScheme: ColorScheme(
      brightness:
          c.bg.computeLuminance() > 0.18 ? Brightness.light : Brightness.dark,
      surface: c.bg,
      primary: c.accentFill,
      secondary: c.accentFill,
      error: c.danger,
      onSurface: c.fg1,
      onPrimary: c.accentFg,
      onSecondary: c.accentFg,
      onError: Colors.white,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: SnappyPageTransitionsBuilder(),
      TargetPlatform.iOS: SnappyPageTransitionsBuilder(),
      TargetPlatform.macOS: SnappyPageTransitionsBuilder(),
      TargetPlatform.windows: SnappyPageTransitionsBuilder(),
      TargetPlatform.linux: SnappyPageTransitionsBuilder(),
    }),
    dividerColor: c.border,
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: c.accent.withValues(alpha: 0.35),
      cursorColor: c.accent,
      selectionHandleColor: c.accent,
    ),
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: c.surface3.withValues(alpha: 0.7),
    hoverColor: c.surface3.withValues(alpha: 0.5),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface2,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      surfaceTintColor: Colors.transparent,
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.lg),
          side: BorderSide(color: c.border)),
    ),
    // One UI family everywhere. A second near-identical sans-serif: at UI
    // sizes the two are almost indistinguishable, so every Material widget
    // (menus, tooltips, dialogs, text fields) rendered in a different family
    // than the app's own text around it — which reads as a mistake rather than
    // a pairing. One UI family.
    textTheme: _weightedTextTheme(base.textTheme
        .apply(fontFamily: kSansFamily, bodyColor: c.fg1, displayColor: c.fg1)),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 12),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.accentFill,
      foregroundColor: c.accentFg,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.lg)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.accent),
    ),
  );
}

/// Material widgets inherit their weights from here, so this is the single
/// place that decides what reads as "heavy". Body copy stays at 400 and only
/// titles/labels step up to 500 — no 600+ anywhere in the inherited theme.
TextTheme _weightedTextTheme(TextTheme t) {
  TextStyle? w(TextStyle? s, FontWeight weight) =>
      s?.copyWith(fontWeight: weightFor(weight));
  return t.copyWith(
    displayLarge: w(t.displayLarge, W.label),
    displayMedium: w(t.displayMedium, W.label),
    displaySmall: w(t.displaySmall, W.label),
    headlineLarge: w(t.headlineLarge, W.label),
    headlineMedium: w(t.headlineMedium, W.label),
    headlineSmall: w(t.headlineSmall, W.label),
    titleLarge: w(t.titleLarge, W.label),
    titleMedium: w(t.titleMedium, W.label),
    titleSmall: w(t.titleSmall, W.label),
    bodyLarge: w(t.bodyLarge, W.body),
    bodyMedium: w(t.bodyMedium, W.body),
    bodySmall: w(t.bodySmall, W.body),
    labelLarge: w(t.labelLarge, W.label),
    labelMedium: w(t.labelMedium, W.label),
    labelSmall: w(t.labelSmall, W.label),
  );
}

/// HugeIcons semantic map. Every application icon resolves to a deliberate
/// rounded glyph instead of a generic fallback.
List<List<dynamic>> hugeIconFor(String name) {
  switch (name) {
    case 'grid':
      return HugeIcons.strokeRoundedDashboardSquare01;
    case 'chevron-left':
    case 'arrow-left':
      return HugeIcons.strokeRoundedArrowLeft01;
    case 'chevron-right':
    case 'arrow-right':
      return HugeIcons.strokeRoundedArrowRight01;
    case 'chevron-down':
      return HugeIcons.strokeRoundedArrowDown01;
    case 'chevron-up':
    case 'arrow-up':
    case 'send':
      return HugeIcons.strokeRoundedArrowUp01;
    case 'bell':
      return HugeIcons.strokeRoundedNotification01;
    case 'alert-circle':
      return HugeIcons.strokeRoundedInformationCircle;
    case 'message':
    case 'message-text':
      return HugeIcons.strokeRoundedBubbleChat;
    case 'chat-thread':
      // Sidebar chat rows. Deliberately not the bubble glyph the rest of the
      // app uses, so a conversation row reads as a thread rather than a
      // generic message.
      return HugeIcons.strokeRoundedMessageMultiple02;
    case 'users':
      return HugeIcons.strokeRoundedUserGroup;
    case 'agent':
    case 'bot':
      return HugeIcons.strokeRoundedBot;
    case 'brain':
      return HugeIcons.strokeRoundedAiBrain01;
    case 'archive':
      return HugeIcons.strokeRoundedArchive01;
    case 'plus':
    case 'add':
      return HugeIcons.strokeRoundedAdd01;
    case 'minus':
      return HugeIcons.strokeRoundedMinusSign;
    case 'x':
      return HugeIcons.strokeRoundedCancel01;
    case 'undo':
      return HugeIcons.strokeRoundedUndo02;
    case 'redo':
      return HugeIcons.strokeRoundedRedo02;
    case 'wrap':
      return HugeIcons.strokeRoundedTextWrap;
    case 'keyboard':
      return HugeIcons.strokeRoundedKeyboard;
    case 'file-code':
      return HugeIcons.strokeRoundedFileCode;
    case 'x-circle':
      return HugeIcons.strokeRoundedCancelCircle;
    case 'check-circle':
      return HugeIcons.strokeRoundedCheckmarkCircle02;
    case 'file-text':
      return HugeIcons.strokeRoundedNote01;
    case 'more-horizontal':
      return HugeIcons.strokeRoundedMoreHorizontal;
    case 'more-vertical':
      return HugeIcons.strokeRoundedMoreVertical;
    case 'search':
      return HugeIcons.strokeRoundedSearch01;
    case 'settings':
      return HugeIcons.strokeRoundedSettings01;
    case 'sliders':
      return HugeIcons.strokeRoundedSlidersHorizontal;
    case 'wifi-off':
      return HugeIcons.strokeRoundedWifiOff01;
    case 'refresh':
      return HugeIcons.strokeRoundedRefresh04;
    case 'alert-triangle':
      return HugeIcons.strokeRoundedAlert02;
    case 'check':
      return HugeIcons.strokeRoundedTick01;
    case 'check-check':
      return HugeIcons.strokeRoundedTickDouble01;
    case 'stop':
      return HugeIcons.strokeRoundedStop;
    case 'play':
      return HugeIcons.strokeRoundedPlay;
    case 'pause':
      return HugeIcons.strokeRoundedPause;
    case 'git-commit':
      return HugeIcons.strokeRoundedGitCommit;
    case 'user':
      return HugeIcons.strokeRoundedUser;
    case 'sparkles':
    case 'zap':
      return HugeIcons.strokeRoundedFlash;
    case 'mic':
      return HugeIcons.strokeRoundedMic01;
    case 'mic-off':
      return HugeIcons.strokeRoundedMicOff01;
    case 'shield':
      return HugeIcons.strokeRoundedShield01;
    case 'goal':
      return HugeIcons.strokeRoundedTarget01;
    case 'folder':
      return HugeIcons.strokeRoundedFolder01;
    case 'folder-open':
      return HugeIcons.strokeRoundedFolderOpen;
    case 'folder-plus':
      return HugeIcons.strokeRoundedFolderAdd;
    case 'upload':
      return HugeIcons.strokeRoundedUpload01;
    case 'download':
      return HugeIcons.strokeRoundedDownload01;
    case 'share':
      return HugeIcons.strokeRoundedShare08;
    case 'file':
      return HugeIcons.strokeRoundedFile01;
    case 'git-branch':
      return HugeIcons.strokeRoundedGitBranch;
    case 'worktree':
      return HugeIcons.strokeRoundedCopy01;
    case 'terminal':
      return HugeIcons.strokeRoundedComputerTerminal01;
    case 'grip':
    case 'sidebar':
    case 'menu':
      return HugeIcons.strokeRoundedMenu01;
    case 'edit':
      return HugeIcons.strokeRoundedPencilEdit01;
    case 'eye':
      return HugeIcons.strokeRoundedView;
    case 'eye-off':
      return HugeIcons.strokeRoundedViewOff;
    case 'code':
      return HugeIcons.strokeRoundedCode;
    case 'book':
      return HugeIcons.strokeRoundedBook01;
    case 'trash':
      return HugeIcons.strokeRoundedDelete01;
    case 'copy':
      return HugeIcons.strokeRoundedCopy01;
    case 'cube':
      return HugeIcons.strokeRoundedBubbleChat;
    case 'inbox':
      return HugeIcons.strokeRoundedInbox;
    case 'transfer':
      return HugeIcons.strokeRoundedArrowLeftRight;
    case 'key':
      return HugeIcons.strokeRoundedKey01;
    case 'cpu':
      return HugeIcons.strokeRoundedCpu;
    case 'layers':
      return HugeIcons.strokeRoundedLayers01;
    case 'activity':
      return HugeIcons.strokeRoundedActivity01;
    case 'image':
      return HugeIcons.strokeRoundedImage01;
    case 'film':
      return HugeIcons.strokeRoundedFilm01;
    case 'music':
      return HugeIcons.strokeRoundedMusicNote01;
    case 'pdf':
      return HugeIcons.strokeRoundedPdf01;
    case 'scan':
      return HugeIcons.strokeRoundedScan;
    case 'camera':
      return HugeIcons.strokeRoundedCamera01;
    case 'camera-off':
      return HugeIcons.strokeRoundedCameraOff01;
    case 'clipboard':
      return HugeIcons.strokeRoundedClipboard;
    case 'history':
    case 'clock':
      return HugeIcons.strokeRoundedClock01;
    case 'minimize':
      return HugeIcons.strokeRoundedMinusSign;
    case 'expand':
      return HugeIcons.strokeRoundedArrowExpand01;
    case 'shrink':
      return HugeIcons.strokeRoundedArrowShrink01;
    case 'rotate':
      return HugeIcons.strokeRoundedRotate01;
    case 'globe':
      return HugeIcons.strokeRoundedGlobal;
    case 'map':
      return HugeIcons.strokeRoundedMaps;
    case 'list':
      return HugeIcons.strokeRoundedLeftToRightListBullet;
    case 'task':
      return HugeIcons.strokeRoundedCheckList;
    case 'kanban':
      return HugeIcons.strokeRoundedKanban;
    case 'file-plus':
      return HugeIcons.strokeRoundedFileAdd;
    case 'corner-down-right':
      return HugeIcons.strokeRoundedArrowDownRight01;
    case 'home':
      return HugeIcons.strokeRoundedHome01;
    case 'scheduled':
      return HugeIcons.strokeRoundedCalendar01;
    case 'coordination':
      return HugeIcons.strokeRoundedRoute01;
    case 'split':
      return HugeIcons.strokeRoundedLayout2Column;
    case 'processes':
      return HugeIcons.strokeRoundedActivity01;
    // Settings-section glyphs. Each names what the section actually holds, so
    // the icons are readable without the label: a machine is a server stack,
    // not a CPU (a CPU is a chip INSIDE the machine); inference profiles are the
    // model layer; usage is spend; the vault is a locked key; scheduled work is
    // a repeat cycle rather than a bare calendar date.
    case 'server':
      return HugeIcons.strokeRoundedServerStack01;
    case 'ai-chip':
      return HugeIcons.strokeRoundedAiChip;
    case 'analytics':
      return HugeIcons.strokeRoundedAnalytics01;
    case 'lock-key':
      return HugeIcons.strokeRoundedLockKey;
    case 'repeat':
      return HugeIcons.strokeRoundedRepeat;
    default:
      return HugeIcons.strokeRoundedCircle;
  }
}

/// Route transition: a short slide with a fade, settling on [Motion.enter].
/// The outgoing page drifts a little the other way so the two read as one move.
class SnappyPageTransitionsBuilder extends PageTransitionsBuilder {
  const SnappyPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Motion.page;

  @override
  Duration get reverseTransitionDuration => Motion.close;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final incoming = CurvedAnimation(
        parent: animation, curve: Motion.enter, reverseCurve: Motion.exit);
    final outgoing = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Motion.enter,
        reverseCurve: Motion.exit);
    return SlideTransition(
      position: Tween(begin: Offset.zero, end: const Offset(-0.06, 0))
          .animate(outgoing),
      child: SlideTransition(
        position: Tween(begin: const Offset(0.08, 0), end: Offset.zero)
            .animate(incoming),
        child: FadeTransition(opacity: incoming, child: child),
      ),
    );
  }
}
