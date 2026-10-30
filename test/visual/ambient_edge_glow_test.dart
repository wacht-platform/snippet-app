import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/ambient/ambient_edge_glow.dart';
import 'package:snippet/theme.dart';

import 'golden.dart';

void main() {
  Widget testFrame({
    required Widget child,
    Size size = const Size(390, 844),
    bool disableAnimations = false,
  }) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: disableAnimations,
        ),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: child,
        ),
      ),
    );
  }

  testWidgets('AmbientEdgeGlow renders child and does not block pointer events',
      (tester) async {
    var buttonTapped = false;

    await tester.pumpWidget(
      testFrame(
        child: AmbientEdgeGlow(
          overrideActive: true,
          overrideSpeaking: false,
          overrideAssistantSpeaking: false,
          child: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => buttonTapped = true,
                child: const Text('Tap Me'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Tap Me'), findsOneWidget);

    // Tap button to verify IgnorePointer lets taps pass through
    await tester.tap(find.text('Tap Me'));
    expect(buttonTapped, isTrue);
  });

  testWidgets('AmbientEdgeGlow hides overlay when inactive', (tester) async {
    await tester.pumpWidget(
      testFrame(
        child: const AmbientEdgeGlow(
          overrideActive: false,
          child: Scaffold(
            body: Center(child: Text('Idle Content')),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('AmbientEdgeGlow renders CustomPaint when active', (tester) async {
    await tester.pumpWidget(
      testFrame(
        child: const AmbientEdgeGlow(
          overrideActive: true,
          overrideAssistantSpeaking: false,
          child: Scaffold(
            body: Center(child: Text('Active Content')),
          ),
        ),
      ),
    );

    // Pump a frame to initiate fade in
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('AmbientEdgeGlow supports reduced motion gracefully',
      (tester) async {
    await tester.pumpWidget(
      testFrame(
        disableAnimations: true,
        child: const AmbientEdgeGlow(
          overrideActive: true,
          overrideAssistantSpeaking: false,
          child: Scaffold(
            body: Center(child: Text('Reduced Motion')),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('AmbientEdgeGlow mobile and desktop golden captures',
      (tester) async {
    // 1. Mobile Phone - Listening
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      testFrame(
        size: const Size(390, 844),
        child: AmbientEdgeGlow(
          overrideActive: true,
          overrideSpeaking: false,
          overrideAssistantSpeaking: false,
          child: Scaffold(
            backgroundColor: AppColors.bg,
            appBar: AppBar(
              title: const Text('Snippet Mobile'),
              backgroundColor: AppColors.surface1,
            ),
            body: const Center(
              child: Text('Ambient Listening Active'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await expectGolden(
        tester, find.byType(MaterialApp), 'goldens/ambient_edge_glow_mobile_listening.png');

    // 2. Mobile Phone - Snippet Speaking
    await tester.pumpWidget(
      testFrame(
        size: const Size(390, 844),
        child: AmbientEdgeGlow(
          overrideActive: true,
          overrideSpeaking: false,
          overrideAssistantSpeaking: true,
          child: Scaffold(
            backgroundColor: AppColors.bg,
            appBar: AppBar(
              title: const Text('Snippet Mobile'),
              backgroundColor: AppColors.surface1,
            ),
            body: const Center(
              child: Text('Snippet Speaking Pulse'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await expectGolden(
        tester, find.byType(MaterialApp), 'goldens/ambient_edge_glow_mobile_speaking.png');

    // 3. Desktop Mac Window - Listening
    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.pumpWidget(
      testFrame(
        size: const Size(800, 600),
        child: AmbientEdgeGlow(
          overrideActive: true,
          overrideSpeaking: false,
          overrideAssistantSpeaking: false,
          child: Scaffold(
            backgroundColor: AppColors.bg,
            appBar: AppBar(
              title: const Text('Snippet Desktop'),
              backgroundColor: AppColors.surface1,
            ),
            body: const Center(
              child: Text('Mac Desktop Ambient Glow'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await expectGolden(
        tester, find.byType(MaterialApp), 'goldens/ambient_edge_glow_desktop_listening.png');

    // 4. Desktop Mac Window - Snippet Speaking
    await tester.pumpWidget(
      testFrame(
        size: const Size(800, 600),
        child: AmbientEdgeGlow(
          overrideActive: true,
          overrideSpeaking: false,
          overrideAssistantSpeaking: true,
          child: Scaffold(
            backgroundColor: AppColors.bg,
            appBar: AppBar(
              title: const Text('Snippet Desktop'),
              backgroundColor: AppColors.surface1,
            ),
            body: const Center(
              child: Text('Mac Desktop Speaking Pulse'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await expectGolden(
        tester, find.byType(MaterialApp), 'goldens/ambient_edge_glow_desktop_speaking.png');

    await tester.binding.setSurfaceSize(null);
  });
}
