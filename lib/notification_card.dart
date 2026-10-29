import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mochi.dart';
import 'notification_sync.dart' show notificationSessionKey;
import 'platform.dart';
import 'session_quick_send.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Send { idle, sending, failed }

enum CardAction { none, approval, answer, reply, view }

CardAction cardActionFor(Map<String, dynamic> p) {
  final kind = '${p['kind'] ?? ''}'.split('.').last;
  final attention = p['attention'];
  final attentionType = attention is Map ? '${attention['type']}' : '';
  final dest = p['destination'];
  final destType = dest is Map ? '${dest['type']}' : '';
  final hasSession = '${p['session'] ?? ''}'.isNotEmpty ||
      (dest is Map && '${dest['id'] ?? ''}'.isNotEmpty && destType != 'task');
  if (kind == 'waiting') {
    if (!hasSession) return CardAction.none;
    return attentionType == 'approval' ? CardAction.approval : CardAction.answer;
  }
  if ((kind == 'term' || kind == 'message' || destType == 'conversation') &&
      hasSession) {
    return CardAction.reply;
  }
  if (const {'done', 'completed', 'error', 'failed'}.contains(kind)) {
    return CardAction.view;
  }
  return CardAction.none;
}

final _fence = RegExp(r'```[^\n]*\n?');
final _link = RegExp(r'!?\[([^\]]*)\]\([^)]*\)');
final _heading = RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true);
final _bullet = RegExp(r'^\s*(?:[-*+]|\d+\.)\s+', multiLine: true);
final _quote = RegExp(r'^\s*>\s?', multiLine: true);
final _emph = RegExp(r'(\*\*|__|~~|`)');
final _ws = RegExp(r'\s+');

String plainPreview(String raw) => raw
    .replaceAll(_fence, '')
    .replaceAllMapped(_link, (m) => m[1] ?? '')
    .replaceAll(_heading, '')
    .replaceAll(_bullet, '')
    .replaceAll(_quote, '')
    .replaceAll(_emph, '')
    .split('\n')
    .map((l) => l.replaceAll(_ws, ' ').trim())
    .where((l) => l.isNotEmpty)
    .join(' · ');

String _ago(Object? createdAt) {
  final t = DateTime.tryParse('${createdAt ?? ''}');
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  return '${d.inDays}d';
}

class NotificationMessageCard extends StatefulWidget {
  const NotificationMessageCard({
    super.key,
    required this.payload,
    required this.rest,
    required this.onOpen,
    required this.onDismiss,
    required this.onClearAll,
    required this.onHold,
    required this.onSent,
    this.send = quickSendForPayload,
  });

  final Map<String, dynamic> payload;
  final List<Map<String, dynamic>> rest;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final VoidCallback onClearAll;
  final ValueChanged<bool> onHold;
  final VoidCallback onSent;
  final Future<bool> Function(Map<String, dynamic>, QuickAction) send;

  @override
  State<NotificationMessageCard> createState() =>
      _NotificationMessageCardState();
}

class _NotificationMessageCardState extends State<NotificationMessageCard> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  var _state = _Send.idle;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => widget.onHold(_focus.hasFocus));
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send(QuickAction action) async {
    if (_state == _Send.sending) return;
    setState(() => _state = _Send.sending);
    widget.onHold(true);
    final ok = await widget.send(widget.payload, action);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.lightImpact();
      widget.onSent();
    } else {
      setState(() => _state = _Send.failed);
    }
  }

  void _submitText(CardAction action) {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _send(action == CardAction.answer ? QuickAnswer(t) : QuickReply(t));
  }

  String get _moreLabel {
    final n = widget.rest.length;
    if (n == 0) return '';
    final keys = {
      for (final p in widget.rest)
        if ('${p['session'] ?? ''}'.isNotEmpty)
          notificationSessionKey('${p['url'] ?? ''}', '${p['session']}')
    };
    final chats = keys.length == n ? keys.length : 0;
    return chats > 1 ? '+$n more from $chats chats' : '+$n more';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payload;
    final title = '${p['title'] ?? ''}'.trim();
    final body = plainPreview(
        '${(p['body'] ?? '').toString().trim().isNotEmpty ? p['body'] : p['message'] ?? ''}');
    final action = cardActionFor(p);
    return _card(title, body, action, _ago(p['created_at']),
        _state == _Send.sending);
  }
}

(String, Color, MochiEyes) _mood(Map<String, dynamic> p, CardAction a) =>
    switch ('${p['kind'] ?? ''}'.split('.').last) {
      'waiting' => (
          switch (a) {
            CardAction.approval => 'wants approval',
            CardAction.answer => 'has a question',
            _ => 'needs you',
          },
          AppColors.run,
          MochiEyes.dot
        ),
      'done' || 'completed' => ('done', AppColors.ok, MochiEyes.happy),
      'error' || 'failed' => ('failed', AppColors.danger, MochiEyes.flat),
      'idle' => ('stopped', AppColors.fg3, MochiEyes.flat),
      _ => ('', AppColors.fg3, MochiEyes.dot),
    };

