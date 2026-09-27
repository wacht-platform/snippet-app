import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../swr.dart';
import '../theme.dart';
import '../widgets.dart';

/// Background processes the agent started (dev servers, tunnels, a browser) via
/// `bash {background:true}`. Lists them from /bg with a live status, a log tail,
/// and a stop button. Revalidates when the daemon reports a process change.
class ProcessesScreen extends StatefulWidget {
  final DaemonClient client;
  final String sessionId;
  final VoidCallback? onClose;
  const ProcessesScreen(
      {super.key, required this.client, required this.sessionId, this.onClose});
  @override
  State<ProcessesScreen> createState() => _ProcessesScreenState();
}

class _ProcessesScreenState extends State<ProcessesScreen> {
  List<Map<String, dynamic>>? _procs;
  bool _loading = true;
  String? _error;
  String? _openLogId;
  String _log = '';
  bool _logLoading = false;
  late final Swr<List<Map<String, dynamic>>> _list;

  @override
  void initState() {
    super.initState();
    _list = Swr<List<Map<String, dynamic>>>(
      client: widget.client,
      key: 'bg:${widget.sessionId}',
      fetch: () => widget.client.bgList(widget.sessionId),
      revalidateOn: (e) => e['kind'] == 'process',
      onChange: _sync,
    );
    _procs = _list.data;
    _loading = _procs == null;
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) => _list.refresh();

  void _sync() {
    if (!mounted) return;
    final p = _list.data;
    setState(() {
      _procs = p ?? _procs;
      _loading = _list.loading;
      _error = p == null && _list.error != null ? '${_list.error}' : null;
      if (p != null &&
          _openLogId != null &&
          !p.any((e) => '${e['id']}' == _openLogId)) {
        _openLogId = null;
      }
    });
  }

  Future<void> _kill(String id) async {
    try {
      await widget.client.bgKill(widget.sessionId, id);
      if (mounted) toast(context, 'Stopped');
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
    await _load(silent: true);
  }

  Future<void> _toggleLog(String id) async {
    if (_openLogId == id) {
      setState(() {
        _openLogId = null;
        _log = '';
      });
      return;
    }
    setState(() {
      _openLogId = id;
      _log = '';
      _logLoading = true;
    });
    try {
      final t = await widget.client.bgLog(widget.sessionId, id);
      if (mounted && _openLogId == id) {
        setState(() {
          _log = t;
          _logLoading = false;
        });
      }
    } catch (e) {
      if (mounted && _openLogId == id) {
        setState(() {
          _log = '$e';
          _logLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final procs = _procs ?? const [];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
            title: 'Processes',
            titleSize: 14,
            compact: true,
            onBack: widget.onClose ?? () => Navigator.pop(context),
            actions: [IconBtn('refresh', onTap: () => _load())],
          ),
          if (_loading)
            const Expanded(child: Center(child: DelayedSpinner()))
          else if (_error != null)
            Expanded(
                child: EmptyState(
                    icon: 'zap', title: "Couldn't load", body: _error!))
          else if (procs.isEmpty)
            const Expanded(
                child: EmptyState(
                    icon: 'zap',
                    title: 'No background processes',
                    body:
                        'Long-running jobs the agent starts (servers, tunnels) show up here.'))
          else
            Expanded(
                child: ListView(
                    padding: const EdgeInsets.all(S.s16),
                    children: [for (final p in procs) _row(p)])),
        ]),
      ),
    );
  }

  Widget _row(Map<String, dynamic> p) {
    final id = '${p['id'] ?? ''}';
    final cmd = '${p['command'] ?? ''}'.replaceAll('\n', ' ');
    final pid = p['pid'] ?? 0;
    final running = p['running'] == true;
    final status = p['status'] as String?;
    final failed = !running && status != null && status != '0';
    final statusLabel = running
        ? 'running'
        : switch (status) {
            '0' => 'exited (ok)',
            'signal' => 'killed',
            final c? when c.isNotEmpty => 'exited ($c)',
            _ => 'exited',
          };
    // A finished process previously wore one grey dot and one grey label
    // whatever the outcome, so `exited (101)` looked exactly like `exited (ok)`
    // — the same "failure is invisible" defect the tool rows had. Colour now
    // summarises the outcome: green live, danger for non-zero/killed, grey for
    // a clean exit.
    final tone = running
        ? Tone.ok
        : failed
            ? Tone.danger
            : Tone.neutral;
    final open = _openLogId == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.s8),
      child: Material(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.s16, S.s12, S.s8, S.s8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(right: S.s8),
              child: Text(cmd,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TS.code(AppColors.fg1)),
            ),
            const SizedBox(height: S.s8),
            Row(children: [
              Tag(statusLabel, tone: tone, dot: !running, live: running),
              const SizedBox(width: S.s8),
              Text('pid $pid', style: TS.meta()),
              const Spacer(),
              TextAction(open ? 'Hide log' : 'Log',
                  onTap: () => _toggleLog(id)),
              if (running)
                TextAction('Stop', onTap: () => _kill(id), danger: true),
            ]),
            if (open) ...[
              const SizedBox(height: S.s8),
              Padding(
                padding: const EdgeInsets.only(right: S.s8, bottom: S.s4),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 240),
                  width: double.infinity,
                  padding: const EdgeInsets.all(S.s12),
                  decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(R.sm + 2)),
                  child: _logLoading
                      ? const Center(child: DelayedSpinner(size: 16))
                      : SingleChildScrollView(
                          child: SelectableText(
                              _log.trim().isEmpty ? '(empty)' : _log,
                              style: TS.codeSmall(AppColors.fg2))),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
