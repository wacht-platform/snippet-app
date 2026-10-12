import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api.dart';
import '../menu_widgets.dart';
import '../models.dart';
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'presented_file_card.dart';

bool get _canEmbedWeb =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

String artifactIcon(String kind) => switch (kind) {
      'html' => 'globe',
      'markdown' => 'file-text',
      'image' || 'svg' => 'image',
      'csv' => 'list',
      'pdf' => 'pdf',
      'code' => 'file-code',
      'collection' => 'layers',
      _ => 'file',
    };

/// Open an artifact: a side drawer on desktop, a full screen on a phone.
Future<void> openArtifact(
  BuildContext context, {
  required DaemonClient client,
  required String session,
  required String id,
  int? version,
}) {
  return presentScreen<void>(
    context,
    style: PanelStyle.drawer,
    maxWidth: 820,
    builder: (_, close) => ArtifactViewer(
      client: client,
      session: session,
      id: id,
      version: version,
      onClose: close,
    ),
  );
}

/// An artifact in the transcript: one line with its title and version.
class ArtifactRow extends StatelessWidget {
  const ArtifactRow({
    super.key,
    required this.client,
    required this.session,
    required this.id,
    required this.version,
    required this.title,
    required this.kind,
    required this.caption,
  });

  final DaemonClient client;
  final String session;
  final String id;
  final int version;
  final String title;
  final String kind;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openArtifact(context,
          client: client, session: session, id: id, version: version),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.s4),
        child: Row(children: [
          SizedBox(
            width: 16,
            child: Center(
                child: AppIcon(artifactIcon(kind),
                    size: 14, color: AppColors.accent)),
          ),
          const SizedBox(width: S.s8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: title, style: TS.ui(AppColors.fg1)),
                TextSpan(text: '  v$version', style: TS.meta(AppColors.fg4)),
                if (caption.isNotEmpty)
                  TextSpan(text: '  $caption', style: TS.ui(AppColors.fg3)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: S.s6),
          AppIcon('chevron-right', size: 12, color: AppColors.fg4),
        ]),
      ),
    );
  }
}

class ArtifactViewer extends StatefulWidget {
  const ArtifactViewer({
    super.key,
    required this.client,
    required this.session,
    required this.id,
    this.version,
    this.onClose,
  });

  final DaemonClient client;
  final String session;
  final String id;
  final int? version;
  final VoidCallback? onClose;

  @override
  State<ArtifactViewer> createState() => _ArtifactViewerState();
}

class _ArtifactViewerState extends State<ArtifactViewer> {
  ArtifactInfo? _artifact;
  int? _n;
  bool _source = false;
  String? _error;
  Future<String>? _text;
  String? _textFor;

  @override
  void initState() {
    super.initState();
    _n = widget.version;
    _load();
  }

