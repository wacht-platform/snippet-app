import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An attachment that was ready to send: uploaded to the daemon, or pasted
/// text carried inline.
class DraftAttachment {
  final String name;
  final bool isImage;
  final bool isAudio;
  final String? localPath;
  final String? remotePath;
  final String? pastedText;
  const DraftAttachment({
    required this.name,
    this.isImage = false,
    this.isAudio = false,
    this.localPath,
    this.remotePath,
    this.pastedText,
  });

  factory DraftAttachment.fromJson(Map<String, dynamic> j) => DraftAttachment(
        name: j['name'] as String? ?? '',
        isImage: j['image'] == true,
        isAudio: j['audio'] == true,
        localPath: j['local'] as String?,
        remotePath: j['remote'] as String?,
        pastedText: j['pasted'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (isImage) 'image': true,
        if (isAudio) 'audio': true,
        if (localPath != null) 'local': localPath,
        if (remotePath != null) 'remote': remotePath,
        if (pastedText != null) 'pasted': pastedText,
      };

  /// Identity for change detection.
  String get id => remotePath ?? 'pasted:${pastedText.hashCode}:$name';
}

/// What a composer held but had not sent.
class Draft {
  final String text;
  final List<DraftAttachment> attachments;
  const Draft({this.text = '', this.attachments = const []});

  bool get isEmpty => text.trim().isEmpty && attachments.isEmpty;
}

/// Unsent composer text and attachments, per session, kept on the device.
///
/// Switching sessions (or the app restarting) used to throw away whatever was
/// typed or attached. Drafts live in memory for synchronous reads — the chat
/// list marks the sessions that have one — and are written through to shared
/// preferences.
class Drafts extends ChangeNotifier {
  Drafts._();
  static final Drafts instance = Drafts._();

  static const _prefix = 'draft:';
  final Map<String, Draft> _drafts = {};
  final Map<String, Timer> _pending = {};

  /// A session's identity across machines: the daemon it lives on and its id.
  static String keyFor(String baseUrl, String sessionId) =>
      '$baseUrl|$sessionId';

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        if (!k.startsWith(_prefix)) continue;
        final d = _decode(prefs.getString(k));
        if (d != null && !d.isEmpty) _drafts[k.substring(_prefix.length)] = d;
      }
      notifyListeners();
    } catch (_) {}
  }

  static Draft? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return Draft(
        text: j['text'] as String? ?? '',
        attachments: [
          for (final a in (j['attachments'] as List? ?? const []))
            DraftAttachment.fromJson(a as Map<String, dynamic>),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  Draft? of(String key) => _drafts[key];

  bool has(String key) => !(_drafts[key]?.isEmpty ?? true);

  /// Record [key]'s draft; an empty one clears it. The disk write is debounced
  /// unless [now].
  void save(String key, Draft draft, {bool now = false}) {
    final had = has(key);
    if (draft.isEmpty) {
      _drafts.remove(key);
    } else {
      _drafts[key] = draft;
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

  /// Add an attachment to [key]'s draft — an upload that finished after its
  /// composer had moved to another session.
  void addAttachment(String key, DraftAttachment a) {
    final d = _drafts[key] ?? const Draft();
    save(key, Draft(text: d.text, attachments: [...d.attachments, a]),
        now: true);
  }

  Future<void> _write(String key) async {
    _pending.remove(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      final d = _drafts[key];
      if (d == null) {
        await prefs.remove('$_prefix$key');
      } else {
        await prefs.setString(
            '$_prefix$key',
            jsonEncode({
              'text': d.text,
              'attachments': [for (final a in d.attachments) a.toJson()],
            }));
      }
    } catch (_) {}
  }
}
