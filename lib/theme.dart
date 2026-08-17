import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
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

// Helper: derive dark surfaces + status from a TUI accent/text palette.
ThemePreset _dark({
  required String name,
  required String label,
  required Color accent,
  required Color text,
  required Color muted,
  required Color faint,
  required Color success,
  required Color danger,
  required Color warn,
  bool isAmoled = false,
}) {
  // Surfaces: neutral grays (no color tint) — Grok-style.
  // AMOLED mode: pure #000000 for deepest blacks on OLED screens.
  final bg = isAmoled ? const Color(0xFF000000) : const Color(0xFF121212);
  final canvas = isAmoled ? const Color(0xFF000000) : const Color(0xFF181818);
  final surface1 = isAmoled ? const Color(0xFF0A0A0A) : const Color(0xFF1E1E1E);
  final surface2 = isAmoled ? const Color(0xFF141414) : const Color(0xFF2A2A2A);
  final surface3 = isAmoled ? const Color(0xFF1E1E1E) : const Color(0xFF363636);

  return ThemePreset(
    name: name,
    label: label,
    bg: bg,
    canvas: canvas,
    surface1: surface1,
    surface2: surface2,
    surface3: surface3,
    fg1: text,
    fg2: muted,
    fg3: _lighten(muted, 0.15),
    fg4: _lighten(faint, 0.20),
    border: _alphaWhite(0.09),
    border2: _alphaWhite(0.14),
    accent: accent,
    accentHover: _lighten(accent, 0.12),
    accentFg: _nearBlack(),
    accentBg: _withAlpha(accent, 0.15),
    accentLine: _withAlpha(accent, 0.40),
    accentRing: _withAlpha(accent, 0.30),
    ok: success,
    okBg: _withAlpha(success, 0.15),
    run: warn,
    runBg: _withAlpha(warn, 0.15),
    danger: danger,
    dangerBg: _withAlpha(danger, 0.15),
    diffAddBg: _withAlpha(success, 0.12),
    diffDelBg: _withAlpha(danger, 0.12),
    diffAddFg: _lighten(success, 0.20),
    diffDelFg: _lighten(danger, 0.20),
    diffGutter: _lighten(faint, 0.15),
  );
}

// Light theme helper: white-based surfaces.
ThemePreset _light({
  required String name,
  required String label,
  required Color accent,
  required Color text,
  required Color muted,
  required Color faint,
  required Color success,
  required Color danger,
  required Color warn,
}) {
  return ThemePreset(
    name: name,
    label: label,
    bg: const Color(0xFFF5F5F5),
    canvas: const Color(0xFFFFFFFF),
    surface1: const Color(0xFFFFFFFF),
    surface2: const Color(0xFFF0F0F0),
    surface3: const Color(0xFFE5E5E5),
    fg1: text,
    fg2: muted,
    fg3: _lighten(muted, 0.2),
    fg4: faint,
    border: _alphaBlack(0.08),
    border2: _alphaBlack(0.14),
    accent: accent,
    accentHover: _darken(accent, 0.08),
    accentFg: const Color(0xFFFFFFFF),
    accentBg: _withAlpha(accent, 0.12),
    accentLine: _withAlpha(accent, 0.35),
    accentRing: _withAlpha(accent, 0.25),
    ok: success,
    okBg: _withAlpha(success, 0.12),
    run: warn,
    runBg: _withAlpha(warn, 0.12),
    danger: danger,
    dangerBg: _withAlpha(danger, 0.12),
    diffAddBg: _withAlpha(success, 0.10),
    diffDelBg: _withAlpha(danger, 0.10),
    diffAddFg: _darken(success, 0.15),
    diffDelFg: _darken(danger, 0.15),
    diffGutter: faint,
  );
}

// ---------------------------------------------------------------------------
// 4 curated presets — each one beautiful, no filler.
// ---------------------------------------------------------------------------