  Future<void> _load({bool latest = false}) async {
    try {
      final all = await widget.client.artifacts(widget.session);
      final found = all.where((a) => a.id == widget.id).firstOrNull;
      if (!mounted) return;
      setState(() {
        _artifact = found;
        _error = found == null ? 'This artifact is no longer available.' : null;
        if (latest || _n == null) _n = found?.latest?.n;
        _textFor = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  ArtifactVersion? get _version => _artifact?.version(_n ?? 0);

  bool get _hasSource => switch (_artifact?.kind) {
        'html' || 'markdown' || 'csv' || 'code' || 'svg' => true,
        _ => false,
      };

  Future<String> _textOf(ArtifactVersion v) {
    if (_textFor != v.url || _text == null) {
      _textFor = v.url;
      _text = widget.client.artifactText(v.url);
    }
    return _text!;
  }

  Future<void> _pickVersion(BuildContext anchor) async {
    final a = _artifact;
    if (a == null || a.versions.length < 2) return;
    final picked = await showAppMenu<int>(
      context,
      anchor: anchor,
      minWidth: 200,
      items: [
        appMenuHeading<int>('Versions'),
        for (final v in a.versions.reversed)
          appMenuRow<int>(
            value: v.n,
            icon: 'history',
            label: 'Version ${v.n}',
            description: _when(v.createdAt),
            selected: v.n == _n,
          ),
      ],
    );
    if (picked != null && mounted) setState(() => _n = picked);
  }

  String _when(int seconds) {
    if (seconds <= 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.day}/${t.month} $hh:$mm';
  }

  void _openInBrowser() {
    final v = _version;
    if (v == null) return;
    launchUrl(widget.client.artifactUri(v.url),
        mode: LaunchMode.externalApplication);
  }

  Widget _header() {
    final a = _artifact;
    final v = _version;
    return Container(
      padding: EdgeInsets.fromLTRB(16, kMobile ? 8 : 12, 8, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        if (a != null)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: AppIcon(artifactIcon(a.kind), size: 16, color: AppColors.accent),
          ),
        Expanded(
          child: Text(a?.title ?? 'Artifact',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(15, weight: W.label, color: AppColors.fg1)),
        ),
        if (v != null)
          Builder(
            builder: (anchor) => TextButton(
              onPressed: (a?.versions.length ?? 0) > 1
                  ? () => _pickVersion(anchor)
                  : null,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('v${v.n}', style: TS.meta(AppColors.fg2)),
                if ((a?.versions.length ?? 0) > 1) ...[
                  const SizedBox(width: 2),
                  AppIcon('chevron-down', size: 12, color: AppColors.fg3),
                ],
              ]),
            ),
          ),
        if (_hasSource)
          IconBtn(_source ? 'eye' : 'code',
              size: 32,
              iconSize: 15,
              tooltip: _source ? 'Preview' : 'Source',
              onTap: () => setState(() => _source = !_source)),
        IconBtn('globe',
            size: 32,
            iconSize: 15,
            tooltip: 'Open in browser',
            onTap: _openInBrowser),
        IconBtn('refresh',
            size: 32,
            iconSize: 15,
            tooltip: 'Latest version',
            onTap: () => _load(latest: true)),
        if (widget.onClose != null)
          IconBtn('x',
              size: 32, iconSize: 15, tooltip: 'Close', onTap: widget.onClose),
      ]),
    );
  }

  Widget _centered(String text, {Widget? action}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text,
                textAlign: TextAlign.center,
                style: sans(13, color: AppColors.fg3, height: 1.5)),
            if (action != null) ...[const SizedBox(height: 12), action],
          ]),
        ),
      );

  Widget _textBody(ArtifactVersion v, Widget Function(String text) render) =>
      FutureBuilder<String>(
        future: _textOf(v),
        builder: (context, snap) {
          if (snap.hasError) return _centered('${snap.error}');
          if (!snap.hasData) return Center(child: Spinner(size: 16, color: AppColors.fg3));
          return render(snap.data!);
        },
      );

  Widget _sourceView(ArtifactVersion v) => _textBody(
        v,
        (text) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(text,
              style: mono(12, height: 1.5, color: AppColors.fg2)),
        ),
      );

  Widget _preview(ArtifactInfo a, ArtifactVersion v) {
    final uri = widget.client.artifactUri(v.url);
    switch (a.kind) {
      case 'markdown':
        return _textBody(
          v,
          (text) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: SelectionArea(
              child: MarkdownBody(
                  data: text, styleSheet: markdownStyle(context)),
            ),
          ),
        );
      case 'image':
        return InteractiveViewer(
          maxScale: 6,
          child: Center(child: Image.network(uri.toString())),
        );
      case 'csv':
        return _textBody(v, (text) => _CsvTable(text: text));
      case 'code':
      case 'file':
        return _sourceView(v);
      default:
        if (!_canEmbedWeb) {
          return _centered('This page opens in your browser.',
              action: TextButton(
                  onPressed: _openInBrowser, child: const Text('Open in browser')));
        }
        return _WebPreview(key: ValueKey(v.url), uri: uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _artifact;
    final v = _version;
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(),
          Expanded(
            child: _error != null
                ? _centered(_error!)
                : a == null || v == null
                    ? Center(child: Spinner(size: 16, color: AppColors.fg3))
                    : _source && _hasSource
                        ? _sourceView(v)
                        : _preview(a, v),
          ),
        ]),
      ),
    );
  }
}

