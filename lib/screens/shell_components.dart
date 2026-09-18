import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// Modal popover for setting the session goal.
class GoalPopover extends StatefulWidget {
  final void Function(String text) onSet;
  const GoalPopover({super.key, required this.onSet});

  @override
  State<GoalPopover> createState() => _GoalPopoverState();
}

class _GoalPopoverState extends State<GoalPopover> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctl.text.trim();
    if (t.isEmpty) return;
    widget.onSet(t);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Set goal',
            style: sans(12, weight: W.label, color: AppColors.fg1)),
        const SizedBox(height: 8),
        AppField(
          controller: _ctl,
          hint: 'What should the agent work toward?',
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Spacer(),
          Btn('Cancel',
              variant: BtnVariant.ghost,
              small: true,
              onTap: () => Navigator.pop(context)),
          const SizedBox(width: 6),
          Btn('Set goal', small: true, onTap: _submit),
        ]),
      ],
    );
  }
}

/// Keeps a swiped-away tab mounted so its WebSocket attach and scroll position
/// survive switching between tabs.
class ShellKeepAlive extends StatefulWidget {
  final Widget child;
  final bool keep;
  const ShellKeepAlive({super.key, required this.child, this.keep = true});
  @override
  State<ShellKeepAlive> createState() => _ShellKeepAliveState();
}

class _ShellKeepAliveState extends State<ShellKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keep;
  @override
  void didUpdateWidget(covariant ShellKeepAlive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keep != widget.keep) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    super.build(context);
    return widget.child;
  }
}

/// Small green pulsing dot indicating a running session.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      if (_ctrl.isAnimating) _ctrl.stop();
      _ctrl.value = 1;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl.drive(Tween(begin: 0.4, end: 1.0)),
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFF34D399), // emerald-400
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// The agent working in a session, as a small inline badge.
///
/// Inline and compact on purpose: it answers "who is in here" on the row, so it
/// needs no screen of its own, and it renders only when an agent is actually
/// bound — an ordinary chat stays visually quiet.
///
/// [working] is the difference between the two facts worth telling apart: an
/// agent ASSIGNED to a chat is quiet accent, while one actually mid-turn takes
/// the run colour. Without it every bound session looked equally busy, which is
/// the opposite of what the badge is for.
class AgentBadge extends StatelessWidget {
  const AgentBadge({super.key, required this.agentId, this.working = false});

  final String agentId;
  final bool working;

  @override
  Widget build(BuildContext context) {
    final fg = working ? AppColors.run : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: working ? AppColors.runBg : AppColors.accentBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppIcon('agent', size: 11, color: fg),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 96),
          child: Text(
            agentId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(10, weight: W.label, color: fg),
          ),
        ),
      ]),
    );
  }
}