const _terminalInk = ThemePreset(
  name: 'terminal-ink',
  label: 'Terminal Ink',
  bg: Color(0xFF121212),
  canvas: Color(0xFF181818),
  surface1: Color(0xFF1E1E1E),
  surface2: Color(0xFF2A2A2A),
  surface3: Color(0xFF363636),
  fg1: Color(0xFFE8ECEA),
  fg2: Color(0xFFB0B8B4),
  fg3: Color(0xFF8A918E),
  fg4: Color(0xFF6E7572),
  border: Color(0x17FFFFFF),
  border2: Color(0x24FFFFFF),
  accent: Color(0xFFE0A458),
  accentHover: Color(0xFFEBB470),
  accentFg: Color(0xFF160E02),
  accentBg: Color(0x26E0A458),
  accentLine: Color(0x66E0A458),
  accentRing: Color(0x4DE0A458),
  ok: Color(0xFF7BC49A),
  okBg: Color(0x267BC49A),
  run: Color(0xFFE0A458),
  runBg: Color(0x26E0A458),
  danger: Color(0xFFE86A6A),
  dangerBg: Color(0x26E86A6A),
  diffAddBg: Color(0x1F7BC49A),
  diffDelBg: Color(0x1FE86A6A),
  diffAddFg: Color(0xFF9AD4B4),
  diffDelFg: Color(0xFFF0A0A0),
  diffGutter: Color(0xFF6E7572),
);

final _nord = _dark(
  name: 'nord',
  label: 'Nord',
  accent: const Color(0xFF88C0D0),
  text: const Color(0xFFD8DEE9),
  muted: const Color(0xFFA0AAB8),
  faint: const Color(0xFF7B8899),
  success: const Color(0xFFA3BE8C),
  danger: const Color(0xFFBF616A),
  warn: const Color(0xFFEBCB8B),
);

final _dracula = _dark(
  name: 'dracula',
  label: 'Dracula',
  accent: const Color(0xFFBD93F9),
  text: const Color(0xFFF8F8F2),
  muted: const Color(0xFFB0B8D0),
  faint: const Color(0xFF8890B0),
  success: const Color(0xFF50FA7B),
  danger: const Color(0xFFFF5555),
  warn: const Color(0xFFF1FA8C),
);

final _lightPreset = _light(
  name: 'light',
  label: 'Light',
  accent: const Color(0xFF2563EB),
  text: const Color(0xFF1E293B),
  muted: const Color(0xFF475569),
  faint: const Color(0xFF94A3B8),
  success: const Color(0xFF15804C),
  danger: const Color(0xFFDC2626),
  warn: const Color(0xFFD97706),
);

// Rosé Pine — moody dark blue-purple with soft rose accents. Cozy, elegant, low-strain.
final _rosePine = _dark(
  name: 'rose-pine',
  label: 'Rosé Pine',
  accent: const Color(0xFFEB6F92), // love (rose)
  text: const Color(0xFFE0DEF4), // text
  muted: const Color(0xFF908CAA), // subtle
  faint: const Color(0xFF6E6A86), // muted
  success: const Color(0xFF9CCFD8), // foam
  danger: const Color(0xFFEB6F92), // love
  warn: const Color(0xFFF6C177), // gold
);

// Everforest Dark — earthy green-gray warmth. Calm, natural, easy on the eyes.
final _everforest = _dark(
  name: 'everforest',
  label: 'Everforest',
  accent: const Color(0xFFA7C080), // green
  text: const Color(0xFFD3C6AA), // fg
  muted: const Color(0xFF8A9B8E), // grey1
  faint: const Color(0xFF56635F), // grey2
  success: const Color(0xFFA7C080), // green
  danger: const Color(0xFFE67E80), // red
  warn: const Color(0xFFDBBC7F), // orange
);

// Kanagawa Wave — ink-black indigo with Hokusai-inspired muted jewel tones.
final _kanagawa = _dark(
  name: 'kanagawa',
  label: 'Kanagawa Wave',
  accent: const Color(0xFF7E9CD8),
  text: const Color(0xFFDCD7BA),
  muted: const Color(0xFFA6A69C),
  faint: const Color(0xFF727169),
  success: const Color(0xFF98BB6C),
  danger: const Color(0xFFC34043),
  warn: const Color(0xFFE6C384),
);

