import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/tool_activity.dart';
import 'package:snippet/tool_sheet.dart';
import 'package:snippet/widgets.dart';

void main() {
  for (final scale in [1.0, 2.0, 3.0]) {
    for (final detail in [false, true]) {
      testWidgets('mobile header scale=$scale detail=$detail', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final batch = ValueNotifier(const ToolBatch([
          ToolStep(tool: 'bash', args: {'command': 'echo hello'}, result: 'hello'),
        ]));
        addTearDown(batch.dispose);
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: Builder(builder: (context) => TextButton(
            onPressed: () => showToolBatchSheet(context, batch: batch,
                initialStep: detail ? 0 : null),
            child: const Text('Open'),
          ))),
        ));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(DraggableScrollableSheet), findsOneWidget);
        final title = find.text(detail ? 'Command' : 'Activity');
        final header = find.ancestor(of: title, matching: find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_SheetHeader',
        ));
        final bounds = tester.getRect(header);
        final sheetBounds = tester.getRect(find.byType(ToolBatchView));
        expect(bounds.top, sheetBounds.top);
        if (scale <= 2) {
          expect(bounds.height, inInclusiveRange(48, 56));
        } else {
          expect(bounds.height, inInclusiveRange(53, 80));
        }
        final titleWidget = tester.widget<Text>(title);
        expect(titleWidget.style!.fontSize, detail ? 13 : 15);
        final close = find.byWidgetPredicate((widget) =>
            widget is IconBtn && widget.tooltip == 'Close');
        final closeBounds = tester.getRect(close);
        expect(closeBounds.width, greaterThanOrEqualTo(44));
        expect(closeBounds.height, greaterThanOrEqualTo(44));
        expect(bounds.contains(closeBounds.topLeft), isTrue);
        expect(closeBounds.bottom, lessThanOrEqualTo(bounds.bottom));
        final handle = find.descendant(of: header, matching: find.byWidgetPredicate(
          (widget) => widget is Container && widget.constraints?.maxWidth == 36
              && widget.constraints?.maxHeight == 4,
        ));
        expect(handle, findsOneWidget);
        expect(tester.getRect(handle).top - bounds.top, 4);
        expect(tester.takeException(), isNull);
        await tester.tapAt(Offset(closeBounds.left + 2, closeBounds.center.dy));
        await tester.pumpAndSettle();
        expect(find.byType(ToolBatchView), findsNothing);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
