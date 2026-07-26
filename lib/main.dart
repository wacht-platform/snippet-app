import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'notifications.dart';
import 'platform.dart';
import 'screens/adaptive_home.dart';
import 'theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Theme: load persisted selection before first frame.
  await ThemeManager.instance.init();
  // Notifications: foreground service on mobile, in-process /events watcher on
  // desktop (macOS/Linux). Tapping one is handled by the shell (it opens the
  // session in-place), so there's no separate full-screen route.
  if (kCanNotify) {
    await initNotifications();
    await resumeWatchingIfEnabled();
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
