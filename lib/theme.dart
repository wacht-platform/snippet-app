import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // One dark surface ladder for desktop and phone. Reading content is the
  // darkest plane; shell chrome, active rows, and inputs step upward without
  // borders or card shadows inventing a separate visual language.
  //
  // NEUTRAL GREY — deliberately no blue channel offset. The previous ladder
  // carried a small blue bias (each surface had B = R + 3..8), which is
  // invisible in isolation but reads as a lavender/purple cast in a large
  // filled area such as the composer card or a sheet. Depth comes from
  // lightness alone.
  final canvas = const Color(0xFF0C0C0C); // chat / reader — darkest
  final bg = const Color(0xFF101010); // shell chrome and navigation
  final floor = const Color(0xFF141414); // secondary panes and sheets
  final surface1 = const Color(0xFF161616); // quiet raised content
  final surface2 = const Color(0xFF1B1B1B); // active row / selection
  final surface3 = const Color(0xFF222222); // inputs, menus, hover

  return ThemePreset(
    name: name,
    label: label,
    bg: bg,
    canvas: canvas,
    floor: floor,
    surface1: surface1,
    surface2: surface2,
    surface3: surface3,
    fg1: ink,
    fg2: inkMuted,
    fg3: inkSubtle,
    fg4: inkFaint,
    // Hairlines stay a single step off their surface, so a border reads as a
    // soft edge rather than a drawn line.
    border: const Color(0xFF262626),
    border2: const Color(0xFF333333),
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
    diffGutter: const Color(0xFF383838),
  );
}

// The only client theme.
final _amoled = _dark(
  name: 'amoled',
  label: 'Dark',
  accent: const Color(0xFF4E88FF), // vibrant blue
  ink: const Color(0xFFFFFFFF), // white — emphasis only
  inkMuted: const Color(0xFFC1C1C1), // DEFAULT body text
  inkSubtle: const Color(0xFF8F8F8F), // muted
  inkFaint: const Color(0xFF5F5F5F), // placeholder / disabled
  success: const Color(0xFF3EAF3F), // online green
  danger: const Color(0xFFEF4444), // red danger
  warn: const Color(0xFFAF8D3E), // amber
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
  static Color get floor => currentTheme.floor;
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

/// Reading/content surfaces (chat, editor, file viewer, diff). Always the dark
/// `canvas`, so the content the user is actually reading recedes and the grey
/// chrome around it carries the structure.
Color get readingBg => AppColors.canvas;

// ---------------------------------------------------------------------------
// Radius — small and precise. Large radii read consumer/toy; a developer tool
// wants edges that feel engineered.
// ---------------------------------------------------------------------------

class R {
  static const card = 8.0; // rows, cards, inputs — the dominant radius
  static const md = 8.0;
  static const sm = 8.0;
  static const xs = 4.0; // small inline marks
  static const chip = 6.0;
  static const sheetTop = 10.0; // window + section corners
}

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

  /// Phone reading body stays at 16px for physical legibility; chrome follows
  /// desktop's 20/16/13/11 hierarchy and the same Geist/Inter family split.
  static const pageTitle = 20.0;
  static const sectionTitle = 16.0;

  /// 14, not 13: at 13px a phone row title sat uncomfortably close to the 11px
  /// meta beside it, so the hierarchy read as "two smalls" rather than
  /// "title + detail". These two move as a pair — widening only the title would
  /// have grown the gap between them in the same row.
  static const rowTitle = 14.0;
  static const body = 16.0;
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
// Typography — Geist for UI, JetBrains Mono for code.
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

/// Optical tracking. The reference sits slightly tight at every size
/// (-0.05px at 12–13px, -0.3px at 20px).
double _tracking(double size) {
  if (size >= 32) return -0.6;
  if (size >= 24) return -0.4;
  if (size >= 17) return -0.3;
  if (size >= 14) return -0.1;
  return -0.05;
}

TextStyle sans(double size,
        {FontWeight weight = W.body,
        double? height,
        double? spacing,
        Color? color}) =>
    GoogleFonts.geist(
      fontSize: size,
      fontWeight: weight,
      height: height ?? 1.33,
      letterSpacing: spacing ?? _tracking(size),
      color: color ?? AppColors.fg2,
    );

TextStyle display(double size,
        {FontWeight weight = W.title, Color? color, double? height}) =>
    GoogleFonts.geist(
      fontSize: size,
      fontWeight: weight,
      height: height ?? 1.15,
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
    textTheme: _weightedTextTheme(GoogleFonts.interTextTheme(base.textTheme)
        .apply(bodyColor: c.fg1, displayColor: c.fg1)),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 12),
  );
}

/// Material widgets inherit their weights from here, so this is the single
/// place that decides what reads as "heavy". Body copy stays at 400 and only
/// titles/labels step up to 500 — no 600+ anywhere in the inherited theme.
TextTheme _weightedTextTheme(TextTheme t) {
  TextStyle? w(TextStyle? s, FontWeight weight) =>
      s?.copyWith(fontWeight: weight);
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
    case 'archive':
      return HugeIcons.strokeRoundedArchive01;
    case 'plus':
    case 'add':
      return HugeIcons.strokeRoundedAdd01;
    case 'x':
      return HugeIcons.strokeRoundedCancel01;
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
      return HugeIcons.strokeRoundedRefresh;
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
    case 'file':
      return HugeIcons.strokeRoundedFile01;
    case 'git-branch':
      return HugeIcons.strokeRoundedGitBranch;
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
    case 'rotate':
      return HugeIcons.strokeRoundedRotate01;
    case 'globe':
      return HugeIcons.strokeRoundedGlobal;
    case 'map':
      return HugeIcons.strokeRoundedMaps;
    case 'list':
      return HugeIcons.strokeRoundedMenuSquare;
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

/// Optical ink correction for a glyph that over- or under-fills its box.
///
/// Glyphs are NOT drawn to a common fill. Measured in the app's own header at
/// the 16px spec: `plus` inks ~10px while `refresh` inks ~14px — so a circular
/// arrow reads ~40% heavier standing beside a plus, though both are nominally
/// the same size. That is a property of the GLYPH, not of the panel it lands
/// in, so the correction lives beside `hugeIconFor` and is applied by `AppIcon`
/// for every call site on both platforms. A per-call parameter is exactly how
/// one header drifts from the next.
///
/// Layout is unaffected: `AppIcon` keeps its nominal `SizedBox.square`, so only
/// the INK scales.
double glyphInkScale(String name) => switch (name) {
      // 10/14 — brings the circular arrow down to the plus's ink.
      'refresh' => 0.72,
      _ => 1.0,
    };