// Ayu Mirage — warm charcoal, amber focus, and restrained blue-green status.
final _ayuMirage = _dark(
  name: 'ayu-mirage',
  label: 'Ayu Mirage',
  accent: const Color(0xFFFFCC66),
  text: const Color(0xFFCCCAC2),
  muted: const Color(0xFFABB0B6),
  faint: const Color(0xFF5C6773),
  success: const Color(0xFFBAE67E),
  danger: const Color(0xFFF07178),
  warn: const Color(0xFFFFCC66),
);

// Night Owl — crisp slate navy designed for long, low-light coding sessions.
final _nightOwl = _dark(
  name: 'night-owl',
  label: 'Night Owl',
  accent: const Color(0xFF82AAFF),
  text: const Color(0xFFD6DEEB),
  muted: const Color(0xFF9DB1C5),
  faint: const Color(0xFF637777),
  success: const Color(0xFFADDB67),
  danger: const Color(0xFFEF5350),
  warn: const Color(0xFFFFCB6B),
);

// Monokai Pro — high-clarity charcoal with lively, carefully balanced accents.
final _monokaiPro = _dark(
  name: 'monokai-pro',
  label: 'Monokai Pro',
  accent: const Color(0xFFFC9867),
  text: const Color(0xFFFCFCFA),
  muted: const Color(0xFFC1C0C0),
  faint: const Color(0xFF727072),
  success: const Color(0xFFA9DC76),
  danger: const Color(0xFFFF6188),
  warn: const Color(0xFFFFD866),
);

// Oxocarbon — IBM Carbon's deep graphite base and cool blue focus color.
final _oxocarbon = _dark(
  name: 'oxocarbon',
  label: 'Oxocarbon',
  accent: const Color(0xFF78A9FF),
  text: const Color(0xFFF2F4F8),
  muted: const Color(0xFFBBC3CF),
  faint: const Color(0xFF697077),
  success: const Color(0xFF42BE65),
  danger: const Color(0xFFFF7EB6),
  warn: const Color(0xFFF1C21B),
);

// Pure black AMOLED theme — deepest blacks, no surface elevation.
final _amoled = _dark(
  name: 'amoled',
  label: 'AMOLED Black',
  accent: const Color(0xFF60A5FA), // blue-400
  text: const Color(0xFFE5E7EB), // gray-200
  muted: const Color(0xFF9CA3AF), // gray-400
  faint: const Color(0xFF6B7280), // gray-500
  success: const Color(0xFF34D399), // emerald-400
  danger: const Color(0xFFF87171), // red-400
  warn: const Color(0xFFFBBF24), // amber-400
  isAmoled: true,
);

List<ThemePreset> get allPresets => [
      _kanagawa,
      _ayuMirage,
      _nightOwl,
      _monokaiPro,
      _oxocarbon,
      _amoled,
      _terminalInk,
      _nord,
      _dracula,
      _rosePine,
      _everforest,
      _lightPreset,
    ];

// ---------------------------------------------------------------------------
// Color helpers
// ---------------------------------------------------------------------------

Color _withAlpha(Color c, double a) => c.withValues(alpha: a);
Color _alphaWhite(double a) => Color.fromRGBO(255, 255, 255, a);
Color _alphaBlack(double a) => Color.fromRGBO(0, 0, 0, a);
Color _nearBlack() => const Color(0xFF160E02);

Color _lighten(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
      .toColor()
      .withValues(alpha: c.a);
}

Color _darken(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
      .toColor()
      .withValues(alpha: c.a);
}

// ---------------------------------------------------------------------------
// ThemeManager — singleton, persists to SharedPreferences, notifies listeners
// ---------------------------------------------------------------------------

class ThemeManager extends ChangeNotifier {
  static const _prefsKey = 'theme_index';
  static const _defaultIndex = 0; // Terminal Ink

  static final ThemeManager instance = ThemeManager._();
  ThemeManager._();

