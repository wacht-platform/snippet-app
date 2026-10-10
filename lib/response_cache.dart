import 'package:shared_preferences/shared_preferences.dart';

/// The last good response body for a few small, often-opened reads, kept on
/// disk per machine so a screen can paint what it showed last time while the
/// fresh copy loads.
class ResponseCache {
  ResponseCache._();
  static final ResponseCache instance = ResponseCache._();

  static const _prefix = 'rc:';
  final Map<String, String> _bodies = {};
  SharedPreferences? _prefs;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_prefix)) continue;
        final body = prefs.getString(key);
        if (body != null) _bodies[key.substring(_prefix.length)] = body;
      }
    } catch (_) {}
  }

  String? get(String key) => _bodies[key];

  void put(String key, String body) {
    if (_bodies[key] == body) return;
    _bodies[key] = body;
    _prefs?.setString('$_prefix$key', body);
  }
}