class _WebPreview extends StatefulWidget {
  const _WebPreview({super.key, required this.uri});
  final Uri uri;

  @override
  State<_WebPreview> createState() => _WebPreviewState();
}

class _WebPreviewState extends State<_WebPreview> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(AppColors.bg)
    ..loadRequest(widget.uri);

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

class _CsvTable extends StatelessWidget {
  const _CsvTable({required this.text});
  final String text;

  List<List<String>> _rows() {
    final sep = text.split('\n').first.contains('\t') ? '\t' : ',';
    final rows = <List<String>>[];
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final cells = <String>[];
      final cell = StringBuffer();
      var quoted = false;
      for (var i = 0; i < line.length; i++) {
        final c = line[i];
        if (c == '"') {
          if (quoted && i + 1 < line.length && line[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = !quoted;
          }
        } else if (c == sep && !quoted) {
          cells.add(cell.toString());
          cell.clear();
        } else {
          cell.write(c);
        }
      }
      cells.add(cell.toString().trimRight());
      rows.add(cells);
      if (rows.length > 500) break;
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    if (rows.isEmpty) return const SizedBox.shrink();
    final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    Widget cell(String text, {bool head = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(text,
              style: head
                  ? sans(12.5, weight: W.label, color: AppColors.fg1)
                  : sans(12.5, color: AppColors.fg2)),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(
            horizontalInside: BorderSide(color: AppColors.border),
          ),
          children: [
            for (var i = 0; i < rows.length; i++)
              TableRow(
                decoration:
                    i == 0 ? BoxDecoration(color: AppColors.surface1) : null,
                children: [
                  for (var c = 0; c < width; c++)
                    cell(c < rows[i].length ? rows[i][c] : '', head: i == 0),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Everything a session has handed over: its artifacts, latest first, then
/// the files it sent, newest first.
class SessionDeliverables extends StatefulWidget {
  const SessionDeliverables({
    super.key,
    required this.client,
    required this.session,
    required this.files,
    this.onOpenFileTab,
    this.onClose,
  });

  final DaemonClient client;
  final String session;
  final List<({String path, String caption})> files;
  final void Function(String path, String name)? onOpenFileTab;
  final VoidCallback? onClose;

  @override
  State<SessionDeliverables> createState() => _SessionDeliverablesState();
}

class _SessionDeliverablesState extends State<SessionDeliverables> {
  List<ArtifactInfo>? _artifacts;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.client.artifacts(widget.session).then((a) {
      if (mounted) setState(() => _artifacts = a);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
        child: Text(label, style: TS.meta(AppColors.fg3)),
      );

  @override
  Widget build(BuildContext context) {
    final artifacts = _artifacts;
    final seen = <String>{};
    final files = [
      for (final f in widget.files.reversed)
        if (seen.add(f.path)) f,
    ];
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: EdgeInsets.fromLTRB(16, kMobile ? 8 : 12, 8, 10),
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(children: [
              Expanded(
                child: Text('Artifacts & files',
                    style: sans(15, weight: W.label, color: AppColors.fg1)),
              ),
              if (widget.onClose != null)
                IconBtn('x',
                    size: 32,
                    iconSize: 15,
                    tooltip: 'Close',
                    onTap: widget.onClose),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                _section('Artifacts'),
                if (_error != null)
                  Text(_error!, style: TS.meta(AppColors.danger))
                else if (artifacts == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Spinner(size: 14, color: AppColors.fg3),
                  )
                else if (artifacts.isEmpty)
                  Text('None yet.', style: TS.meta(AppColors.fg4))
                else
                  for (final a in artifacts)
                    ArtifactRow(
                      client: widget.client,
                      session: widget.session,
                      id: a.id,
                      version: a.latest?.n ?? 1,
                      title: a.title,
                      kind: a.kind,
                      caption: a.caption,
                    ),
                _section('Files'),
                if (files.isEmpty)
                  Text('None yet.', style: TS.meta(AppColors.fg4))
                else
                  for (final f in files)
                    PresentedFileCard(
                      client: widget.client,
                      path: f.path,
                      caption: f.caption,
                      onOpenFileTab: widget.onOpenFileTab,
                    ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
