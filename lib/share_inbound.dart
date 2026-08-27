import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Inbound share / "Ask Snippet" payload from Android.
class SharedInbound {
  final String type; // text | image | file
  final String text;
  final List<String> paths;
  final List<String> names;

  const SharedInbound({
    required this.type,
    this.text = '',
    this.paths = const [],
    this.names = const [],
  });

  bool get isEmpty => text.trim().isEmpty && paths.isEmpty;

  factory SharedInbound.fromMap(Map<dynamic, dynamic> raw) {
    final paths = ((raw['paths'] as List?) ?? const [])
        .map((e) => '$e')
        .where((e) => e.isNotEmpty)
        .toList();
    final names = ((raw['names'] as List?) ?? const [])
        .map((e) => '$e')
        .toList();
    return SharedInbound(
      type: raw['type'] as String? ?? 'text',
      text: (raw['text'] as String?) ?? '',
      paths: paths,
      names: names.length == paths.length
          ? names
          : List<String>.generate(
              paths.length,
              (i) => i < names.length && names[i].isNotEmpty
                  ? names[i]
                  : paths[i].split('/').last,
            ),
    );
  }
}

const _channel = MethodChannel('snippet/share');

/// Listen for Android share-sheet / PROCESS_TEXT payloads.
class ShareInbound {
  static bool _bound = false;
  static void Function(SharedInbound share)? _onShare;

  static void listen(void Function(SharedInbound share) onShare) {
    _onShare = onShare;
    if (!_bound) {
      _bound = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'shareReceived') return;
        final args = call.arguments;
        if (args is Map) {
          final share = SharedInbound.fromMap(args);
          if (!share.isEmpty) _onShare?.call(share);
        }
      });
    }
    takePending();
  }

  static Future<void> takePending() async {
    if (kIsWeb) return;
    try {
      final raw = await _channel.invokeMethod<dynamic>('takePending');
      if (raw is Map) {
        final share = SharedInbound.fromMap(raw);
        if (!share.isEmpty) _onShare?.call(share);
      }
    } catch (_) {}
  }

  static void dispose() {
    _onShare = null;
  }
}
