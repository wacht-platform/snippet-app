import 'dart:convert';

class ApprovalSummary {
  const ApprovalSummary({
    required this.command,
    this.lane,
    this.customTool,
    this.newCustomTool = false,
    this.secrets = const [],
  });

  final String command;
  final String? lane;
  final String? customTool;
  final bool newCustomTool;
  final List<String> secrets;

  static final _vaultPrefix = RegExp(
      r'^\s*⚠?\s*uses vault secret\(s\) \[([^\]]*)\]\s*[—-]\s*',
      dotAll: true);
  static final _lanePrefix = RegExp(r'^lane «(.+?)» · ');
  static final _customTool = RegExp(
      r'^⚠ (new )?custom tool `([^`]+)`(?:, uses vault secret\(s\) \[([^\]]*)\])? — runs: ',
      dotAll: true);

  factory ApprovalSummary.parse(String raw, {String? fullCommand}) {
    var detail = raw.trim();
    final lane = _lanePrefix.firstMatch(detail);
    if (lane != null) detail = detail.substring(lane.end).trim();
    List<String> names(String? value) => (value ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final custom = _customTool.firstMatch(detail);
    final vault = custom == null ? _vaultPrefix.firstMatch(detail) : null;
    if (custom != null) detail = detail.substring(custom.end).trim();
    if (vault != null) detail = detail.substring(vault.end).trim();
    return ApprovalSummary(
      command: fullCommand != null && fullCommand.trim().isNotEmpty
          ? fullCommand.trim()
          : detail,
      lane: lane?.group(1),
      customTool: custom?.group(2),
      newCustomTool: custom?.group(1) != null,
      secrets: custom != null ? names(custom.group(3)) : names(vault?.group(1)),
    );
  }

  /// The command without `NAME="$NAME"` for the secrets already named above it.
  String get shownCommand {
    var text = command;
    for (final _ in secrets) {
      for (final name in secrets) {
        text = text.replaceFirst(RegExp('^$name="?\\\$$name"?\\s+'), '');
      }
    }
    return text;
  }

  String headline(String tool) {
    final String base;
    if (customTool != null) {
      base = '${newCustomTool ? 'Run new tool' : 'Run tool'} $customTool';
    } else if (secrets.isNotEmpty) {
      base = 'Use ${secrets.join(', ')}';
    } else {
      base = switch (tool) {
        'bash' => 'Run a command',
        'change_files' => 'Change files',
        '' => 'Allow an action',
        _ => 'Allow $tool',
      };
    }
    return lane == null ? base : '$base in lane $lane';
  }
}

ApprovalSummary? approvalOf(Object? attention) {
  if (attention is! Map || attention['type'] != 'approval') return null;
  final text = '${attention['text'] ?? ''}'.trim();
  if (text.isEmpty) return null;
  final command = attention['command'];
  return ApprovalSummary.parse(text,
      fullCommand: command is String ? command : null);
}

/// The real text of the call an approval is about, with its line breaks. The
/// summary is flattened and cut, so it is only the fallback. The call must match
/// it: a lane's request or a parallel call has a different call before it.
String? fullApprovalCommand(List<Map<String, dynamic>> events,
    Map<String, dynamic> request, String summary) {
  final i = events.indexOf(request);
  if (i < 1) return null;
  final call = events[i - 1];
  if (call['kind'] != 'tool_call' ||
      call['tool_name'] != request['tool_name']) {
    return null;
  }
  final args = call['arguments'];
  if (args is! Map) return null;
  final String text;
  final String flat;
  if (args['command'] is String) {
    text = args['command'] as String;
    flat = text;
  } else if (args['changes'] is List) {
    final lines = [
      for (final c in args['changes'] as List)
        if (c is Map) '${c['action'] ?? 'change'} ${c['path'] ?? '?'}'
    ];
    text = lines.join('\n');
    flat = lines.join(', ');
  } else {
    return null;
  }
  final prefix = flat.trim().split(RegExp(r'\s+')).join(' ');
  final head = prefix.length > 40 ? prefix.substring(0, 40) : prefix;
  return summary.contains(head) ? text : null;
}

/// One line for a collapsed notification, the notch and the toast.
String? approvalPreview(Object? attention) {
  final approval = approvalOf(attention);
  if (approval == null) return null;
  final map = attention as Map;
  final label = '${map['label'] ?? ''}'.trim();
  final detail = label.isNotEmpty
      ? label
      : approval.shownCommand.split(RegExp(r'\s+')).join(' ');
  final head = approval.headline('${map['tool'] ?? ''}');
  return detail.isEmpty ? head : '$head: $detail';
}

String _escape(String value) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(value);

String approvalHtml(Object? attention) {
  final map = attention as Map;
  final approval = approvalOf(map)!;
  final label = '${map['label'] ?? ''}'.trim();
  return [
    '<b>${_escape(approval.headline('${map['tool'] ?? ''}'))}</b>',
    if (label.isNotEmpty) _escape(label),
    if (approval.shownCommand.isNotEmpty) _codeHtml(approval.shownCommand),
  ].join('<br>');
}

String _codeHtml(String code) {
  final lines = code.split('\n');
  final shown = lines.take(8).map((l) => '<tt>${_escape(l)}</tt>').join('<br>');
  return lines.length > 8 ? '$shown<br>…' : shown;
}

String questionHtml(Object? attention) {
  final map = attention as Map;
  final choices = answerChoices(map);
  final more = map['more'] is int ? map['more'] as int : 0;
  return [
    _escape('${map['text'] ?? ''}'.trim()),
    if (choices.length > maxChoiceButtons)
      for (final (label, _) in choices) '• ${_escape(label)}',
    if (more > 0)
      '<i>+$more more question${more == 1 ? '' : 's'} in the chat</i>',
  ].join('<br>');
}

/// Android shows three action buttons at most.
const maxChoiceButtons = 3;

List<(String, String)> answerChoices(Object? attention) {
  final raw = attention is Map ? attention['choices'] : null;
  if (raw is! List) return const [];
  return [
    for (final c in raw)
      if (c is Map && '${c['label'] ?? ''}'.isNotEmpty)
        ('${c['label']}', '${c['value'] ?? c['label']}')
  ];
}

String answerText(Object? attention, String text) {
  final map = attention is Map ? attention : const {};
  final question = '${map['text'] ?? ''}'.trim();
  return question.isEmpty || map['more'] is int ? text : '$question\n→ $text';
}

String choiceAnswer((String, String) choice) =>
    choice.$1 == choice.$2 ? choice.$1 : '${choice.$1} (${choice.$2})';

final _fenceLine = RegExp(r'^\s*```');
final _headingLine = RegExp(r'^\s{0,3}#{1,6}\s+(.*)$');
final _bulletLine = RegExp(r'^\s*(?:[-*+])\s+(.*)$');
final _quoteLine = RegExp(r'^\s*>\s?(.*)$');
final _inlineCode = RegExp(r'`([^`]+)`');
final _inlineBold = RegExp(r'\*\*(.+?)\*\*|__(.+?)__');
final _inlineLink = RegExp(r'!?\[([^\]]*)\]\([^)]*\)');

String _inline(String line) {
  final code = <String>[];
  final masked = line.replaceAllMapped(_inlineCode, (m) {
    code.add(m[1]!);
    return '\u0000${code.length - 1}\u0000';
  });
  return _escape(masked.replaceAllMapped(_inlineLink, (m) => m[1] ?? ''))
      .replaceAllMapped(_inlineBold, (m) => '<b>${m[1] ?? m[2]}</b>')
      .replaceAllMapped(RegExp('\u0000(\\d+)\u0000'),
          (m) => '<tt>${_escape(code[int.parse(m[1]!)])}</tt>');
}

/// The markup Android's `Html.fromHtml` keeps: bold, italic, monospace and breaks.
String markdownToNotificationHtml(String markdown) {
  final out = <String>[];
  var inFence = false;
  for (final raw in const LineSplitter().convert(markdown)) {
    if (_fenceLine.hasMatch(raw)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      out.add('<tt>${_escape(raw)}</tt>');
      continue;
    }
    final line = raw.trim();
    if (line.isEmpty) continue;
    final heading = _headingLine.firstMatch(raw);
    final bullet = _bulletLine.firstMatch(raw);
    final quote = _quoteLine.firstMatch(raw);
    if (heading != null) {
      out.add('<b>${_inline(heading[1]!)}</b>');
    } else if (bullet != null) {
      out.add('• ${_inline(bullet[1]!)}');
    } else if (quote != null) {
      out.add('<i>${_inline(quote[1]!)}</i>');
    } else {
      out.add(_inline(line));
    }
  }
  return out.join('<br>');
}

/// One event reaches the notch from several paths, and a stopped session's text
/// repeats what the live chat already showed. The first wins unless a later copy
/// carries the buttons.
class NotificationDedupe {
  NotificationDedupe({this.window = const Duration(seconds: 60)});

