import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Background processes the agent started (dev servers, tunnels, a browser) via
/// `bash {background:true}`. Lists them from /bg with a live status, a log tail,
/// and a stop button. Auto-refreshes while open.
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
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = _procs == null;
        _error = null;
      });
    }
    try {
      final p = await widget.client.bgList(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _procs = p;
        _loading = false;
        if (_openLogId != null && !p.any((e) => '${e['id']}' == _openLogId)) {
          _openLogId = null;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
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
            onBack: widget.onClose ?? () => Navigator.pop(context),
            actions: [IconBtn('refresh', onTap: () => _load())],
          ),
          if (_loading)
            Expanded(
                child: Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.fg3))))
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
                    padding: const EdgeInsets.all(14),
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
    final statusLabel = running
        ? 'running'
        : switch (status) {
            '0' => 'exited (ok)',
            'signal' => 'killed',
            final c? when c.isNotEmpty => 'exited ($c)',
            _ => 'exited',
          };
    final open = _openLogId == id;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.card),
          border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: running ? AppColors.ok : AppColors.fg4)),
          const SizedBox(width: 9),
          Expanded(
              child: Text(cmd,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: mono(12, color: AppColors.fg1))),
          if (running)
            TextButton(
                onPressed: () => _kill(id),
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4)),
                child: Text('Stop', style: sans(12, color: AppColors.danger))),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Text('pid $pid', style: mono(10.5, color: AppColors.fg4)),
          const SizedBox(width: 12),
          Text(statusLabel, style: mono(10.5, color: AppColors.fg4)),
          const Spacer(),
          GestureDetector(
              onTap: () => _toggleLog(id),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(open ? 'hide log' : 'log',
                      style: mono(11,
                          color: open ? AppColors.accent : AppColors.fg3)))),
        ]),
        if (open) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: AppColors.border)),
            child: _logLoading
                ? Center(
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.fg3)))
                : SingleChildScrollView(
                    child: Text(_log.trim().isEmpty ? '(empty)' : _log,
                        style: mono(10.5, height: 1.4, color: AppColors.fg2))),
          ),
        ],
      ]),
    );
  }
}
