import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'platform.dart';
import 'screens/file_viewer.dart';
import 'theme.dart';
import 'tool_sheet.dart';
import 'widgets.dart';

/// The daemon a subtree talks to, so media deep in the transcript (tool
/// panels, message attachments) can load files without threading a client
/// through every row.
class DaemonScope extends InheritedWidget {
  final DaemonClient client;

  /// Opens a file in a tab (desktop), when the host has tabs.
  final void Function(String path, String name)? onOpenFile;

  /// Shows a tool batch in the desktop side pane, when the host has one.
  final void Function(ValueListenable<ToolBatch> batch)? onOpenTools;
  const DaemonScope({
    super.key,
    required this.client,
    this.onOpenFile,
    this.onOpenTools,
    required super.child,
  });

  static DaemonClient? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DaemonScope>()?.client;

  static DaemonScope? scopeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DaemonScope>();

  @override
  bool updateShouldNotify(DaemonScope old) =>
      old.client != client ||
      old.onOpenFile != onOpenFile ||
      old.onOpenTools != onOpenTools;
}

/// What a file is, for choosing its preview and icon.
enum MediaKind { image, audio, video, pdf, archive, code, text, other }

MediaKind mediaKindOf(String path) {
  final ext =
      path.split('.').length > 1 ? path.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'bmp' ||
    'heic' ||
    'svg' =>
      MediaKind.image,
    'aac' ||
    'flac' ||
    'm4a' ||
    'mp3' ||
    'oga' ||
    'ogg' ||
    'opus' ||
    'wav' ||
    'webm' =>
      MediaKind.audio,
    'mp4' || 'mov' || 'mkv' || 'avi' || 'm4v' => MediaKind.video,
    'pdf' => MediaKind.pdf,
    'zip' ||
    'tar' ||
    'gz' ||
    'tgz' ||
    'bz2' ||
    'xz' ||
    '7z' ||
    'rar' =>
      MediaKind.archive,
    'rs' ||
    'dart' ||
    'ts' ||
    'tsx' ||
    'js' ||
    'jsx' ||
    'py' ||
    'go' ||
    'java' ||
    'kt' ||
    'swift' ||
    'c' ||
    'h' ||
    'cpp' ||
    'rb' ||
    'php' ||
    'sh' ||
    'json' ||
    'yaml' ||
    'yml' ||
    'toml' ||
    'html' ||
    'css' ||
    'sql' =>
      MediaKind.code,
    'txt' || 'md' || 'log' || 'csv' || 'rtf' => MediaKind.text,
    _ => MediaKind.other,
  };
}

String _iconFor(MediaKind kind) => switch (kind) {
      MediaKind.image => 'image',
      MediaKind.audio => 'music',
      MediaKind.video => 'film',
      MediaKind.pdf => 'pdf',
      MediaKind.archive => 'archive',
      MediaKind.code => 'file-code',
      MediaKind.text => 'file-text',
      MediaKind.other => 'file',
    };

