import 'package:flutter/material.dart';

import 'call_tracking.dart';
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

/// In-app surface for a pending call prompt, or the tracking state with Stop.
class CallPromptCard extends StatefulWidget {
  const CallPromptCard({super.key, required this.status, required this.onAction});
  final CallStatus status;
  final Future<bool> Function(String action) onAction;

  @override
  State<CallPromptCard> createState() => _CallPromptCardState();
}

class _CallPromptCardState extends State<CallPromptCard> {
  var _busy = false;
  var _failed = false;

  Future<void> _run(String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await widget.onAction(action);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tracking = widget.status.phase == CallPhase.tracking;
    final pad = kMobile ? 14.0 : 12.0;
    return Material(
      color: kMobile ? AppColors.surface2 : AppColors.surface1,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kMobile ? 14 : 12),
        side: BorderSide(color: AppColors.line),
      ),
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: tracking ? AppColors.danger : AppColors.accent,
                    shape: BoxShape.circle),
              ),
              const SizedBox(width: S.s8),
              Expanded(
                child: Text(tracking ? 'Tracking call' : widget.status.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 14 : 13,
                        weight: W.label, color: AppColors.fg1)),
              ),
            ]),
            if (!tracking)
              Padding(
                padding: const EdgeInsets.only(top: S.s4, left: 16),
                child: Text(widget.status.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 13.5 : 13, color: AppColors.fg2)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: S.s8, left: 16),
              child: Wrap(spacing: S.s8, runSpacing: S.s8, children: [
                if (tracking)
                  Btn('Stop',
                      small: true,
                      variant: BtnVariant.secondary,
                      disabled: _busy,
                      onTap: () => _run(callActionStop))
                else ...[
                  Btn('Track',
                      small: true,
                      disabled: _busy,
                      onTap: () => _run(callActionTrack)),
                  Btn('Ignore',
                      small: true,
                      variant: BtnVariant.secondary,
                      disabled: _busy,
                      onTap: () => _run(callActionIgnore)),
                ],
              ]),
            ),
            if (_failed)
              Padding(
                padding: const EdgeInsets.only(top: S.s6, left: 16),
                child: Text("Couldn't reach Snippet. Try again.",
                    style: sans(12, color: AppColors.danger)),
              ),
          ],
        ),
      ),
    );
  }
}
