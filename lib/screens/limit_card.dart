import 'package:flutter/material.dart';

import '../api.dart';
import '../transcript_card.dart';
import '../widgets.dart';
import 'routing_screen.dart' show limitLabel;

class LimitCard extends StatefulWidget {
  const LimitCard({
    super.key,
    required this.client,
    required this.session,
    required this.profile,
    required this.resetsAt,
    required this.options,
    required this.settled,
  });

  final DaemonClient client;
  final String session;
  final String profile;
  final int resetsAt;
  final List<String> options;
  final bool settled;

  @override
  State<LimitCard> createState() => _LimitCardState();
}

class _LimitCardState extends State<LimitCard> {
  String? _busy;

  Future<void> _act(String action, {String? profile}) async {
    setState(() => _busy = profile ?? action);
    try {
      await widget.client
          .resolveLimit(widget.session, action, profile: profile);
    } catch (e) {
      if (mounted) toast(context, "Couldn't do that: $e", danger: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reset = widget.resetsAt > 0 ? limitLabel(widget.resetsAt) : null;
    if (widget.settled) {
      return NoteLine(reset == null
          ? '${widget.profile} hit its usage limit. Handled.'
          : '${widget.profile} hit its usage limit. Resets at $reset.');
    }
    return TranscriptCard(
      icon: 'clock',
      tone: Tone.run,
      kind: 'Usage limit',
      status: 'Paused',
      title: '${widget.profile} hit its usage limit',
      body: reset == null
          ? 'Continue on another model now, or wait for it to reset.'
          : 'It resets at $reset. Continue on another model now, or wait and this chat picks up then.',
      footer: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (i, p) in widget.options.take(3).indexed)
          Btn(_busy == p ? 'Switching…' : 'Continue on $p',
              small: true,
              variant: i == 0 ? BtnVariant.primary : BtnVariant.secondary,
              disabled: _busy != null,
              onTap: () => _act('switch', profile: p)),
        Btn(reset == null ? 'Wait' : 'Wait until $reset',
            small: true,
            variant: BtnVariant.secondary,
            disabled: _busy != null,
            onTap: () => _act('wait')),
      ]),
    );
  }
}