String baseName(String path) {
  final parts = path.split('/').where((p) => p.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

/// An attachment the user sent, parsed from the marker the client appends.
class SentAttachment {
  final String path;
  final MediaKind kind;
  const SentAttachment(this.path, this.kind);
}

final RegExp _markerRe =
    RegExp(r'\[attached (image|file)(?: —[^\]/]*)?:?\s*(/[^\]]+)\]');

List<SentAttachment> parseSentAttachments(String text) => [
      for (final m in _markerRe.allMatches(text))
        SentAttachment(
          m.group(2)!.trim(),
          m.group(1) == 'image'
              ? MediaKind.image
              : mediaKindOf(m.group(2)!.trim()),
        ),
    ];

/// Open a file the way the platform wants: on desktop in a tab next to the
/// session (like any other file), on phones images in the full-screen viewer
/// and everything else in the file viewer.
void openMedia(BuildContext context, DaemonClient client, String path) {
  final openTab = DaemonScope.scopeOf(context)?.onOpenFile;
  if (!kMobile && openTab != null) {
    openTab(path, baseName(path));
    return;
  }
  if (mediaKindOf(path) == MediaKind.image) {
    showImageViewer(context, client: client, path: path);
    return;
  }
  pushFileViewerRoute(context,
      client: client, path: path, name: baseName(path));
}

/// A rounded image thumbnail with a quiet placeholder while it loads and a
/// clear state when it can't. Tapping opens the image viewer.
class ImageThumb extends StatelessWidget {
  final DaemonClient client;
  final String path;
  final double width;
  final double height;
  final BoxFit fit;
  const ImageThumb({
    super.key,
    required this.client,
    required this.path,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final placeholder = ColoredBox(
      color: AppColors.surface2,
      child: Center(child: AppIcon('image', size: 18, color: AppColors.fg4)),
    );
    return Semantics(
      image: true,
      label: baseName(path),
      button: true,
      child: GestureDetector(
        onTap: () => openMedia(context, client, path),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image(
            image: ResizeImage.resizeIfNeeded(
              (width * dpr).round(),
              null,
              client.imageProvider(path),
            ),
            fit: fit,
            gaplessPlayback: true,
            frameBuilder: (_, child, frame, sync) =>
                sync || frame != null ? child : placeholder,
            errorBuilder: (_, __, ___) => ColoredBox(
              color: AppColors.surface2,
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon('image', size: 18, color: AppColors.fg4),
                  if (height >= 72) ...[
                    const SizedBox(height: 4),
                    Text('Unavailable', style: sans(11, color: AppColors.fg4)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Images laid out for a message: one image large, several as a tidy grid.
class ImageGallery extends StatelessWidget {
  final DaemonClient client;
  final List<String> paths;
  final double maxWidth;
  const ImageGallery({
    super.key,
    required this.client,
    required this.paths,
    this.maxWidth = 280,
  });

  @override
  Widget build(BuildContext context) {
    if (paths.length == 1) {
      return ImageThumb(
          client: client,
          path: paths.first,
          width: maxWidth.clamp(0, 260),
          height: 180);
    }
    const gap = 6.0;
    final columns = paths.length == 2 || paths.length == 4 ? 2 : 3;
    final side = ((maxWidth.clamp(0, 280) - gap * (columns - 1)) / columns)
        .floorToDouble();
    return SizedBox(
      width: side * columns + gap * (columns - 1),
      child: Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final path in paths)
            ImageThumb(client: client, path: path, width: side, height: side),
        ],
      ),
    );
  }
}

/// A file as a compact card: its kind, its name and a type label. Tapping opens it.
class FileChip extends StatelessWidget {
  final DaemonClient? client;
  final String path;
  final String? name;
  final VoidCallback? onTap;
  final Widget? trailing;
  const FileChip({
    super.key,
    required this.path,
    this.client,
    this.name,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final kind = mediaKindOf(path);
    final label = name ?? baseName(path);
    final ext =
        label.contains('.') ? label.split('.').last.toUpperCase() : 'FILE';
    final tap = onTap ??
        (client == null ? null : () => openMedia(context, client!, path));
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: kind == MediaKind.pdf
                    ? AppColors.dangerBg
                    : AppColors.surface3,
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: AppIcon(_iconFor(kind),
                  size: 15,
                  color:
                      kind == MediaKind.pdf ? AppColors.danger : AppColors.fg2),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, weight: W.label, color: AppColors.fg1)),
                  Text(ext.length > 6 ? 'FILE' : ext,
                      style: mono(10, color: AppColors.fg3)),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
        ),
      ),
    );
  }
}

/// A voice note: play/pause, progress and time, with its transcript beneath.
/// The audio is only fetched when first played, so a long chat full of voice
/// notes costs nothing until one is opened.
class VoiceNote extends StatefulWidget {
  final DaemonClient client;
  final String path;
  final Widget? transcript;
  const VoiceNote(
      {super.key, required this.client, required this.path, this.transcript});

  @override
  State<VoiceNote> createState() => _VoiceNoteState();
}

class _VoiceNoteState extends State<VoiceNote> {
  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _playing = false;
  bool _loading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  Future<void> _toggle() async {
    final player = _player ?? _attach();
    try {
      if (_playing) {
        await player.pause();
      } else if (player.state == PlayerState.paused) {
        await player.resume();
      } else {
        setState(() => _loading = true);
        await player.play(UrlSource(widget.client.fileUrl(widget.path)));
      }
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't play this voice note");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  AudioPlayer _attach() {
    final player = AudioPlayer();
    _subs
      ..add(player.onPlayerStateChanged.listen((s) {
        if (!mounted) return;
        setState(() {
          _playing = s == PlayerState.playing;
          if (s == PlayerState.completed) _position = Duration.zero;
        });
      }))
      ..add(player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      }))
      ..add(player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      }));
    return _player = player;
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  static String _clock(Duration d) {
    final s = d.inSeconds.clamp(0, 359999);
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds;
    final progress =
        total <= 0 ? 0.0 : (_position.inMilliseconds / total).clamp(0.0, 1.0);
    final time = _duration == Duration.zero
        ? 'Voice note'
        : '${_clock(_position)} / ${_clock(_duration)}';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Semantics(
              button: true,
              label: _playing ? 'Pause voice note' : 'Play voice note',
              child: InkWell(
                onTap: _error == null ? _toggle : null,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: _loading
                      ? Spinner(size: 14, color: AppColors.accentFg)
                      : AppIcon(_playing ? 'pause' : 'play',
                          size: 15, color: AppColors.accentFg),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 180,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(R.pill),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: AppColors.surface3,
                        valueColor: AlwaysStoppedAnimation(AppColors.accent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(_error ?? time,
                      style: sans(11,
                          tabular: true,
                          color: _error == null
                              ? AppColors.fg3
                              : AppColors.danger)),
                ],
              ),
            ),
          ]),
          if (widget.transcript != null) ...[
            const SizedBox(height: 6),
            widget.transcript!,
          ],
        ],
      ),
    );
  }
}

