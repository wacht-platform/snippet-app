import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api.dart';
import '../models.dart';
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'artifact_grid.dart';
import 'file_viewer.dart';
import 'presented_file_card.dart';

const _textExts = {
  'txt', 'log', 'md', 'json', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf',
  'env', 'xml', 'css', 'scss', 'js', 'ts', 'tsx', 'jsx', 'dart', 'rs', 'py',
  'go', 'c', 'h', 'cpp', 'hpp', 'java', 'kt', 'swift', 'rb', 'lua', 'sh',
  'sql', 'diff', 'patch', 'lock', 'vue', 'svelte', 'gradle', 'properties',
};

const _webExts = {
  'html', 'htm', 'svg', 'png', 'jpg', 'jpeg', 'gif', 'webp', 'avif', 'css',
  'js', 'mjs', 'json', 'txt', 'md', 'woff', 'woff2', 'ttf', 'otf', 'ico',
};

String _ext(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
}

bool _isText(String entry) {
  final e = _ext(entry);
  return e.isEmpty || _textExts.contains(e);
}

const _maxTextChars = 200000;

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

/// A tall sheet on a phone, for the artifact viewer and the shared list.
Future<void> showArtifactSheet(
    BuildContext context, Widget Function(VoidCallback close) builder) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    backgroundColor: AppColors.bg,
    sheetAnimationStyle: sheetMotion,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (sheet) {
      void close() => Navigator.of(sheet).pop();
      return FractionallySizedBox(
        heightFactor: 0.94,
        child: _HeaderDragSheet(onClose: close, child: builder(close)),
      );
    },
  );
}

/// Lets the sheet be dragged down by its header only, so the page inside keeps
/// its own scrolling. Past a threshold or on a quick flick it closes.
class _HeaderDragSheet extends StatefulWidget {
  const _HeaderDragSheet({required this.onClose, required this.child});
  final VoidCallback onClose;
  final Widget child;

  @override
  State<_HeaderDragSheet> createState() => _HeaderDragSheetState();
}

class _HeaderDragSheetState extends State<_HeaderDragSheet> {
  static const _headerHeight = 76.0;
  double _dy = 0;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, _dy, 0),
      child: Stack(children: [
        Positioned.fill(child: widget.child),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _headerHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) => setState(() => _dragging = true),
            onVerticalDragUpdate: (d) =>
                setState(() => _dy = (_dy + d.delta.dy).clamp(0.0, double.infinity)),
            onVerticalDragEnd: (d) {
              final flick = (d.primaryVelocity ?? 0) > 700;
              if (flick || _dy > 140) {
                widget.onClose();
              } else {
                setState(() {
                  _dragging = false;
                  _dy = 0;
                });
              }
            },
            onVerticalDragCancel: () => setState(() {
              _dragging = false;
              _dy = 0;
            }),
          ),
        ),
      ]),
    );
  }
}

