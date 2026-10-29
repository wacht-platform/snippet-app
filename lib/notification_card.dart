import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.initiallyExpanded = false,
  });

  final Map<String, dynamic> payload;
  final List<Map<String, dynamic>> rest;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final VoidCallback onClearAll;
  final ValueChanged<bool> onHold;
  final VoidCallback onSent;
  final Future<bool> Function(Map<String, dynamic>, QuickAction) send;
  final bool initiallyExpanded;

  @override
  State<NotificationMessageCard> createState() =>
      _NotificationMessageCardState();
}

class _NotificationMessageCardState extends State<NotificationMessageCard> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  var _state = _Send.idle;
  late var _open = widget.initiallyExpanded;

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
    _send(action == CardAction.answer ? _answer(t) : QuickReply(t));
  }

  QuickAnswer _answer(String text) {
    final a = widget.payload['attention'];
    final q = a is Map ? '${a['text'] ?? ''}'.trim() : '';
    return QuickAnswer(q.isEmpty || _moreQuestions > 0 ? text : '$q\n→ $text');
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

  bool get _expandable => const {
        CardAction.approval,
        CardAction.answer,
        CardAction.reply
      }.contains(cardActionFor(widget.payload));

  void _toggle() {
    if (!_expandable) {
      widget.onOpen();
      return;
    }
    setState(() => _open = !_open);
    widget.onHold(_open || _focus.hasFocus);
  }

  List<(String, String)> get _choices {
    final a = widget.payload['attention'];
    final cs = a is Map ? a['choices'] : null;
    if (cs is! List) return const [];
    return [
      for (final c in cs)
        if (c is Map && '${c['label'] ?? ''}'.isNotEmpty)
          ('${c['label']}', '${c['value'] ?? c['label']}')
    ];
  }

  int get _moreQuestions {
    final a = widget.payload['attention'];
    return a is Map && a['more'] is int ? a['more'] as int : 0;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payload;
    final title = '${p['title'] ?? ''}'.trim();
    final body = plainPreview(
        '${(p['body'] ?? '').toString().trim().isNotEmpty ? p['body'] : p['message'] ?? ''}');
    final action = cardActionFor(p);
    final busy = _state == _Send.sending;
    final mood = _mood(p, action);
    final ago = _ago(p['created_at']);
    final showBody = body.isNotEmpty && body != title;

    final head = Row(children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: mood.$2, shape: BoxShape.circle),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Flexible(
                child: Text(title.isEmpty ? 'Snippet' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 14 : 13.5,
                        weight: W.label, height: 1.35, color: AppColors.fg1)),
              ),
              if (mood.$1.isNotEmpty) ...[
                const SizedBox(width: S.s6),
                Text(mood.$1,
                    maxLines: 1,
                    style: sans(12.5, height: 1.35, color: mood.$2)),
              ],
            ]),
            if (showBody && !_open)
              Text(body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? 13 : 12.5,
                      height: 1.35, color: AppColors.fg3)),
          ],
        ),
      ),
      if (ago.isNotEmpty) ...[
        const SizedBox(width: S.s8),
        Text(ago, style: mono(11, color: AppColors.fg4)),
      ],
      SizedBox.square(
        dimension: kMobile ? 44 : 28,
        child: IconButton(
          tooltip: 'Dismiss',
          padding: EdgeInsets.zero,
          style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          icon: AppIcon('x', size: kMobile ? 14 : 12, color: AppColors.fg4),
          onPressed: widget.onDismiss,
        ),
      ),
    ]);

    final choices = _choices;
    final Widget? actions = switch (action) {
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
      CardAction.answer when choices.isNotEmpty => Wrap(
          spacing: S.s8,
          runSpacing: S.s8,
          children: [
            for (final (i, (label, value)) in choices.indexed)
              Btn(label,
                  small: true,
                  variant: i == 0 ? BtnVariant.primary : BtnVariant.secondary,
                  disabled: busy,
                  onTap: () => _send(
                      _answer(label == value ? label : '$label ($value)'))),
          ]),
      CardAction.answer || CardAction.reply => _ReplyField(
          controller: _text,
          focus: _focus,
          busy: busy,
          hint: action == CardAction.answer ? 'Answer…' : 'Reply…',
          onSubmit: () => _submitText(action),
        ),
      _ => null,
    };

    final link = sans(12.5, weight: W.label, color: AppColors.accent);
    Widget textLink(String label, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.xs),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: 4, vertical: kMobile ? 8 : 3),
            child: Text(label, style: link),
          ),
        );

    final expanded = Padding(
      padding: const EdgeInsets.only(left: 18, right: S.s12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showBody)
            Text(body,
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
                style: sans(kMobile ? 14.5 : 13.5,
                    height: 1.45, color: AppColors.fg1)),
          if (_moreQuestions > 0)
            Padding(
              padding: const EdgeInsets.only(top: S.s4),
              child: Text(
                  '+$_moreQuestions more question${_moreQuestions == 1 ? '' : 's'} in the chat',
                  style: sans(12, color: AppColors.fg3)),
            ),
          if (actions != null && _moreQuestions == 0)
            Padding(
                padding: const EdgeInsets.only(top: 10), child: actions),
          if (_state == _Send.failed)
            Padding(
              padding: const EdgeInsets.only(top: S.s6),
              child: Text("Couldn't send. Open chat",
                  style: sans(12, color: AppColors.danger)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: S.s4),
            child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: S.s8,
                children: [
                  Transform.translate(
                      offset: const Offset(-4, 0),
                      child: textLink('Open chat', widget.onOpen)),
                ]),
          ),
        ],
      ),
    );

    final motion = MediaQuery.maybeDisableAnimationsOf(context) == true
        ? Duration.zero
        : const Duration(milliseconds: 280);
    final radius = kMobile ? (_open ? 24.0 : 28.0) : (_open ? 12.0 : 10.0);

    return LayoutBuilder(builder: (context, box) {
      final full = box.maxWidth;
      final width = kMobile && !_open ? math.min(full, 300.0) : full;
      return Align(
        alignment: kMobile && _expandable
            ? Alignment.topCenter
            : Alignment.topRight,
        heightFactor: 1,
        child: AnimatedContainer(
          duration: motion,
          curve: Curves.easeOutCubic,
          width: width,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            border: Border.all(color: AppColors.lineStrong),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: _toggle,
              onLongPress: widget.rest.isEmpty ? null : widget.onClearAll,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    kMobile ? 18 : 14, kMobile ? 6 : 8, 4, kMobile ? 6 : 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextHeightBehavior(
                      textHeightBehavior: const TextHeightBehavior(
                          leadingDistribution: TextLeadingDistribution.even),
                      child: head,
                    ),
                    AnimatedSize(
                      duration: motion,
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topLeft,
                      child: AnimatedSwitcher(
                        duration: motion,
                        switchInCurve: const Interval(.35, 1,
                            curve: Curves.easeOut),
                        switchOutCurve: Curves.easeIn,
                        child: _open
                            ? KeyedSubtree(
                                key: const ValueKey('open'), child: expanded)
                            : const SizedBox(
                                key: ValueKey('closed'),
                                width: double.infinity),
                      ),
                    ),
                    if (widget.rest.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 18, top: S.s4),
                        child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: S.s8,
                            children: [
                              Text(_moreLabel,
                                  style: mono(11.5, color: AppColors.fg4)),
                              if (!kMobile)
                                textLink('Clear all', widget.onClearAll),
                            ]),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

(String, Color) _mood(Map<String, dynamic> p, CardAction a) =>
    switch ('${p['kind'] ?? ''}'.split('.').last) {
      'waiting' => (
          switch (a) {
            CardAction.approval => 'wants approval',
            CardAction.answer => 'has a question',
            _ => 'needs you',
          },
          AppColors.run,
        ),
      'done' || 'completed' => ('done', AppColors.ok),
      'error' || 'failed' => ('failed', AppColors.danger),
      'idle' => ('stopped', AppColors.fg3),
      _ => ('', AppColors.fg4),
    };

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