/// Full-screen image viewer: black backdrop, pinch to zoom, tap or swipe down
/// to close.
Future<void> showImageViewer(
  BuildContext context, {
  required DaemonClient client,
  required String path,
}) {
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black,
    transitionDuration: Motion.fast,
    reverseTransitionDuration: Motion.quick,
    pageBuilder: (_, __, ___) => _ImageViewer(client: client, path: path),
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  ));
}

class _ImageViewer extends StatefulWidget {
  final DaemonClient client;
  final String path;
  const _ImageViewer({required this.client, required this.path});

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  final TransformationController _zoom = TransformationController();
  double _dragY = 0;

  bool get _zoomed => _zoom.value.getMaxScaleOnAxis() > 1.01;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final fade = (1 - (_dragY.abs() / 400)).clamp(0.3, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: fade),
      body: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            onVerticalDragUpdate:
                _zoomed ? null : (d) => setState(() => _dragY += d.delta.dy),
            onVerticalDragEnd: _zoomed
                ? null
                : (d) {
                    if (_dragY.abs() > 120 ||
                        (d.primaryVelocity ?? 0).abs() > 900) {
                      Navigator.of(context).pop();
                    } else {
                      setState(() => _dragY = 0);
                    }
                  },
            child: Transform.translate(
              offset: Offset(0, _dragY),
              child: InteractiveViewer(
                transformationController: _zoom,
                minScale: 1,
                maxScale: 6,
                onInteractionEnd: (_) => setState(() {}),
                child: Center(
                  child: Image(
                    image: ResizeImage.resizeIfNeeded(
                      (size.width * dpr).round().clamp(720, 2400),
                      null,
                      widget.client.imageProvider(widget.path),
                    ),
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                    errorBuilder: (_, __, ___) => Text("Can't load this image",
                        style: sans(13, color: Colors.white70)),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(children: [
                Expanded(
                  child: Text(baseName(widget.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, weight: W.label, color: Colors.white)),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const AppIcon('x', size: 20, color: Colors.white),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Pasted text as it travels in a message: inline, so the agent reads it
/// directly, between markers the transcript collapses into a card.
String pastedTextBlock(String text) {
  final body = text.trimRight();
  final lines = '\n'.allMatches(body).length + 1;
  return '[pasted text — $lines lines]\n$body\n[/pasted text]';
}

final RegExp _pastedRe = RegExp(
  r'\[pasted text — \d+ lines?\]\n([\s\S]*?)\n\[/pasted text\]',
);

/// The pasted blocks in [text], and the text with them removed.
(List<String>, String) splitPastedBlocks(String text) {
  final blocks = [for (final m in _pastedRe.allMatches(text)) m.group(1)!];
  return (blocks, text.replaceAll(_pastedRe, '').trim());
}

/// A pasted block in the transcript: collapsed to a few lines with its size,
/// expandable to the full text, with copy.
class PastedTextCard extends StatefulWidget {
  final String text;
  const PastedTextCard({super.key, required this.text});

  @override
  State<PastedTextCard> createState() => _PastedTextCardState();
}

class _PastedTextCardState extends State<PastedTextCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final lines = widget.text.split('\n');
    final preview = lines.take(3).join('\n');
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(R.card)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(children: [
                AppIcon('file-text', size: 14, color: AppColors.fg3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pasted text · ${lines.length} ${lines.length == 1 ? 'line' : 'lines'}',
                    style: sans(12, weight: W.label, color: AppColors.fg2),
                  ),
                ),
                Tooltip(
                  message: 'Copy',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(R.sm),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: widget.text));
                      if (context.mounted) toast(context, 'Copied');
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: AppIcon('copy', size: 13, color: AppColors.fg3),
                    ),
                  ),
                ),
                AppIcon(_open ? 'chevron-up' : 'chevron-down',
                    size: 14, color: AppColors.fg3),
                const SizedBox(width: 6),
              ]),
            ),
          ),
          Container(height: 1, color: AppColors.border),
          AnimatedSize(
            duration: Motion.fast,
            curve: Motion.enter,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: _open
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: SingleChildScrollView(
                        child: SelectableText(widget.text,
                            style:
                                mono(12, height: 1.45, color: AppColors.fg1)),
                      ),
                    )
                  : Text(
                      lines.length > 3 ? '$preview\n…' : preview,
                      maxLines: 4,
                      overflow: TextOverflow.fade,
                      style: mono(12, height: 1.45, color: AppColors.fg2),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
