import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
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
    final live = !widget.settled;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AppIcon('clock', size: 14, color: AppColors.run),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${widget.profile} hit its usage limit',
                  style: sans(13.5, weight: W.label, color: AppColors.fg1)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            live
                ? (reset == null
                    ? 'Continue on another model now, or wait for it to reset.'
                    : 'It resets at $reset. Continue on another model now, or wait and this chat picks up then.')
                : (reset == null ? 'Handled.' : 'Resets at $reset.'),
            style: sans(12.5, height: 1.45, color: AppColors.fg3),
          ),
          if (live) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
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
          ],
        ]),
      ),
    );
  }
}
