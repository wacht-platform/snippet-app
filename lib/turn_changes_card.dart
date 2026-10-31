import 'package:flutter/material.dart';

import 'file_icons.dart';
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
              height: 46,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: AppColors.surface3,
                        borderRadius: BorderRadius.circular(8)),
                    child: AppIcon('file-diff', size: 15, color: AppColors.fg2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        '$total ${total == 1 ? 'file' : 'files'} changed',
                        style:
                            sans(13.5, weight: W.label, color: AppColors.fg1)),
                  ),
                  _Bar(_n(e['add']), _n(e['del']), width: 44),
                  const SizedBox(width: 10),
                  _Delta(_n(e['add']), _n(e['del']), size: 12.5),
                  const SizedBox(width: 6),
                  AppIcon(_open ? 'chevron-down' : 'chevron-right',
                      size: 13, color: AppColors.fg4),
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
                  height: 32,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                    child: Row(children: [
                      FileGlyph(f.path.split('/').last, size: 15),
                      const SizedBox(width: 10),
                      Expanded(child: _Path(f.path)),
                      const SizedBox(width: 10),
                      _Bar(f.add, f.del, width: 28),
                      const SizedBox(width: 10),
                      SizedBox(
                          width: 74,
                          child: Align(
                              alignment: Alignment.centerRight,
                              child: _Delta(f.add, f.del, size: 12))),
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
                    padding: const EdgeInsets.fromLTRB(39, 0, 14, 0),
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

class _Bar extends StatelessWidget {
  const _Bar(this.add, this.del, {required this.width});

  final int add;
  final int del;
  final double width;

  @override
  Widget build(BuildContext context) {
    final total = add + del;
    if (total == 0) return SizedBox(width: width);
    final share = (add / total).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        width: width,
        height: 4,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
              flex: (share * 100).round().clamp(1, 99),
              child: ColoredBox(color: AppColors.ok)),
          Expanded(
              flex: ((1 - share) * 100).round().clamp(1, 99),
              child: ColoredBox(color: AppColors.danger)),
        ]),
      ),
    );
  }
}
