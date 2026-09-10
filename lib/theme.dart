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

// Helper: build the palette. Surfaces follow a "surface ladder" — hierarchy
// comes from surface lift + hairlines, not drop shadows. Text follows a strict
// brightness ladder so fg1 > fg2 > fg3 > fg4 always holds.
ThemePreset _dark({
  required String name,
  required String label,
  required Color accent,
  required Color ink,
  required Color inkMuted,
  required Color inkSubtle,
  required Color inkFaint,
  required Color success,
  required Color danger,
  required Color warn,
}) {
  // Surface ladder:
  // #0C0C0F background, #121216 sidebar, #1B1B22 cards/active, #24242E hover
  final bg = const Color(0xFF0C0C0F); // page floor — shell canvas
  final canvas = const Color(0xFF101014); // reading surface
  final surface1 = const Color(0xFF14141A); // cards, panels
  final surface2 = const Color(0xFF1B1B22); // active tab / active row card
  final surface3 = const Color(0xFF24242E); // dropdowns, popovers, hover

  return ThemePreset(
    name: name,
    label: label,
    bg: bg,
    canvas: canvas,
    surface1: surface1,
    surface2: surface2,
    surface3: surface3,
    fg1: ink,
    fg2: inkMuted,
    fg3: inkSubtle,
    fg4: inkFaint,
    // Hairlines:
    border: const Color(0xFF22222A),
    border2: const Color(0xFF2E2E38),
    accent: accent,
    accentHover: _lighten(accent, 0.10),
    accentFg: const Color(0xFFFFFFFF),
    accentBg: _withAlpha(accent, 0.14),
    accentLine: _withAlpha(accent, 0.38),
    accentRing: _withAlpha(accent, 0.45),
    ok: success,
    okBg: _withAlpha(success, 0.13),
    run: warn,
    runBg: _withAlpha(warn, 0.13),
    danger: danger,
    dangerBg: _withAlpha(danger, 0.13),
    diffAddBg: _withAlpha(success, 0.10),
    diffDelBg: _withAlpha(danger, 0.10),
    diffAddFg: _lighten(success, 0.14),
    diffDelFg: _lighten(danger, 0.14),
    diffGutter: const Color(0xFF383846),
  );
}

// The only client theme.
final _amoled = _dark(
  name: 'amoled',
  label: 'Dark',
  accent: const Color(0xFF4E88FF), // vibrant blue
  ink: const Color(0xFFF2F2F6), // near-white
  inkMuted: const Color(0xFF9EA0B0), // secondary
  inkSubtle: const Color(0xFF686A78), // tertiary
  inkFaint: const Color(0xFF4A4C58), // disabled
  success: const Color(0xFF22C55E), // green status
  danger: const Color(0xFFEF4444), // red danger
  warn: const Color(0xFFF59E0B), // amber
);

List<ThemePreset> get allPresets => [_amoled];

// ---------------------------------------------------------------------------
// Color helpers
// ---------------------------------------------------------------------------

Color _withAlpha(Color c, double a) => c.withValues(alpha: a);

Color _lighten(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
      .toColor()
      .withValues(alpha: c.a);
}

// ---------------------------------------------------------------------------
// ThemeManager — singleton, persists to SharedPreferences, notifies listeners
// ---------------------------------------------------------------------------

class ThemeManager extends ChangeNotifier {
  static const _prefsKey = 'theme_index';
  static const _defaultIndex = 0; // AMOLED Black — the only remaining preset

  static final ThemeManager instance = ThemeManager._();
  ThemeManager._();

  int _index = _defaultIndex;
  int get index => _index;
  ThemePreset get current => allPresets[0];

  Future<void> init() async {
    _index = 0;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_prefsKey, 0);
  }

  Future<void> setIndex(int i) async {
    if (i != 0) return;
    _index = 0;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_prefsKey, 0);
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
// Radius — small and precise. Large radii read consumer/toy; a developer tool
// wants edges that feel engineered.
// ---------------------------------------------------------------------------

class R {
  static const card = 8.0;
  static const md = 6.0;
  static const sm = 4.0;
  static const xs = 4.0;
  static const sheetTop = 12.0;
}

