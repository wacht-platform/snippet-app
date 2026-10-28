import 'dart:convert';

import 'package:flutter/services.dart';

import 'notifications.dart';
import 'platform.dart';

class MacosNotch {
  MacosNotch._();

  static const MethodChannel _channel = MethodChannel('snippet/macos_notch');
  static bool _initialized = false;

  static void ensureInitialized() {
    if (_initialized || !kMacOS) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationTap') {
        final arg = call.arguments;
        if (arg is String && arg.isNotEmpty) {
          try {
            final payload = jsonDecode(arg) as Map<String, dynamic>;
            onNotifTap?.call(payload);
          } catch (_) {}
        }
      }
    });
  }

  static void updateAmbient({
    required bool active,
    required bool userSpeaking,
    required bool assistantSpeaking,
    required double probability,
  }) {
    if (!kMacOS) return;
    ensureInitialized();
    _channel.invokeMethod<void>('updateAmbient', {
      'active': active,
      'userSpeaking': userSpeaking,
      'assistantSpeaking': assistantSpeaking,
      'probability': probability,
    }).catchError((_) {});
  }

  static void showNotification({
    required String title,
    required String subtitle,
    required String kind,
    required Map<String, dynamic> payload,
  }) {
    if (!kMacOS) return;
    ensureInitialized();
    _channel.invokeMethod<void>('showNotification', {
      'title': title,
      'subtitle': subtitle,
      'kind': kind,
      'payload': jsonEncode(payload),
    }).catchError((_) {});
  }
}