/// Open an artifact: a side-pane tab on desktop, a tall sheet on a phone.
Future<void> openArtifact(
  BuildContext context, {
  required DaemonClient client,
  required String session,
  required String id,
  int? version,
}) {
  if (kMobile) {
    return showArtifactSheet(
      context,
      (close) => ArtifactViewer(
          client: client,
          session: session,
          id: id,
          version: version,
          onClose: close),
    );
  }
  return presentScreen<void>(
    context,
    style: PanelStyle.drawer,
    maxWidth: 820,
    purpose: ShellPanelPurpose.artifact,
    panelId: id,
    originClient: client,
    originSessionId: session,
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

  String get _kindLabel => switch (kind) {
        'html' => 'Web page',
        'markdown' => 'Document',
        'image' || 'svg' => 'Image',
        'csv' => 'Table',
        'pdf' => 'PDF',
        'code' => 'Code',
        'collection' => 'Collection',
        _ => 'File',
      };

  void _open(BuildContext context) => openArtifact(context,
      client: client, session: session, id: id, version: version);

  @override
  Widget build(BuildContext context) => MediaRow(
        icon: artifactIcon(kind),
        name: title,
        detail: [_kindLabel, 'v$version', if (caption.isNotEmpty) caption]
            .join(' · '),
        onTap: () => _open(context),
      );
}

bool artifactShowsInline(String kind, String? display) {
  final wanted = display == 'inline' ||
      (display == null && (kind == 'markdown' || kind == 'csv' || kind == 'image'));
  if (!wanted) return false;
  return switch (kind) {
    'markdown' || 'csv' || 'code' || 'image' => true,
    'html' || 'svg' => _canEmbedWeb,
    _ => false,
  };
}

class ArtifactInline extends StatefulWidget {
  const ArtifactInline({
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
  State<ArtifactInline> createState() => _ArtifactInlineState();
}

class _ArtifactInlineState extends State<ArtifactInline>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final Future<ArtifactVersion?> _version = _load();
  Future<String>? _text;

  Future<ArtifactVersion?> _load() async {
    final all = await widget.client.artifacts(widget.session);
    final a = all.where((a) => a.id == widget.id).firstOrNull;
    return a?.version(widget.version) ?? a?.latest;
  }

  Future<String> _textOf(ArtifactVersion v) =>
      _text ??= widget.client.artifactText(v.url);

  Widget _loading() => const ArtifactSkeleton();

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: sans(12.5, color: AppColors.fg3)),
      );

  Widget _textBody(ArtifactVersion v, Widget Function(String) render) =>
      FutureBuilder<String>(
        future: _textOf(v),
        builder: (context, snap) {
          if (snap.hasError) return _note('${snap.error}');
          if (!snap.hasData) return _loading();
          return render(snap.data!);
        },
      );

  Widget _body(ArtifactVersion v) {
    final uri = widget.client.artifactUri(v.url);
    switch (widget.kind) {
      case 'markdown':
        return _textBody(
            v,
            (text) => MarkdownBody(
                data: text,
                styleSheet: markdownStyle(context),
                builders: {'pre': PreBlockBuilder()}));
      case 'csv':
        return _textBody(
            v,
            (text) => MarkdownBody(
                data: _csvMarkdown(text),
                styleSheet: markdownStyle(context),
                builders: {'pre': PreBlockBuilder()}));
      case 'code':
        return _textBody(
            v,
            (text) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(text,
                        style: mono(12, height: 1.5, color: AppColors.fg2)),
                  ),
                ));
      case 'image':
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            uri.toString(),
            fit: BoxFit.contain,
            frameBuilder: (context, child, frame, sync) {
              if (sync) return child;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: frame == null
                    ? const ArtifactSkeleton(key: ValueKey('loading'))
                    : KeyedSubtree(key: const ValueKey('loaded'), child: child),
              );
            },
          ),
        );
      default:
        return _InlineWebPage(key: ValueKey(uri.toString()), uri: uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: FutureBuilder<ArtifactVersion?>(
          future: _version,
          builder: (context, snap) {
            if (snap.hasError) return _note('${snap.error}');
            if (snap.connectionState != ConnectionState.done) return _loading();
            final v = snap.data;
            if (v == null) return _note('This artifact is no longer available.');
            return _body(v);
          },
        ),
      );
  }
}

String _csvMarkdown(String text) {
  final rows = _CsvTable(text: text)._rows().take(201).toList();
  if (rows.isEmpty) return '';
  final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
  String line(List<String> r) =>
      '| ${List.generate(width, (i) => (i < r.length ? r[i] : '').replaceAll('|', '\\|')).join(' | ')} |';
  return [
    line(rows.first),
    '|${List.filled(width, '---').join('|')}|',
    for (final r in rows.skip(1)) line(r),
  ].join('\n');
}

String _cssHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

String _cssRgba(Color c) =>
    'rgba(${(c.r * 255).round()},${(c.g * 255).round()},${(c.b * 255).round()},${c.a.toStringAsFixed(3)})';