extension on _NotificationMessageCardState {
  Widget _card(
      String title, String body, CardAction action, String ago, bool busy) {
    final mood = _mood(widget.payload, action);
    final actions = switch (action) {
      CardAction.approval => Wrap(spacing: S.s8, runSpacing: S.s8, children: [
          Btn('Approve',
              small: true,
              disabled: busy,
              onTap: () => _send(const QuickApprove())),
          Btn('Deny',
              small: true,
              variant: BtnVariant.secondary,
              disabled: busy,
              onTap: () => _send(const QuickDeny())),
        ]),
      CardAction.answer || CardAction.reply => _ReplyField(
          controller: _text,
          focus: _focus,
          busy: busy,
          hint: action == CardAction.answer ? 'Answer…' : 'Reply…',
          onSubmit: () => _submitText(action),
        ),
      CardAction.view => Btn('Open',
          small: true, variant: BtnVariant.secondary, onTap: widget.onOpen),
      CardAction.none => null,
    };

    final close = SizedBox.square(
      dimension: kMobile ? 44 : 24,
      child: IconButton(
        tooltip: 'Dismiss',
        padding: EdgeInsets.zero,
        style: const ButtonStyle(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        icon: AppIcon('x', size: kMobile ? 14 : 12, color: AppColors.fg4),
        onPressed: widget.onDismiss,
      ),
    );

    final head = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: Row(children: [
          Flexible(
            child: Text(title.isEmpty ? 'Snippet' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(kMobile ? 13 : 12.5,
                    weight: W.label, height: 1.4, color: AppColors.fg2)),
          ),
          if (mood.$1.isNotEmpty) ...[
            const SizedBox(width: S.s6),
            Text(mood.$1,
                maxLines: 1,
                style: sans(kMobile ? 13 : 12.5, height: 1.4, color: mood.$2)),
          ],
        ]),
      ),
      const SizedBox(width: S.s8),
      if (ago.isNotEmpty)
        Text(ago, style: mono(11, color: AppColors.fg4)),
      kMobile ? const SizedBox(width: 30) : close,
    ]);

    final bubble = Container(
      padding: EdgeInsets.fromLTRB(12, kMobile ? 4 : 6, 4, kMobile ? 8 : 10),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          head,
          if (body.isNotEmpty && body != title)
            Padding(
              padding: const EdgeInsets.only(right: S.s8, top: 2),
              child: Text(body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? 14.5 : 13.5,
                      height: kMobile ? 20 / 14.5 : 19 / 13.5,
                      color: AppColors.fg1)),
            ),
          if (actions != null)
            Padding(
              padding: const EdgeInsets.only(right: S.s8, top: S.s8),
              child: actions,
            ),
          if (_state == _Send.failed)
            Padding(
              padding: const EdgeInsets.only(top: S.s6),
              child: GestureDetector(
                onTap: widget.onOpen,
                child: Text("Couldn't send. Open chat",
                    style: sans(12, color: AppColors.danger)),
              ),
            ),
        ],
      ),
    );

    return Material(
      color: AppColors.surface2,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.lineStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
      InkWell(
        onTap: widget.onOpen,
        onLongPress: widget.rest.isEmpty ? null : widget.onClearAll,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: MochiIcon(
                      color: AppColors.accent,
                      size: kMobile ? 38 : 34,
                      eyes: mood.$3),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: CustomPaint(
                      size: const Size(8, 12),
                      painter: _Tail(AppColors.surface3)),
                ),
                Expanded(child: bubble),
              ]),
              if (widget.rest.isNotEmpty)
                Padding(
                  padding:
                      EdgeInsets.only(left: kMobile ? 46 : 40, top: S.s8),
                  child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                    Text(_moreLabel, style: mono(11.5, color: AppColors.fg4)),
                    if (!kMobile) ...[
                    const SizedBox(width: S.s12),
                    InkWell(
                      onTap: widget.onClearAll,
                      borderRadius: BorderRadius.circular(R.xs),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Text('Clear all',
                            style: sans(12,
                                weight: W.label, color: AppColors.accent)),
                      ),
                    ),
                    ],
                  ]),
                ),
            ],
          ),
        ),
      ),
      if (kMobile) Positioned(top: 4, right: 4, child: close),
      ]),
    );
  }
}

class _Tail extends CustomPainter {
  _Tail(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) => canvas.drawPath(
      Path()
        ..moveTo(s.width, 0)
        ..lineTo(0, s.height * .35)
        ..quadraticBezierTo(0, s.height * .5, s.width, s.height)
        ..close(),
      Paint()..color = color);

  @override
  bool shouldRepaint(_Tail old) => old.color != color;
}

class _ReplyField extends StatelessWidget {
  const _ReplyField({
    required this.controller,
    required this.focus,
    required this.busy,
    required this.hint,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final String hint;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final h = kMobile ? 40.0 : 32.0;
    final canSend = !busy && controller.text.trim().isNotEmpty;
    return Container(
      height: h,
      padding: const EdgeInsets.only(left: S.s12),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focus,
            enabled: !busy,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSubmit(),
            style: sans(kMobile ? 14 : 13, color: AppColors.fg1),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: hint,
              hintStyle: sans(kMobile ? 14 : 13, color: AppColors.fg4),
            ),
          ),
        ),
        SizedBox.square(
          dimension: h,
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(11),
                  child: CircularProgressIndicator(strokeWidth: 1.6))
              : IconButton(
                  tooltip: 'Send',
                  padding: EdgeInsets.zero,
                  onPressed: canSend ? onSubmit : null,
                  icon: AppIcon('arrow-up',
                      size: 15,
                      color: canSend ? AppColors.accent : AppColors.fg4),
                ),
        ),
      ]),
    );
  }
}
