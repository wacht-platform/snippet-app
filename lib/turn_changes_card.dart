import 'package:flutter/material.dart';

import 'theme.dart';

class TurnChangedFile {
  const TurnChangedFile(this.path, this.add, this.del);
  final String path;
  final int add;
  final int del;
}

/// End-of-turn summary: what the turn changed on disk.
class TurnChangesCard extends StatefulWidget {
  const TurnChangesCard({super.key, required this.event});

  final Map<String, dynamic> event;

  @override
  State<TurnChangesCard> createState() => _TurnChangesCardState();
}

class _TurnChangesCardState extends State<TurnChangesCard> {
  static const _collapsedRows = 4;
  bool _open = false;

  static int _n(dynamic v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final files = [
      for (final f in (e['files'] as List? ?? const []))
        if (f is Map)
          TurnChangedFile(
              f['path']?.toString() ?? '', _n(f['add']), _n(f['del'])),
    ];
    final total = _n(e['total_files']) > 0 ? _n(e['total_files']) : files.length;
    if (total == 0) return const SizedBox.shrink();
    final shown = _open ? files : files.take(_collapsedRows).toList();
    final more = total - shown.length;
    final expandable = files.length > _collapsedRows;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.line),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('$total ${total == 1 ? 'file' : 'files'} changed',
                  style: sans(13, weight: W.label, color: AppColors.fg2)),
            ),
            _Delta(_n(e['add']), _n(e['del']), size: 13),
          ]),
          const SizedBox(height: 6),
          for (final f in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                  child: Text(f.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12.5, color: AppColors.fg3)),
                ),
                const SizedBox(width: 10),
                _Delta(f.add, f.del, size: 12.5),
              ]),
            ),
          if (more > 0 || (_open && expandable))
            InkWell(
              onTap: expandable ? () => setState(() => _open = !_open) : null,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
                child: Text(_open ? 'Show less' : '$more more',
                    style: sans(12.5, color: AppColors.fg4)),
              ),
            ),
        ]),
      ),
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