// ---------------------------------------------------------------------------
// Typography — Inter for UI, JetBrains Mono for code.
//
// Weights are a real ramp, NOT capped. Capping every call at 400 removed all
// weight-based hierarchy: 119 call sites asked for emphasis and every one
// rendered regular, leaving size as the only differentiator, which reads flat.
// 400 body · 500 labels/emphasis · 600 titles/active.
// ---------------------------------------------------------------------------

/// Role weights — prefer these over raw `FontWeight.wNNN` so the ramp stays
/// consistent across the app.
class W {
  static const body = FontWeight.w400;
  static const label = FontWeight.w500;
  static const title = FontWeight.w600;
  static const strong = FontWeight.w700;
}

/// Optical tracking: tighter as type grows. Large text needs negative tracking
/// to avoid looking loose; small text must stay open to remain legible.
double _tracking(double size) {
  if (size >= 32) return -0.8;
  if (size >= 24) return -0.5;
  if (size >= 17) return -0.2;
  if (size >= 14) return -0.05;
  if (size >= 13) return 0;
  return 0.1;
}

TextStyle sans(double size,
        {FontWeight weight = W.body,
        double? height,
        double? spacing,
        Color? color}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      height: height ?? 1.45,
      letterSpacing: spacing ?? _tracking(size),
      color: color ?? AppColors.fg1,
    );

TextStyle display(double size,
        {FontWeight weight = W.title, Color? color, double? height}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      height: height ?? 1.2,
      letterSpacing: _tracking(size),
      color: color ?? AppColors.fg1,
    );

TextStyle mono(double size,
        {FontWeight weight = W.body, double? height, Color? color}) =>
    GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
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
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
          side: BorderSide(color: c.border)),
    ),
    textTheme: _weightedTextTheme(
        GoogleFonts.interTextTheme(base.textTheme)
            .apply(bodyColor: c.fg1, displayColor: c.fg1)),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 12),
  );
}

/// Give the Material text theme a real weight ramp instead of flattening
/// everything to 400: display/headline/title carry weight, body stays regular,
/// labels sit at 500. Material widgets inherit this, so they stop reading flat.
TextTheme _weightedTextTheme(TextTheme t) {
  TextStyle? w(TextStyle? s, FontWeight weight) =>
      s?.copyWith(fontWeight: weight);
  return t.copyWith(
    displayLarge: w(t.displayLarge, W.title),
    displayMedium: w(t.displayMedium, W.title),
    displaySmall: w(t.displaySmall, W.title),
    headlineLarge: w(t.headlineLarge, W.title),
    headlineMedium: w(t.headlineMedium, W.title),
    headlineSmall: w(t.headlineSmall, W.title),
    titleLarge: w(t.titleLarge, W.title),
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

// ---------------------------------------------------------------------------
// Icon map
// ---------------------------------------------------------------------------

IconData iconFor(String name) {
  switch (name) {
    case 'chevron-left':
      return Icons.chevron_left_rounded;
    case 'arrow-left':
      return IconsaxPlusLinear.arrow_left_2;
    case 'chevron-right':
      return Icons.chevron_right_rounded;
    case 'bell':
      return IconsaxPlusLinear.notification;
    case 'alert-circle':
      return IconsaxPlusLinear.info_circle;
    case 'message':
    case 'message-text':
      return IconsaxPlusLinear.message_text_1;
    case 'users':
      return IconsaxPlusLinear.profile_2user;
    case 'archive':
      return IconsaxPlusLinear.archive;
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
      return IconsaxPlusLinear.microphone_2;
    case 'mic-off':
      return IconsaxPlusLinear.microphone_slash;
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
    case 'eye':
      return IconsaxPlusLinear.eye;
    case 'code':
      return IconsaxPlusLinear.document_code_2;
    case 'book':
      return IconsaxPlusLinear.book_1;
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
    case 'scheduled':
      return IconsaxPlusLinear.calendar_tick;
    case 'sidebar':
      return IconsaxPlusLinear.menu;
    case 'menu':
      return IconsaxPlusLinear.menu;
    default:
      return IconsaxPlusLinear.element_3;
  }
}
