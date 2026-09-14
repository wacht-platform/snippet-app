import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../agent_messaging.dart';

/// One coordination agent: who it is, and — the important part — its board.
///
/// The role/kind/capability fields are header context, not the content. What an
/// agent actually IS on this machine is what it dispatched, what came back, and
/// what it concluded, so the board is the body of this page.
///
/// Renders two ways: as a full screen with its own app bar, or `embedded` as the
/// shell's right pane — the same data, no nested modal to dismiss.
class CoordinationAgentDetail extends StatefulWidget {
  const CoordinationAgentDetail({
    super.key,
    required this.agent,
    this.client,
    this.embedded = false,
    this.onClose,
  });

  /// The daemon connection. Optional because one host (the shell's right pane)
  /// renders this before an instance is active; the board then reports that it
  /// is unavailable rather than pretending the agent has no memory.
  final DaemonClient? client;
  final CoordinationAgent agent;

  /// When embedded, the host owns the chrome and supplies [onClose].
  final bool embedded;
  final VoidCallback? onClose;

  @override
  State<CoordinationAgentDetail> createState() =>
      _CoordinationAgentDetailState();
}

class _CoordinationAgentDetailState extends State<CoordinationAgentDetail> {
  List<BoardEntry> _board = const [];
  bool _loading = true;
  String? _error;
  String? _kindFilter;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = widget.client;
    if (client == null) {
      setState(() {
        _error = null;
        _loading = false;
      });
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final entries = await client.agentBoard(
        widget.agent.id,
        kind: _kindFilter,
        contains: _search.text.trim().isEmpty ? null : _search.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _board = entries;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  CoordinationAgent get agent => widget.agent;

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    if (widget.embedded) {
      return Container(
        color: AppColors.bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(children: [
                Expanded(
                  child: Text(agent.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(14, weight: W.title, color: AppColors.fg1)),
                ),
                if (widget.onClose != null)
                  IconBtn('x',
                      size: 28,
                      iconSize: 15,
                      tooltip: 'Close',
                      onTap: widget.onClose),
              ]),
            ),
            Divider(height: 1, color: AppColors.border),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(agent.displayName)),
      body: body,
    );
  }

  Widget _body(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        Divider(height: 1, color: AppColors.border),
        _controls(),
        Expanded(child: _boardList()),
      ],
    );
  }

  Widget _header() {
    final initial = agent.displayName.trim().isEmpty
        ? '?'
        : agent.displayName.trim()[0].toUpperCase();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, widget.embedded ? 14 : 18, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: widget.embedded ? 18 : 22,
            backgroundColor: AppColors.accentBg,
            foregroundColor: AppColors.accent,
            child: Text(initial,
                style: sans(widget.embedded ? 15 : 18,
                    weight: W.title, color: AppColors.accent)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(agent.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(16, weight: W.title, color: AppColors.fg1)),
                const SizedBox(height: 3),
                Text('@${agent.handle} · ${agent.role} · ${agent.status}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(10.5, color: AppColors.fg4)),
              ],
            ),
          ),
          if (widget.client != null)
            Btn('Message',
                small: true,
                variant: BtnVariant.ghost,
                icon: 'message',
                onTap: () => openAgentThread(
                      context,
                      client: widget.client!,
                      agentId: agent.id,
                      agentName: agent.displayName,
                    )),
        ],
      ),
    );
  }

  /// Filter chips + search. The kinds are the three things a board row can be,
  /// which is what makes recall answerable: "what did I dispatch" is a click,
  /// not a scrolled list.
  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            for (final (label, value) in const [
              ('All', null),
              ('Dispatched', 'dispatched'),
              ('Reported', 'reported'),
              ('Noted', 'noted'),
            ]) ...[
              _filterChip(label, value),
              const SizedBox(width: 6),
            ],
            const Spacer(),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _search,
                onSubmitted: (_) => _load(),
                style: sans(12.5, color: AppColors.fg1),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search memory',
                  hintStyle: sans(12.5, color: AppColors.fg4),
                  prefixIcon: Icon(Icons.search,
                      size: 15, color: AppColors.fg4),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(R.sm),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(R.sm),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String? value) {
    final selected = _kindFilter == value;
    return Material(
      color: selected ? AppColors.accentBg : AppColors.surface2,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        onTap: () {
          setState(() => _kindFilter = value);
          _load();
        },
        borderRadius: BorderRadius.circular(R.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Text(label,
              style: sans(11.5,
                  weight: W.label,
                  color: selected ? AppColors.accent : AppColors.fg3)),
        ),
      ),
    );
  }

  Widget _boardList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: sans(12.5, color: AppColors.danger)),
        ),
      );
    }
    // No daemon connection: say so rather than reporting an empty board, which
    // would read as "this agent has never done anything".
    if (widget.client == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text('Connect to a machine to see its agent boards.',
              textAlign: TextAlign.center,
              style: sans(12.5, color: AppColors.fg4)),
        ),
      );
    }
    if (_board.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon('layers', size: 22, color: AppColors.fg4),
              const SizedBox(height: 10),
              Text(
                _kindFilter == null && _search.text.trim().isEmpty
                    ? 'Nothing recorded yet.\nWork this agent dispatches or concludes appears here.'
                    : 'No rows match that filter.',
                textAlign: TextAlign.center,
                style: sans(12.5, color: AppColors.fg4),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      itemCount: _board.length,
      itemBuilder: (_, i) => _boardRow(_board[i]),
    );
  }

  Widget _boardRow(BoardEntry entry) {
    final (icon, color) = switch (entry.kind) {
      'dispatched' => ('send', AppColors.accent),
      'reported' => ('check-check', AppColors.ok),
      _ => ('message', AppColors.fg3),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: AppIcon(icon, size: 14, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.summary,
                      style: sans(12.5, height: 1.4, color: AppColors.fg1)),
                  const SizedBox(height: 5),
                  Text(
                    [
                      entry.kind,
                      if (entry.workspace != null) entry.workspace!,
                      if (entry.sessionId != null) entry.sessionId!,
                      _shortTime(entry.createdAt),
                    ].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(9.5, color: AppColors.fg4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact age label. The board is read newest-first, so a relative time is
  /// more useful than a timestamp.
  static String _shortTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final age = DateTime.now().difference(parsed);
    if (age.inMinutes < 1) return 'just now';
    if (age.inHours < 1) return '${age.inMinutes}m ago';
    if (age.inDays < 1) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
  }
}
