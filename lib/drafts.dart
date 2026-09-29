import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unsent composer text, per session, kept on the device.
///
/// Switching sessions (or the app restarting) used to throw away whatever was
/// typed. Drafts live in memory for synchronous reads — the chat list marks the
/// sessions that have one — and are written through to shared preferences.
class Drafts extends ChangeNotifier {
  Drafts._();
  static final Drafts instance = Drafts._();

  static const _prefix = 'draft:';
  final Map<String, String> _drafts = {};
  final Map<String, Timer> _pending = {};

  /// A session's identity across machines: the daemon it lives on and its id.
  static String keyFor(String baseUrl, String sessionId) =>
      '$baseUrl|$sessionId';

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        if (!k.startsWith(_prefix)) continue;
        final v = prefs.getString(k);
        if (v != null && v.trim().isNotEmpty) {
          _drafts[k.substring(_prefix.length)] = v;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  String? of(String key) => _drafts[key];

  bool has(String key) => _drafts[key]?.trim().isNotEmpty ?? false;

  /// Record [text] as [key]'s draft; empty clears it. The disk write is
  /// debounced unless [now].
  void save(String key, String text, {bool now = false}) {
    final had = has(key);
    if (text.trim().isEmpty) {
      _drafts.remove(key);
    } else {
      _drafts[key] = text;
    }
    if (had != has(key)) notifyListeners();
    _pending.remove(key)?.cancel();
    if (now) {
      unawaited(_write(key));
    } else {
      _pending[key] =
          Timer(const Duration(milliseconds: 400), () => _write(key));
    }
  }

  Future<void> _write(String key) async {
    _pending.remove(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = _drafts[key];
      if (v == null) {
        await prefs.remove('$_prefix$key');
      } else {
        await prefs.setString('$_prefix$key', v);
      }
    } catch (_) {}
  }
}