  int _index = _defaultIndex;
  int get index => _index;
  ThemePreset get current => allPresets[_index];

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getInt(_prefsKey);
    if (saved != null && saved >= 0 && saved < allPresets.length) {
      _index = saved;
    }
  }

  Future<void> setIndex(int i) async {
    if (i < 0 || i >= allPresets.length || i == _index) return;
    _index = i;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_prefsKey, i);
  }

  Future<void> setName(String name) async {
    final i = allPresets.indexWhere((p) => p.name == name);
    if (i >= 0) await setIndex(i);
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
  static Color get canvas => currentTheme.canvas;
  static Color get surface1 => currentTheme.surface1;
  static Color get surface2 => currentTheme.surface2;
  static Color get surface3 => currentTheme.surface3;

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

/// Reading/content surfaces (chat, editor, file viewer, diff). Phones use ONE
/// background everywhere (the darker `bg` — no sidebar/canvas split on a small
/// screen); desktop keeps the lighter canvas against the darker sidebar.
Color get readingBg => kMobile ? AppColors.bg : AppColors.canvas;

// ---------------------------------------------------------------------------
// Radius — crisp but friendly corners.
// ---------------------------------------------------------------------------

class R {
  static const card = 10.0;
  static const md = 8.0;
  static const sm = 6.0;
  static const xs = 4.0;
  static const sheetTop = 12.0;
}

// ---------------------------------------------------------------------------
// Typography — Inter for UI (clean, readable at all sizes), Geist Mono for code.
// ---------------------------------------------------------------------------

FontWeight _cap(FontWeight w) => w.value > 400 ? FontWeight.w400 : w;

TextStyle sans(double size,
        {FontWeight weight = FontWeight.w400,
        double? height,
        double? spacing,
        Color? color}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: _cap(weight),
      height: height ?? 1.45,
      letterSpacing: spacing ?? (size >= 16 ? -0.2 : -0.1),
      color: color ?? AppColors.fg1,
    );

TextStyle display(double size, {Color? color, double? height}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: FontWeight.w400,
      height: height,
      letterSpacing: -0.3,
      color: color ?? AppColors.fg1,
    );

TextStyle mono(double size,
        {FontWeight weight = FontWeight.w400, double? height, Color? color}) =>
    GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: _cap(weight),
      height: height ?? 1.45,
      color: color ?? AppColors.fg1,
    );

String get monoFamily => GoogleFonts.jetBrainsMono().fontFamily ?? 'monospace';

// ---------------------------------------------------------------------------
// Material ThemeData — derived from the active palette.
// ---------------------------------------------------------------------------

ThemeData buildAppTheme() {
  final c = currentTheme;
  final base = ThemeData(
    useMaterial3: true,
    brightness:
        c.bg.computeLuminance() > 0.18 ? Brightness.light : Brightness.dark,
    colorScheme: ColorScheme(
      brightness:
          c.bg.computeLuminance() > 0.18 ? Brightness.light : Brightness.dark,
      surface: c.bg,
      primary: c.accent,
      secondary: c.accent,
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
    dividerColor: c.border,
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: _withAlpha(c.accent, 0.35),
      cursorColor: c.accent,
      selectionHandleColor: c.accent,
    ),
    splashColor: c.surface3.withValues(alpha: 0.4),
    highlightColor: c.surface3.withValues(alpha: 0.3),
    hoverColor: c.surface3.withValues(alpha: 0.35),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface1,
      elevation: 8,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
          side: BorderSide(color: c.border2)),
    ),
    textTheme: _allRegular(GoogleFonts.interTextTheme(base.textTheme)
        .apply(bodyColor: c.fg1, displayColor: c.fg1)),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 12),
  );
}

TextTheme _allRegular(TextTheme t) {
  TextStyle? r(TextStyle? s) => s?.copyWith(fontWeight: FontWeight.w400);
  return t.copyWith(
    displayLarge: r(t.displayLarge),
    displayMedium: r(t.displayMedium),
    displaySmall: r(t.displaySmall),
    headlineLarge: r(t.headlineLarge),
    headlineMedium: r(t.headlineMedium),
    headlineSmall: r(t.headlineSmall),
    titleLarge: r(t.titleLarge),
    titleMedium: r(t.titleMedium),
    titleSmall: r(t.titleSmall),
    bodyLarge: r(t.bodyLarge),
    bodyMedium: r(t.bodyMedium),
    bodySmall: r(t.bodySmall),
    labelLarge: r(t.labelLarge),
    labelMedium: r(t.labelMedium),
    labelSmall: r(t.labelSmall),
  );
}

