import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'artifact_viewer.dart';
import '../file_icons.dart';

class ArtifactGrid extends StatefulWidget {
  const ArtifactGrid({
    super.key,
    required this.client,
    required this.session,
    required this.artifacts,
    required this.files,
    this.onOpenFileTab,
  });

  final DaemonClient client;
  final String session;
  final List<ArtifactInfo> artifacts;
  final List<({String path, String caption})> files;
  final void Function(String path, String name)? onOpenFileTab;

  @override
  State<ArtifactGrid> createState() => _ArtifactGridState();
}

String _group(String kind) => switch (kind) {
      'html' => 'Pages',
      'image' || 'svg' => 'Images',
      _ => 'Docs',
    };

String _kindLabel(String kind) => switch (kind) {
      'html' => 'Page',
      'markdown' => 'Doc',
      'image' || 'svg' => 'Image',
      'csv' => 'Table',
      'pdf' => 'PDF',
      'code' => 'Code',
      'collection' => 'Collection',
      _ => 'File',
    };

class _ArtifactGridState extends State<ArtifactGrid> {
  String _filter = 'All';

  Widget _chip(String label, int n) {
    final on = _filter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: on ? AppColors.surface2 : Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.sm),
            side: BorderSide(color: on ? Colors.transparent : AppColors.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          onTap: () => setState(() => _filter = label),
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: Text('$label $n',
                style: sans(12, color: on ? AppColors.fg1 : AppColors.fg3)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, int>{};
    for (final a in widget.artifacts) {
      groups[_group(a.kind)] = (groups[_group(a.kind)] ?? 0) + 1;
    }
    final total = widget.artifacts.length + widget.files.length;
    final arts = [
      for (final a in widget.artifacts)
        if (_filter == 'All' || _group(a.kind) == _filter) a
    ];
    final files = _filter == 'All' || _filter == 'Files'
        ? widget.files
        : const <({String path, String caption})>[];
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > 640;
      final side = wide ? 32.0 : 14.0;
      final cols = ((box.maxWidth - side * 2 + 10) / (wide ? 230 : 170))
          .floor()
          .clamp(2, 6);
      final cards = <Widget>[
        for (final a in arts)
          _Card(
            title: a.title.isEmpty ? a.id : a.title,
            meta: [
              _kindLabel(a.kind),
              if (a.latest != null) 'v${a.latest!.n}',
              if ((a.latest?.createdAt ?? 0) > 0)
                relativeTime(a.latest!.createdAt),
            ].join(' · '),
            thumb: _ArtifactThumb(client: widget.client, artifact: a),
            onTap: () => openArtifact(context,
                client: widget.client,
                session: widget.session,
                id: a.id,
                version: a.latest?.n ?? 1),
          ),
        for (final f in files)
          _Card(
            title: f.path.split('/').last,
            meta: f.caption.isEmpty ? 'File' : f.caption,
            thumb: Center(
              child: FileGlyph(f.path, size: 26),
            ),
            onTap: widget.onOpenFileTab == null
                ? null
                : () => widget.onOpenFileTab!(f.path, f.path.split('/').last),
          ),
      ];
      return ListView(
        padding: EdgeInsets.fromLTRB(side, wide ? 20 : 2, side, 24),
        children: [
          if (wide)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Artifacts',
                  style: sans(18, weight: W.label, color: AppColors.fg1)),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chip('All', total),
              for (final g in ['Pages', 'Images', 'Docs'])
                if ((groups[g] ?? 0) > 0) _chip(g, groups[g]!),
              if (widget.files.isNotEmpty) _chip('Files', widget.files.length),
            ]),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: wide ? 1.15 : 1.0,
            children: cards,
          ),
        ],
      );
    });
  }
}

class _Card extends StatefulWidget {
  const _Card(
      {required this.title, required this.meta, required this.thumb, this.onTap});
  final String title;
  final String meta;
  final Widget thumb;
  final VoidCallback? onTap;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _hover
                    ? AppColors.accent.withValues(alpha: 0.45)
                    : AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Container(color: AppColors.surface2.withValues(alpha: 0.5), child: widget.thumb),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12.5, color: AppColors.fg1)),
                    const SizedBox(height: 2),
                    Text(widget.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(11, color: AppColors.fg4)),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ArtifactThumb extends StatefulWidget {
  const _ArtifactThumb({required this.client, required this.artifact});
  final DaemonClient client;
  final ArtifactInfo artifact;

  @override
  State<_ArtifactThumb> createState() => _ArtifactThumbState();
}

class _ArtifactThumbState extends State<_ArtifactThumb> {
  Future<String>? _text;

  bool get _textual => const {'markdown', 'code', 'csv'}
      .contains(widget.artifact.kind);

  @override
  void initState() {
    super.initState();
    final v = widget.artifact.latest;
    if (v != null && _textual) _text = widget.client.artifactText(v.url);
  }

  Widget _page() => Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              AppIcon('globe', size: 10, color: AppColors.fg4),
              const SizedBox(width: 5),
              Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(3))),
            ]),
            const SizedBox(height: 7),
            Expanded(
              child: Container(
                  decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(4))),
            ),
            const SizedBox(height: 5),
            Row(children: [
              Expanded(
                child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(4))),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4))),
              ),
            ]),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final a = widget.artifact;
    final v = a.latest;
    if (v == null) return Center(child: AppIcon(artifactIcon(a.kind), size: 24, color: AppColors.fg4));
    final uri = widget.client.artifactUri(v.url).toString();
    if (a.kind == 'image') {
      return Image.network(uri,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Center(child: AppIcon('image', size: 24, color: AppColors.fg4)));
    }
    if (a.kind == 'svg') {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SvgPicture.network(uri, fit: BoxFit.contain),
      );
    }
    if (a.kind == 'html') return _page();
    if (_text != null) {
      return FutureBuilder<String>(
        future: _text,
        builder: (_, snap) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Text(
            (snap.data ?? '').split('\n').take(9).join('\n'),
            maxLines: 9,
            overflow: TextOverflow.clip,
            style: mono(9, height: 1.45, color: AppColors.fg4),
          ),
        ),
      );
    }
    return Center(child: AppIcon(artifactIcon(a.kind), size: 26, color: AppColors.fg4));
  }
}
