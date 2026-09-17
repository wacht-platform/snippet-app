import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:snippet/theme.dart';

void main() {
  testWidgets('mobile shell starts on Agents and tabs switch to the correct destinations',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});

      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(390, 844) * 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const DesktopShell(),
      ));

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // 1. Initial destination is Agents (index 0)
      expect(find.text('Add a machine to see its agents.'), findsOneWidget);
      expect(find.text('Add a machine to begin.'), findsNothing);

      // 2. Tap Chats tab (index 1)
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();

      expect(find.text('Add a machine to begin.'), findsOneWidget);
      expect(find.text('Add a machine to see its agents.'), findsNothing);

      // 3. Tap Agents tab again (index 0)
      await tester.tap(find.text('Agents'));
      await tester.pumpAndSettle();

      expect(find.text('Add a machine to see its agents.'), findsOneWidget);
      expect(find.text('Add a machine to begin.'), findsNothing);

      // 4. Tap Settings tab (index 2)
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Add a machine to configure it.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
