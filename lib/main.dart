import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'notifications.dart';
import 'platform.dart';
import 'screens/adaptive_home.dart';
import 'theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Widget _buildErrorWidget(FlutterErrorDetails details) {
  return Material(
    color: AppColors.bg,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 28, color: AppColors.danger),
            const SizedBox(height: 12),
            Text('This panel could not be displayed',
                textAlign: TextAlign.center,
                style: sans(15, weight: FontWeight.w600, color: AppColors.fg1)),
            const SizedBox(height: 6),
            Text('Close it and try again.',
                textAlign: TextAlign.center,
                style: sans(12, color: AppColors.fg3)),
          ],
        ),
      ),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep a build failure inside a tool panel visible and dismissible instead of
  // leaving only the modal barrier over the previous screen.
  ErrorWidget.builder = _buildErrorWidget;
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