String snippetPageTheme(bool dark, String bg) {
  final vars = {
    '--sn-bg': bg,
    '--sn-surface': _cssHex(AppColors.surface1),
    '--sn-surface-2': _cssHex(AppColors.surface2),
    '--sn-surface-3': _cssHex(AppColors.surface3),
    '--sn-text': _cssHex(AppColors.fg1),
    '--sn-text-2': _cssHex(AppColors.fg2),
    '--sn-muted': _cssHex(AppColors.fg3),
    '--sn-faint': _cssHex(AppColors.fg4),
    '--sn-border': _cssHex(AppColors.border),
    '--sn-border-strong': _cssHex(AppColors.border2),
    '--sn-accent': _cssHex(AppColors.accent),
    '--sn-accent-text': _cssHex(AppColors.accentFg),
    '--sn-accent-bg': _cssRgba(AppColors.accentBg),
    '--sn-ok': _cssHex(AppColors.ok),
    '--sn-warn': _cssHex(AppColors.run),
    '--sn-danger': _cssHex(AppColors.danger),
    '--sn-radius': '12px',
    '--sn-font': "'Inter', -apple-system, system-ui, sans-serif",
    '--sn-mono': "'JetBrains Mono', ui-monospace, monospace",
  };
  final css = ':root{${vars.entries.map((e) => '${e.key}:${e.value}').join(';')}}';
  return '''
(function () {
  var d = document, h = d.head || d.documentElement;
  var v = d.createElement('style'); v.textContent = ${jsonEncode(css)}; h.insertBefore(v, h.firstChild);
  if (!d.querySelector('link[data-sn-fonts]')) {
    var l = d.createElement('link'); l.rel = 'stylesheet'; l.setAttribute('data-sn-fonts', '');
    l.href = 'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap';
    h.appendChild(l);
  }
  var b = d.body; if (!b) return;
  var clear = function (c) { return c === 'rgba(0, 0, 0, 0)' || c === 'transparent'; };
  if (clear(getComputedStyle(b).backgroundColor) && clear(getComputedStyle(d.documentElement).backgroundColor)) {
    var s = d.createElement('style');
    s.textContent = ':root{color-scheme:${dark ? 'dark' : 'light'}}html,body{background:var(--sn-bg);color:var(--sn-text);margin:0}';
    h.appendChild(s);
  }
})();
''';
}

class ArtifactSkeleton extends StatefulWidget {
  const ArtifactSkeleton({super.key, this.fill = false});

  final bool fill;

  @override
  State<ArtifactSkeleton> createState() => _ArtifactSkeletonState();
}

class _ArtifactSkeletonState extends State<ArtifactSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final block = AppColors.surface2;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: widget.fill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Skeleton(width: 140, height: 14, radius: 6, color: block),
        const SizedBox(height: 14),
        Skeleton(height: 10, radius: 5, color: block),
        const SizedBox(height: 8),
        FractionallySizedBox(
            widthFactor: 0.8,
            child: Skeleton(height: 10, radius: 5, color: block)),
        const SizedBox(height: 16),
        if (widget.fill)
          Expanded(
              child: Skeleton(
                  height: double.infinity, radius: 12, color: AppColors.surface1))
        else
          Skeleton(height: 96, radius: 12, color: AppColors.surface1),
      ],
    );
    return Semantics(
      label: 'Loading',
      child: FadeTransition(
        opacity: Tween(begin: 0.55, end: 1.0).animate(
            CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ClipRect(child: body),
        ),
      ),
    );
  }
}

bool get canRenderMermaid => _canEmbedWeb;

class MermaidDiagram extends StatelessWidget {
  const MermaidDiagram({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final escaped = const HtmlEscape(HtmlEscapeMode.element).convert(code);
    final vars = jsonEncode({
      'darkMode': dark,
      'background': 'transparent',
      'fontFamily': "Inter, -apple-system, system-ui, sans-serif",
      'fontSize': '14px',
      'primaryColor': _cssHex(AppColors.surface2),
      'primaryTextColor': _cssHex(AppColors.fg1),
      'primaryBorderColor': _cssHex(AppColors.border2),
      'secondaryColor': _cssHex(AppColors.surface3),
      'tertiaryColor': _cssHex(AppColors.surface1),
      'lineColor': _cssHex(AppColors.fg3),
      'textColor': _cssHex(AppColors.fg2),
      'clusterBkg': _cssHex(AppColors.surface1),
      'clusterBorder': _cssHex(AppColors.border2),
      'edgeLabelBackground': _cssHex(AppColors.surface1),
      'noteBkgColor': _cssHex(AppColors.surface3),
      'noteTextColor': _cssHex(AppColors.fg1),
    });
    final html = '''<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;padding:0;background:transparent}
.mermaid{display:flex;justify-content:center;margin:0;padding:4px 0}
.mermaid svg{max-width:100%;height:auto}</style></head>
<body><pre class="mermaid">$escaped</pre>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<script>mermaid.initialize({startOnLoad:true,securityLevel:'strict',theme:'base',themeVariables:$vars});</script>
</body></html>''';
    return _InlineWebPage(key: ValueKey('mermaid:${code.hashCode}'), html: html);
  }
}

class _InlineWebPage extends StatefulWidget {
  const _InlineWebPage({super.key, this.uri, this.html});
  final Uri? uri;
  final String? html;

