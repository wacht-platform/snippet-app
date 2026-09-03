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

// The only client theme. Other palettes were removed on request.
final _amoled = _dark(
  name: 'amoled',
  label: 'AMOLED Black',
  accent: const Color(0xFF60A5FA),
  text: const Color(0xFFE5E7EB),
  muted: const Color(0xFF9CA3AF),
  faint: const Color(0xFF6B7280),
  success: const Color(0xFF34D399),
  danger: const Color(0xFFF87171),
  warn: const Color(0xFFFBBF24),
  isAmoled: true,
);

List<ThemePreset> get allPresets => [_amoled];

// ---------------------------------------------------------------------------
// Color helpers
// ---------------------------------------------------------------------------

Color _withAlpha(Color c, double a) => c.withValues(alpha: a);
Color _alphaWhite(double a) => Color.fromRGBO(255, 255, 255, a);
Color _nearBlack() => const Color(0xFF160E02);

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
// Radius — crisp but friendly corners.
// ---------------------------------------------------------------------------

class R {
  static const card = 14.0;
  static const md = 12.0;
  static const sm = 8.0;
  static const xs = 6.0;
  static const sheetTop = 16.0;
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
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.card),
          side: BorderSide(color: c.border)),
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
    case 'arrow-left':
      return IconsaxPlusLinear.arrow_left_2;
    case 'chevron-right':
      return Icons.chevron_right_rounded;
    case 'bell':
      return IconsaxPlusLinear.notification;
    case 'alert-circle':
      return IconsaxPlusLinear.info_circle;
    case 'message':
      return IconsaxPlusLinear.message_text_1;
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