  final Duration window;
  final _seen = <String, ({DateTime at, bool actionable})>{};

  static String _normal(String text) {
    final words =
        text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return words.length > 120 ? words.substring(0, 120) : words;
  }

  bool admit({
    required String id,
    required String session,
    required String text,
    bool actionable = false,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    _seen.removeWhere((_, v) => at.difference(v.at) > window);
    final normal = _normal(text);
    final keys = [
      if (id.isNotEmpty) 'id:$id',
      if (normal.isNotEmpty) 'text:$session:$normal',
    ];
    final known =
        keys.map((k) => _seen[k]).whereType<({DateTime at, bool actionable})>();
    final admitted =
        known.isEmpty || (actionable && known.every((v) => !v.actionable));
    if (admitted) {
      for (final k in keys) {
        _seen[k] = (at: at, actionable: actionable);
      }
    }
    return admitted;
  }
}

const _toastStates = {'waiting', 'idle', 'done', 'error'};

/// A session's newer state replaces its older one instead of stacking beside it.
bool toastSuperseded(Map<String, dynamic> older, Map<String, dynamic> newer) =>
    _toastStates.contains(older['kind']) &&
    _toastStates.contains(newer['kind']) &&
    '${older['session'] ?? ''}'.isNotEmpty &&
    older['session'] == newer['session'] &&
    older['url'] == newer['url'];
