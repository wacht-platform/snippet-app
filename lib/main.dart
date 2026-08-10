import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'notifications.dart';
import 'platform.dart';
import 'screens/adaptive_home.dart';
import 'theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Theme and notification setup must never prevent the first frame. A native
  // plugin can be unavailable or permission-gated on a new desktop install;
  // the app remains usable and the feature can be retried from Settings.
  try {
    await ThemeManager.instance.init();
  } catch (_) {}
  if (kCanNotify) {
    try {
      await initNotifications();
      await resumeWatchingIfEnabled();
    } catch (_) {}
  }
  runApp(const SnippetApp());
}

class SnippetApp extends StatefulWidget {
  const SnippetApp({super.key});
  @override
  State<SnippetApp> createState() => _SnippetAppState();
}

class _SnippetAppState extends State<SnippetApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ThemeManager.instance.addListener(_onThemeChange);
    if (kCanNotify) reportForeground(true);
  }

  @override
  void dispose() {
    ThemeManager.instance.removeListener(_onThemeChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onThemeChange() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kCanNotify) return;
    final fg = state == AppLifecycleState.resumed;
    reportForeground(fg);
    if (!fg) reportOpenSession('');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'snippet',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: kMobile
          ? const WithForegroundTask(child: AdaptiveHome())
          : const AdaptiveHome(),
    );
  }
}
