import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';
import 'golden.dart';

/// Renders the shared widget set to a PNG, and pins the behaviour of the two
/// shared-layer rules that are easiest to regress.
///
/// This app has no runnable Flutter target on this machine, so `flutter test`
/// rendering offscreen is the only way to SEE it. Keep this gallery honest: it
/// is the one place a visual change can be reviewed before it ships.
/// The two densities the app ships. `flutter_test` defaults to `android`, so
/// without the override the gallery renders ONLY the mobile branch — every
/// `kMobile` ternary (Btn 44 vs 34, PillBtn 48 vs 36, AppField, IconBtn's
/// target floor) would go unseen on desktop.
const List<(String, TargetPlatform)> _densities = [
  ('mobile', TargetPlatform.android),
  ('desktop', TargetPlatform.macOS),
];

void main() {
  for (final (density, platform) in _densities) {
    testWidgets('shared widget gallery ($density)', (tester) async {
    // Set INSIDE the body, and cleared in `finally`: the binding checks debug
    // vars before `tearDown`, so a leak either fails this test or the next one.
    debugDefaultTargetPlatformOverride = platform;
    try {
    // physicalSize is PHYSICAL pixels: at dpr 2.0 a 1400px view is only 700
    // LOGICAL, which silently clips a desktop-width gallery. Scale the logical
    // size we actually want.
    const logical = Size(760, 1500);
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = logical * 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('CARDS'),
              const SizedBox(height: 10),
              SizedBox(
                width: 320,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Card title',
                          style:
                              sans(14, weight: W.label, color: AppColors.fg1)),
                      const SizedBox(height: 4),
                      Text('Secondary detail line',
                          style: sans(12, color: AppColors.fg3)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const SectionLabel('BUTTONS'),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                Btn('Primary', onTap: () {}),
                Btn('Secondary', variant: BtnVariant.secondary, onTap: () {}),
                Btn('Surface', variant: BtnVariant.surface, onTap: () {}),
                Btn('Outline', variant: BtnVariant.outline, onTap: () {}),
                Btn('Ghost', variant: BtnVariant.ghost, onTap: () {}),
                Btn('Danger', variant: BtnVariant.danger, onTap: () {}),
                Btn('Disabled', disabled: true, onTap: () {}),
              ]),
              const SizedBox(height: 20),
              const SectionLabel('ICONS, PILLS, CHIPS'),
              const SizedBox(height: 10),
              Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconBtn('plus', tooltip: 'Add', onTap: () {}),
                    IconBtn('x',
                        size: 22,
                        iconSize: 12,
                        tooltip: 'Clear',
                        onTap: () {}),
                    IconBtn('check', active: true, tooltip: 'On', onTap: () {}),
                    PillBtn('Pill action', icon: 'check', onTap: () {}),
                    const StatusPill(status: 'running'),
                    const StatusPill(status: 'offline'),
                    const WarnChip(),
                  ]),
              const SizedBox(height: 20),
              const SectionLabel('BUBBLES'),
              const SizedBox(height: 10),
              SizedBox(
                width: 460,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Bubble(mine: true, text: 'A user turn looks like this'),
                    ),
                    SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Bubble(
                          mine: false,
                          text: 'And an assistant turn looks like this.'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SectionLabel('NOTES'),
              const SizedBox(height: 10),
              SizedBox(
                width: 460,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    NoteLine('A quiet note under a tool call.'),
                    NoteLine('A note that failed.', error: true),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SectionLabel('STAT TILES & PROGRESS'),
              const SizedBox(height: 10),
              SizedBox(
                width: 460,
                child: Column(children: const [
                  Row(children: [
                    Expanded(
                        child: StatTile(
                            label: 'Sessions', value: '31', sub: '+2 today')),
                    SizedBox(width: 10),
                    Expanded(
                        child: StatTile(
                            label: 'Tokens', value: '1.2M', accent: true)),
                  ]),
                  SizedBox(height: 12),
                  Progress(pct: 42),
                ]),
              ),
              const SizedBox(height: 20),
              const SectionLabel('FIELDS'),
              const SizedBox(height: 10),
              SizedBox(
                width: 460,
                child: Column(children: [
                  AppField(
                      label: 'Workspace',
                      controller: TextEditingController(text: 'snippet-mobile'),
                      hint: 'Type a path'),
                  const SizedBox(height: 12),
                  AppField(
                      label: 'Disabled',
                      controller: TextEditingController(),
                      hint: 'Cannot edit',
                      enabled: false),
                ]),
              ),
              const SizedBox(height: 20),
              const SectionLabel('ADD CARD & TAPPABLE CARD'),
              const SizedBox(height: 10),
              SizedBox(
                width: 460,
                child: Column(children: [
                  AddCard(label: 'New session', onTap: () {}),
                  const SizedBox(height: 12),
                  AppCard(
                    onTap: () {},
                    child: Row(children: [
                      const AppIcon('folder', size: 16),
                      const SizedBox(width: 10),
                      Text('A tappable card',
                          style: sans(13, color: AppColors.fg1)),
                      const Spacer(),
                      AppIcon('chevron-right', size: 14,
                          color: AppColors.fg4),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              const SectionLabel('SWITCHES & PILLS'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppSwitch(on: true, onChanged: (_) {}),
                  AppSwitch(on: false, onChanged: (_) {}),
                  Pills<String>(
                    items: const [('all', 'All'), ('mine', 'Mine'), ('shared', 'Shared')],
                    selected: 'mine',
                    onSelect: (_) {},
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 460,
                child: AppToggle(
                  on: true,
                  onChanged: (_) {},
                  label: 'Stream responses',
                  sub: 'Show tokens as they arrive',
                ),
              ),
              const SizedBox(height: 20),
              const SectionLabel('STATUS DOTS'),
              const SizedBox(height: 10),
              Row(mainAxisSize: MainAxisSize.min, children: const [
                StatusDot(status: 'online'),
                SizedBox(width: 12),
                StatusDot(status: 'running'),
                SizedBox(width: 12),
                StatusDot(status: 'offline'),
              ]),
            ],
          ),
        ),
      ),
    ));
    // A fixed pump, NOT pumpAndSettle: StatusDot pulses forever, so the tree
    // never goes quiet and pumpAndSettle would time out.
    await tester.pump(const Duration(milliseconds: 120));
    await expectGolden(tester, find.byType(MaterialApp), 'goldens/widget_gallery_$density.png');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    });
  }

  group('IconBtn hit target', () {
    /// The tappable box of an IconBtn. The platform override MUST be cleared
    /// before returning: the binding verifies foundation debug vars at the end
    /// of the test body, before any tearDown runs, and throws if one is left set.
    Future<Size> inkBox(
      WidgetTester tester,
      TargetPlatform platform,
      Widget child,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: child))),
      );
      final size = tester.getSize(find.descendant(
          of: find.byType(IconBtn), matching: find.byType(InkWell)));
      debugDefaultTargetPlatformOverride = null;
      return size;
    }

    testWidgets('a small icon still gets a fingertip-sized target on a phone',
        (tester) async {
      final box = await inkBox(tester, TargetPlatform.android,
          IconBtn('x', size: 22, iconSize: 12, onTap: () {}));
      expect(box.width, M.minTarget);
      expect(box.height, M.minTarget);
    });

    testWidgets('desktop keeps the requested size', (tester) async {
      final box = await inkBox(tester, TargetPlatform.macOS,
          IconBtn('x', size: 22, iconSize: 12, onTap: () {}));
      expect(box.width, 22);
    });

    testWidgets('an explicit size at or above the floor is left alone',
        (tester) async {
      final box = await inkBox(tester, TargetPlatform.android,
          IconBtn('x', size: 48, iconSize: 20, onTap: () {}));
      expect(box.width, 48);
    });

    testWidgets('an inert icon does not grow', (tester) async {
      final box = await inkBox(
          tester, TargetPlatform.android, const IconBtn('x', size: 22));
      expect(box.width, 22);
    });
  });

  group('press feedback', () {
    double scaleOf(WidgetTester tester) {
      final t = tester.widget<AnimatedScale>(find.descendant(
          of: find.byType(Pressable), matching: find.byType(AnimatedScale)));
      return t.scale;
    }

    testWidgets('a press scales the control down, release restores it',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: Btn('Go', onTap: () {}))),
      ));
      expect(scaleOf(tester), 1.0);

      // Hold the pointer down: the press is acknowledged on the way DOWN, not
      // when the tap completes.
      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(Btn)));
      await tester.pump();
      expect(scaleOf(tester), lessThan(1.0));

      await gesture.up();
      await tester.pump();
      expect(scaleOf(tester), 1.0);
    });

    testWidgets('the press duration is the shared token', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: Btn('Go', onTap: () {}))),
      ));
      final t = tester.widget<AnimatedScale>(find.descendant(
          of: find.byType(Pressable), matching: find.byType(AnimatedScale)));
      expect(t.duration, Motion.press);
    });

    testWidgets('a disabled button does not react to a press', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(child: Btn('Go', disabled: true, onTap: () {}))),
      ));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(Btn)));
      await tester.pump();
      expect(scaleOf(tester), 1.0);
      await gesture.up();
    });

    testWidgets('reduced motion keeps the control still under a press',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: Center(child: Btn('Go', onTap: () {}))),
        ),
      ));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(Btn)));
      await tester.pump();
      expect(scaleOf(tester), 1.0,
          reason: 'no travel when motion is reduced');
      await gesture.up();
    });
  });

  group('transcript text', () {
    /// Reads the size on the span that ACTUALLY carries the text.
    ///
    /// Markdown nests the real style on CHILD spans; `RichText.text.style` is only
    /// the inherited root style and reports the theme default instead. Reading the
    /// root made the stylesheet look ignored when it was in fact applying.
    double? leafSize(WidgetTester tester, String needle) {
      for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
        double? found;
        w.text.visitChildren((InlineSpan span) {
          if (span is TextSpan &&
              (span.text ?? '').contains(needle) &&
              span.style?.fontSize != null) {
            found ??= span.style!.fontSize;
          }
          return true;
        });
        if (found != null) return found;
      }
      return null;
    }

    testWidgets('a user bubble and agent prose read at the same size',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Column(children: [
            Bubble(mine: true, text: 'UserSideWord'),
            Bubble(mine: false, text: 'AgentSideWord'),
          ]),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      final user = leafSize(tester, 'UserSideWord');
      final agent = leafSize(tester, 'AgentSideWord');
      expect(user, isNotNull, reason: 'the user span must be found');
      expect(agent, isNotNull, reason: 'the agent span must be found');
      expect(user, agent,
          reason: 'both branches share markdownStyle.p — a bubble that reads '
              'smaller than the prose beside it looks like a bug');
    });
  });

  group('reduced motion', () {
    Widget host({required bool reduce, required Widget child}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Scaffold(body: Center(child: child)),
          ),
        );

    testWidgets('StatusDot holds steady when motion is reduced',
        (tester) async {
      await tester.pumpWidget(host(
          reduce: true, child: const StatusDot(status: 'running')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.hasRunningAnimations, isFalse,
          reason: 'nothing should still be scheduling frames');
    });

    testWidgets('StatusDot keeps breathing when motion is allowed',
        (tester) async {
      await tester.pumpWidget(host(
          reduce: false, child: const StatusDot(status: 'running')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.hasRunningAnimations, isTrue,
          reason: 'the pulse must survive when motion is not reduced');
    });
  });
}
