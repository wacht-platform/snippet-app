import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/inference_profiles.dart';
import 'package:snippet/screens/vault.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

class _FakeDaemon extends DaemonClient {
  _FakeDaemon() : super('https://daemon.invalid', 'test-token');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  Map<String, dynamic> config = {};
  List<String> secrets = [];

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson(config);

  @override
  Future<List<String>> vaultList() async => secrets;
}

void main() {
  testWidgets('profile card has its provider logo and does not show token or session count',
      (tester) async {
    final client = _FakeDaemon()
      ..config = {
        'profiles': [
          {
            'name': 'gpt-4o',
            'provider': 'openai',
            'model': 'gpt-4o',
            'active': true,
            'usable': true,
          }
        ],
      };

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: InferenceProfilesScreen(client: client, embedded: true),
      ),
    ));

    await tester.pumpAndSettle();

    // The name and model are shown
    expect(find.text('gpt-4o'), findsOneWidget);
    expect(find.text('openai · gpt-4o'), findsOneWidget);

    // No session count and no token count
    expect(find.textContaining('session'), findsNothing);
    expect(find.textContaining('tok'), findsNothing);

    final logos = tester.widgetList<ProviderLogo>(find.byType(ProviderLogo));
    expect(logos.any((l) => l.provider == 'openai'), isTrue);
    final icons = tester.widgetList<AppIcon>(find.byType(AppIcon));
    expect(icons.any((icon) => icon.name == 'cpu'), isFalse);
  });

  testWidgets(
      'rebuilding parent does not cause embedded InferenceProfilesScreen to flicker',
      (tester) async {
    final client = _FakeDaemon()
      ..config = {
        'profiles': [
          {
            'name': 'claude-3-5-sonnet',
            'provider': 'anthropic',
            'model': 'claude-3-5-sonnet-20241022',
            'active': true,
            'usable': true,
          }
        ],
      };

    final rebuildNotifier = ValueNotifier<int>(0);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: rebuildNotifier,
          builder: (context, value, _) {
            return Column(
              children: [
                Text('Rebuild count: $value'),
                Expanded(
                  child: InferenceProfilesScreen(
                      client: client, embedded: true),
                ),
              ],
            );
          },
        ),
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('claude-3-5-sonnet'), findsOneWidget);

    // Trigger parent rebuild
    rebuildNotifier.value++;
    // Pump a single frame without waiting for any microtasks/futures.
    await tester.pump();

    // It should STILL be rendering the profile, never disappearing or shrinking
    expect(find.text('claude-3-5-sonnet'), findsOneWidget);
  });

  testWidgets('vault secret does not render masked dots placeholder',
      (tester) async {
    final client = _FakeDaemon()..secrets = ['API_SECRET_KEY'];

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: VaultScreen(client: client, embedded: true),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.text('API_SECRET_KEY'), findsOneWidget);
    expect(find.text('••••••'), findsNothing);
    expect(find.textContaining('••'), findsNothing);
  });
}