  String get cacheKey => uri?.toString() ?? 'html:${html.hashCode}';

  @override
  State<_InlineWebPage> createState() => _InlineWebPageState();
}

class _InlineWebPageState extends State<_InlineWebPage> {
  static const _report = """
(function () {
  if (window.__snippetHeight) return;
  window.__snippetHeight = true;
  var last = 0;
  function send() {
    var d = document.documentElement, b = document.body;
    var h = Math.ceil(Math.max(d.scrollHeight, b ? b.scrollHeight : 0, d.offsetHeight));
    if (h !== last) { last = h; SnippetHeight.postMessage(String(h)); }
  }
  new ResizeObserver(send).observe(document.documentElement);
  if (document.body) new ResizeObserver(send).observe(document.body);
  window.addEventListener('load', send);
  send();
})();
""";

  static const _wheel = """
(function () {
  if (window.__snippetWheel) return;
  window.__snippetWheel = true;
  window.addEventListener('wheel', function (e) {
    var dy = e.deltaY;
    if (Math.abs(e.deltaX) > Math.abs(dy) || dy === 0) return;
    for (var el = e.target; el && el.nodeType === 1 && el !== document.body && el !== document.documentElement; el = el.parentElement) {
      var oy = getComputedStyle(el).overflowY;
      if ((oy === 'auto' || oy === 'scroll') && el.scrollHeight > el.clientHeight + 1) {
        if ((dy < 0 && el.scrollTop > 0) || (dy > 0 && el.scrollTop + el.clientHeight < el.scrollHeight - 1)) return;
      }
    }
    e.preventDefault();
    var k = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? window.innerHeight : 1;
    SnippetScroll.postMessage(String(dy * k));
  }, { passive: false });
})();
""";

  static final _knownHeights = <String, double>{};