// ---------------------------------------------------------------------------
// Icon map
// ---------------------------------------------------------------------------

IconData iconFor(String name) {
  switch (name) {
    case 'chevron-left':
      return Icons.chevron_left_rounded;
    case 'chevron-right':
      return Icons.chevron_right_rounded;
    case 'chevron-down':
      return Icons.expand_more_rounded;
    case 'chevron-up':
      return Icons.expand_less_rounded;
    case 'arrow-right':
      return Icons.arrow_forward_rounded;
    case 'plus':
      return IconsaxPlusLinear.add;
    case 'x':
      return Icons.close_rounded;
    case 'more-vertical':
      return Icons.more_vert;
    case 'search':
      return IconsaxPlusLinear.search_normal_1;
    case 'settings':
      return IconsaxPlusLinear.setting_2;
    case 'sliders':
      return IconsaxPlusLinear.setting_4;
    case 'wifi-off':
      return IconsaxPlusLinear.wifi;
    case 'refresh':
      return IconsaxPlusLinear.refresh_2;
    case 'alert-triangle':
      return IconsaxPlusLinear.warning_2;
    case 'check':
      return Icons.check_rounded;
    case 'check-check':
      return Icons.done_all_rounded;
    case 'stop':
      return IconsaxPlusLinear.stop;
    case 'play':
      return Icons.play_arrow_rounded;
    case 'pause':
      return Icons.pause_rounded;
    case 'send':
    case 'arrow-up':
      return IconsaxPlusLinear.arrow_up_3;
    case 'sparkles':
      return IconsaxPlusLinear.flash_1;
    case 'mic':
      return Icons.mic_none_rounded;
    case 'mic-off':
      return Icons.mic_off_rounded;
    case 'shield':
      return IconsaxPlusLinear.shield_tick;
    case 'goal':
      return Icons.gps_fixed_rounded;
    case 'folder':
      return IconsaxPlusLinear.folder_2;
    case 'folder-open':
      return IconsaxPlusLinear.folder_open;
    case 'folder-plus':
      return IconsaxPlusLinear.folder_add;
    case 'upload':
      return IconsaxPlusLinear.document_upload;
    case 'download':
      return IconsaxPlusLinear.document_download;
    case 'file':
      return IconsaxPlusLinear.document_text;
    case 'git-branch':
      return IconsaxPlusLinear.hierarchy;
    case 'terminal':
      return IconsaxPlusLinear.code;
    case 'grip':
      return IconsaxPlusLinear.menu;
    case 'edit':
      return IconsaxPlusLinear.edit_2;
    case 'trash':
      return IconsaxPlusLinear.trash;
    case 'key':
      return IconsaxPlusLinear.key;
    case 'cpu':
      return IconsaxPlusLinear.cpu;
    case 'layers':
      return IconsaxPlusLinear.layer;
    case 'activity':
      return IconsaxPlusLinear.activity;
    case 'image':
      return IconsaxPlusLinear.gallery;
    case 'scan':
      return IconsaxPlusLinear.scan;
    case 'camera':
      return IconsaxPlusLinear.camera;
    case 'camera-off':
      return IconsaxPlusLinear.camera_slash;
    case 'clipboard':
      return IconsaxPlusLinear.clipboard_text;
    case 'history':
      return IconsaxPlusLinear.timer_1;
    case 'zap':
      return IconsaxPlusLinear.flash_1;
    case 'minimize':
      return IconsaxPlusLinear.minus;
    case 'rotate':
      return IconsaxPlusLinear.rotate_left;
    case 'globe':
      return IconsaxPlusLinear.global;
    case 'map':
      return IconsaxPlusLinear.map;
    case 'list':
      return IconsaxPlusLinear.menu;
    case 'file-plus':
      return IconsaxPlusLinear.document_upload;
    case 'corner-down-right':
      return IconsaxPlusLinear.direct_right;
    case 'home':
      return IconsaxPlusLinear.home_2;
    case 'clock':
      return IconsaxPlusLinear.clock;
    case 'sidebar':
      return IconsaxPlusLinear.menu;
    case 'menu':
      return IconsaxPlusLinear.menu;
    default:
      return IconsaxPlusLinear.element_3;
  }
}
