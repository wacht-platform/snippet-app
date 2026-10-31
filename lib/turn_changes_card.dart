import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// End-of-turn summary of what the turn changed on disk. One line until
/// tapped; each file opens, and the footer opens every change.
class TurnChangesCard extends StatefulWidget {
  const TurnChangesCard({
    super.key,
    required this.event,
    this.onOpenFile,
    this.onOpenAll,
  });

  final Map<String, dynamic> event;
  final void Function(String path)? onOpenFile;
  final VoidCallback? onOpenAll;

  @override
  State<TurnChangesCard> createState() => _TurnChangesCardState();
}

class _TurnChangesCardState extends State<TurnChangesCard> {
  bool _open = false;

  static int _n(dynamic v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final files = [
      for (final f in (e['files'] as List? ?? const []))
        if (f is Map)
          (
            path: f['path']?.toString() ?? '',
            add: _n(f['add']),
            del: _n(f['del'])
          ),
    ];
    final total =
        _n(e['total_files']) > 0 ? _n(e['total_files']) : files.length;
    if (total == 0) return const SizedBox.shrink();
    final hidden = total - files.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: SizedBox(
              height: 36,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  AppIcon(_open ? 'chevron-down' : 'chevron-right',
                      size: 12, color: AppColors.fg4),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        '$total ${total == 1 ? 'file' : 'files'} changed',
                        style: sans(13, color: AppColors.fg2)),
                  ),
                  _Delta(_n(e['add']), _n(e['del']), size: 12.5),
                ]),
              ),
            ),
          ),
          if (_open) ...[
            for (final f in files)
              InkWell(
                onTap: widget.onOpenFile == null
                    ? null
                    : () => widget.onOpenFile!(f.path),
                child: SizedBox(
                  height: 28,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 12, 0),
                    child: Row(children: [
                      Expanded(child: _Path(f.path)),
                      const SizedBox(width: 10),
                      _Delta(f.add, f.del, size: 12),
                    ]),
                  ),
                ),
              ),
            if (hidden > 0 || widget.onOpenAll != null)
              InkWell(
                onTap: widget.onOpenAll,
                child: SizedBox(
                  height: 30,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 12, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          hidden > 0
                              ? '$hidden more · view all changes'
                              : 'View all changes',
                          style: sans(12, color: AppColors.fg3)),
                    ),
                  ),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}

class _Path extends StatelessWidget {
  const _Path(this.path);
  final String path;

  @override
  Widget build(BuildContext context) {
    final i = path.lastIndexOf('/');
    final name = i < 0 ? path : path.substring(i + 1);
    final dir = i < 0 ? '' : path.substring(0, i);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: name, style: sans(12.5, color: AppColors.fg1)),
        if (dir.isNotEmpty)
          TextSpan(text: '  $dir', style: sans(11.5, color: AppColors.fg4)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Delta extends StatelessWidget {
  const _Delta(this.add, this.del, {required this.size});

  final int add;
  final int del;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (add > 0)
        Text('+$add', style: sans(size, color: AppColors.ok, tabular: true)),
      if (add > 0 && del > 0) const SizedBox(width: 6),
      if (del > 0)
        Text('-$del',
            style: sans(size, color: AppColors.danger, tabular: true)),
    ]);
  }
}