  late double _height = _knownHeights[widget.cacheKey] ?? 180;
  bool _ready = false;
  bool _finished = false;
  bool _measured = false;
  Timer? _settle;
  Timer? _giveUp;
  Timer? _heightThrottle;
  double? _pendingHeight;
  bool _onScreen = true;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position =
        Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_checkOnScreen);
      _position = position;
      _position?.addListener(_checkOnScreen);
    }
  }

  void _checkOnScreen() {
    final box = context.findRenderObject();
    final viewport = _position?.context.notificationContext?.findRenderObject();
    if (box is! RenderBox || viewport is! RenderBox || !box.attached || !viewport.attached) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final viewTop = viewport.localToGlobal(Offset.zero).dy;
    const margin = 600.0;
    final visible = top + box.size.height > viewTop - margin &&
        top < viewTop + viewport.size.height + margin;
    if (visible != _onScreen) setState(() => _onScreen = visible);
  }
  String _bg = '#000000';
  bool _dark = true;

  String get _theme => snippetPageTheme(_dark, _bg);

  late final WebViewController _controller = () {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('SnippetHeight', onMessageReceived: (m) {
        final h = double.tryParse(m.message);
        if (h == null || !mounted) return;
        final next = h.clamp(40.0, 6000.0);
        _measured = true;
        _knownHeights[widget.cacheKey] = next;
        _pendingHeight = next;
        if (!_ready) {
          if ((next - _height).abs() > 1) setState(() => _height = next);
          _scheduleReveal();
          return;
        }
        _heightThrottle ??= Timer(const Duration(milliseconds: 250), () {
          _heightThrottle = null;
          final target = _pendingHeight;
          if (mounted && target != null && (target - _height).abs() > 1) {
            setState(() => _height = target);
          }
        });
      })
      ..addJavaScriptChannel('SnippetScroll', onMessageReceived: (m) {
        final dy = double.tryParse(m.message);
        final p = _position;
        if (dy == null || p == null || !p.hasPixels) return;
        final delta = p.axisDirection == AxisDirection.up ? -dy : dy;
        final next =
            (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent);
        if (next != p.pixels) p.jumpTo(next);
      })
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          if (!_finished || !r.isMainFrame) return NavigationDecision.navigate;
          final u = Uri.tryParse(r.url);
          if (u == null || u.scheme == 'about' || u.scheme == 'data') {
            return NavigationDecision.navigate;
          }
          final same = widget.uri != null &&
              u.replace(fragment: '').toString() ==
                  widget.uri!.replace(fragment: '').toString();
          if (same) return NavigationDecision.navigate;
          launchUrl(u, mode: LaunchMode.externalApplication);
          return NavigationDecision.prevent;
        },
        onPageFinished: (_) {
          _controller.runJavaScript(_theme);
          _controller.runJavaScript(_report);
          if (!kMobile) _controller.runJavaScript(_wheel);
          _finished = true;
          _giveUp ??= Timer(const Duration(milliseconds: 2500), _reveal);
          _scheduleReveal();
        },
      ));
    if (!kMacOS) c.setBackgroundColor(Colors.transparent);
    final html = widget.html;
    if (html != null) return c..loadHtmlString(html);
    return c..loadRequest(widget.uri!);
  }();

  void _scheduleReveal() {
    if (_ready || !_finished || !_measured) return;
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 250), _reveal);
  }

  void _reveal() {
    if (_ready || !mounted) return;
    _settle?.cancel();
    _giveUp?.cancel();
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _settle?.cancel();
    _giveUp?.cancel();
    _heightThrottle?.cancel();
    _position?.removeListener(_checkOnScreen);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _bg = _cssHex(theme.scaffoldBackgroundColor);
    _dark = theme.brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      height: _height,
      child: Stack(children: [
        if (_onScreen)
          Positioned.fill(child: WebViewWidget(controller: _controller)),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _ready,
            child: AnimatedOpacity(
              opacity: _ready ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: ColoredBox(
                color: theme.scaffoldBackgroundColor,
                child: const ArtifactSkeleton(fill: true),
              ),
            ),
          ),
        ),
      ]),
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
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _n = widget.version;
    _load();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool latest = false, bool quiet = false}) async {
    try {
      final all = await widget.client.artifacts(widget.session);
      final found = all.where((a) => a.id == widget.id).firstOrNull;
      if (!mounted) return;
      final before = _artifact?.latest?.n;
      final after = found?.latest?.n;
      if (quiet && found != null && before == after) return;
      final follow = latest || _n == null || _n == before;
      setState(() {
        _artifact = found;
        _error = found == null ? 'This artifact is no longer available.' : null;
        if (follow) _n = after;
        _textFor = null;
      });
    } catch (e) {
      if (mounted && !quiet) setState(() => _error = '$e');
    }
  }

  Future<void> _download() async {
    final a = _artifact;
    final v = _version;
    if (a == null || v == null) return;
    if (a.kind != 'html' && a.kind != 'collection' && v.source.isNotEmpty) {
      final name = v.source.split('/').last;
      try {
        final msg = await downloadRemoteFileWithCancel(context, widget.client,
            path: v.source, name: name);
        if (msg != null && mounted) toast(context, msg);
        return;
      } catch (_) {
        if (!mounted) return;
      }
    }
    try {
      toast(context, 'Preparing ${a.title}…');
      final path = await widget.client.zipArtifact(widget.session, a.id, version: v.n);
      if (!mounted) return;
      final msg = await downloadRemoteFileWithCancel(context, widget.client,
          path: path, name: '${a.id}-v${v.n}.zip');
      if (msg != null && mounted) toast(context, msg);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  ArtifactVersion? get _version => _artifact?.version(_n ?? 0);

  bool get _hasSource => switch (_artifact?.kind) {
        'html' || 'markdown' || 'csv' || 'code' || 'svg' => true,
        'file' => _isText(_version?.entry ?? ''),
        _ => false,
      };

  Future<String> _textOf(ArtifactVersion v) {
    if (_textFor != v.url || _text == null) {
      _textFor = v.url;
      _text = widget.client.artifactText(v.url).then((t) => t.length >
              _maxTextChars
          ? '${t.substring(0, _maxTextChars)}\n\n… truncated, download for the full file'
          : t);
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

  Future<void> _more(BuildContext anchor) async {
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 220,
      items: [
        if (_hasSource)
          appMenuRow<String>(
              value: 'source',
              icon: _source ? 'eye' : 'code',
              label: _source ? 'Preview' : 'Source'),
        appMenuRow<String>(
            value: 'browser', icon: 'globe', label: 'Open in browser'),
        appMenuRow<String>(
            value: 'latest', icon: 'refresh', label: 'Latest version'),
      ],
    );
    if (!mounted) return;
    switch (picked) {
      case 'source':
        setState(() => _source = !_source);
      case 'browser':
        _openInBrowser();
      case 'latest':
        _load(latest: true);
    }
  }

  Widget _mobileHeader() {
    final a = _artifact;
    final v = _version;
    final versions = a?.versions.length ?? 0;
    return Container(
      color: AppColors.surface1,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: AppColors.border2,
            borderRadius: BorderRadius.circular(R.pill),
          ),
        ),
        Row(children: [
          IconBtn('x',
              size: M.minTarget,
              iconSize: 20,
              tooltip: 'Close',
              onTap: widget.onClose),
          const SizedBox(width: 2),
          Expanded(
            child: Text(a?.title ?? 'Artifact',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(17, weight: W.strong, color: AppColors.fg1)),
          ),
          if (v != null)
            Builder(
              builder: (anchor) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: versions > 1 ? () => _pickVersion(anchor) : null,
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  margin: const EdgeInsets.only(left: 6, right: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('v${v.n}', style: TS.meta(AppColors.fg2)),
                    if (versions > 1) ...[
                      const SizedBox(width: 3),
                      AppIcon('chevron-down', size: 12, color: AppColors.fg3),
                    ],
                  ]),
                ),
              ),
            ),
          IconBtn('download',
              size: M.minTarget,
              iconSize: 19,
              tooltip: 'Download',
              onTap: _download),
          Builder(
            builder: (anchor) => IconBtn('more-horizontal',
                size: M.minTarget,
                iconSize: 19,
                tooltip: 'More',
                onTap: () => _more(anchor)),
          ),
        ]),
      ]),
    );
  }

  Widget _header() {
    if (kMobile) return _mobileHeader();
    final a = _artifact;
    final v = _version;
    return Container(
      padding: EdgeInsets.fromLTRB(16, kMobile ? 8 : 12, 8, 10),
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
        IconBtn('download',
            size: 32, iconSize: 15, tooltip: 'Download', onTap: _download),
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

  Widget _fileCard(ArtifactInfo a, ArtifactVersion v) {
    final name = (v.source.isNotEmpty ? v.source : v.entry).split('/').last;
    final ext = _ext(name);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(20),
            ),
            child: AppIcon(
                ext == 'pdf'
                    ? 'file-text'
                    : ext == 'apk' || ext == 'zip' || ext == 'gz'
                        ? 'file-archive'
                        : 'file',
                size: 28,
                color: AppColors.fg2),
          ),
          const SizedBox(height: 16),
          Text(name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(16, weight: W.label, color: AppColors.fg1)),
          const SizedBox(height: 4),
          Text(ext.isEmpty ? 'File' : '${ext.toUpperCase()} file',
              style: sans(13, color: AppColors.fg3)),
          const SizedBox(height: 22),
          Btn('Download', icon: 'download', onTap: _download),
          const SizedBox(height: 8),
          Btn('Open in browser',
              icon: 'external-link',
              variant: BtnVariant.ghost,
              onTap: _openInBrowser),
        ]),
      ),
    );
  }

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
                  data: text,
                  styleSheet: markdownStyle(context),
                  builders: {'pre': PreBlockBuilder()},
                  onTapLink: (_, href, __) => openMarkdownLink(href, context)),
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
        return _sourceView(v);
      case 'file':
        if (_isText(v.entry)) return _sourceView(v);
        return _fileCard(a, v);
      case 'pdf':
        if (defaultTargetPlatform == TargetPlatform.android) {
          return _fileCard(a, v);
        }
        continue web;
      web:
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
      color: kMobile ? AppColors.bg : Colors.transparent,
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
  String _page = '';
  int _progress = 0;
  String? _failed;
  Timer? _slow;
  late final WebViewController _controller = () {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _route,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageFinished: (_) {
          _slow?.cancel();
          if (mounted) setState(() => _progress = 100);
          _controller.runJavaScript(_page);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == false || !mounted) return;
          setState(() => _failed = e.description);
        },
      ));
    if (!kMacOS) c.setBackgroundColor(Colors.white);
    return c..loadRequest(widget.uri);
  }();

  @override
  void initState() {
    super.initState();
    _slow = Timer(const Duration(seconds: 20), () {
      if (mounted && _progress < 100) {
        setState(() => _failed = 'This page is taking too long to load.');
      }
    });
  }

  @override
  void dispose() {
    _slow?.cancel();
    super.dispose();
  }

  NavigationDecision _route(NavigationRequest r) {
    final u = Uri.tryParse(r.url);
    if (u == null) return NavigationDecision.prevent;
    if (u.scheme == 'about' || u.scheme == 'data' || u.scheme == 'blob') {
      return NavigationDecision.navigate;
    }
    final sameOrigin = u.scheme == widget.uri.scheme &&
        u.host == widget.uri.host &&
        u.port == widget.uri.port;
    final ext = _ext(u.path);
    if (sameOrigin && (ext.isEmpty || _webExts.contains(ext))) {
      return NavigationDecision.navigate;
    }
    if (!r.isMainFrame) return NavigationDecision.navigate;
    launchUrl(u, mode: LaunchMode.externalApplication);
    return NavigationDecision.prevent;
  }

  void _retry() {
    setState(() {
      _failed = null;
      _progress = 0;
    });
    _controller.loadRequest(widget.uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _page = snippetPageTheme(theme.brightness == Brightness.dark,
        _cssHex(theme.scaffoldBackgroundColor));
    if (_failed != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_failed!,
                textAlign: TextAlign.center,
                style: sans(13, color: AppColors.fg3, height: 1.5)),
            const SizedBox(height: 14),
            Btn('Retry', icon: 'refresh', small: true, onTap: _retry),
            const SizedBox(height: 6),
            Btn('Open in browser',
                icon: 'external-link',
                small: true,
                variant: BtnVariant.ghost,
                onTap: () => launchUrl(widget.uri,
                    mode: LaunchMode.externalApplication)),
          ]),
        ),
      );
    }
    return Stack(children: [
      Positioned.fill(child: WebViewWidget(controller: _controller)),
      if (_progress < 100)
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: LinearProgressIndicator(
            value: _progress == 0 ? null : _progress / 100,
            minHeight: 2,
            backgroundColor: Colors.transparent,
            color: AppColors.accent,
          ),
        ),
    ]);
  }
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
      color: kMobile ? AppColors.bg : Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (kMobile)
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
              ),
            ),
          if (!ShellPanelRoot.inPanel(context))
          Container(
            padding: EdgeInsets.fromLTRB(16, kMobile ? 8 : 12, 8, 10),
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
            child: _error != null
                ? EmptyState(icon: 'alert-triangle', title: 'Couldn\'t load artifacts', body: _error)
                : artifacts == null
                    ? Center(child: Spinner(size: 16, color: AppColors.fg3))
                    : artifacts.isEmpty && files.isEmpty
                        ? const EmptyState(
                            icon: 'layers',
                            title: 'Nothing shared yet',
                            body: 'Artifacts and files the agent hands over in this chat collect here.',
                          )
                        : !kMobile
                        ? ArtifactGrid(
                            client: widget.client,
                            session: widget.session,
                            artifacts: artifacts,
                            files: files,
                            onOpenFileTab: widget.onOpenFileTab,
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                            children: [
                              if (artifacts.isNotEmpty) ...[
                                _section('Artifacts · ${artifacts.length}'),
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
                              ],
                              if (files.isNotEmpty) ...[
                                _section('Files · ${files.length}'),
                                for (final f in files)
                                  PresentedFileCard(
                                    client: widget.client,
                                    path: f.path,
                                    caption: f.caption,
                                    onOpenFileTab: widget.onOpenFileTab,
                                  ),
                              ],
                            ],
                          ),
          ),
        ]),
      ),
    );
  }
}
