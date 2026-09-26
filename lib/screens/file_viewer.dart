import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../desktop_pick.dart';
import '../file_actions.dart';
import '../highlight.dart';
import '../models.dart';
import '../notifications.dart';
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'editor.dart';

/// The surface a phone can show. `onOpenFile` opens the file as a shell TAB,
/// which is a desktop concept: the phone shell renders `_activeTab`, and a file
/// tab is AUXILIARY, so `_activeTab` skips it and `_mobileShell` never draws it.
/// Honouring that callback on a phone therefore pushed a view the phone does not
/// render, and tapping a file appeared to do nothing.
///
/// Shared so a file reached from the browser and one reached from an agent's
/// `present_file` card cannot diverge — the card called the tab callback
/// directly and so kept the old, dead behaviour after the browser was fixed.
Future<void> pushFileViewerRoute(
  BuildContext context, {
  required DaemonClient client,
  required String path,
  required String name,
}) {
  return Navigator.of(context).push(PageRouteBuilder<void>(
    transitionDuration: Motion.fast,
    reverseTransitionDuration: Motion.quick,
    pageBuilder: (_, animation, __) => FileViewer(
      client: client,
      path: path,
      name: name,
      onClose: () => Navigator.of(context).pop(),
    ),
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.025, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Motion.enter,
        )),
        child: child,
      ),
    ),
  ));
}

/// Open a file for viewing, choosing the surface the CURRENT platform can show.
///
/// Returns true when this handled the open (a phone route was pushed); false
/// means the caller should run its own desktop path — a shell tab, or a panel.
///
/// Phones MUST take the route. `onOpenFileTab` creates a shell TAB, and the
/// phone shell renders `_activeTab`, which skips auxiliary tabs — so a file tab
/// is never drawn and the tap appears to do nothing. Both the file browser and
/// the agent's `present_file` card got this wrong by calling the tab callback
/// directly, so the decision lives in ONE place and a third call site cannot
/// repeat it.
bool openFileForViewing(
  BuildContext context, {
  required DaemonClient client,
  required String path,
  required String name,
}) {
  if (!kMobile) return false;
  pushFileViewerRoute(context, client: client, path: path, name: name);
  return true;
}

/// Read-only viewer for one file.
class FileViewer extends StatefulWidget {
  final DaemonClient client;
  final String path;
  final String name;
  final VoidCallback? onClose;

  /// When true (desktop/shell tab), the window already has a tab strip —
  /// skip the in-pane title bar and put download/edit on a thin action row.
  final bool embedded;
  const FileViewer(
      {super.key,
      required this.client,
      required this.path,
      required this.name,
      this.onClose,
      this.embedded = false});
  @override
  State<FileViewer> createState() => _FileViewerState();
}

class _FileViewerState extends State<FileViewer> {
  final CodeLineEditingController _controller = CodeLineEditingController();
  FileContent? _f;
  bool _loading = true;
  bool _downloading = false;
  String? _error;

  static const _imageExts = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
    'avif'
  };
  static const _videoExts = {'mp4', 'm4v', 'mov', 'webm', 'mkv', 'avi'};
  static const _audioExts = {'mp3', 'm4a', 'wav', 'ogg', 'flac', 'aac'};
  String get _ext {
    final d = widget.name.lastIndexOf('.');
    return d >= 0 ? widget.name.substring(d + 1).toLowerCase() : '';
  }

  bool get _isImage => _imageExts.contains(_ext);
  bool get _isVideo => _videoExts.contains(_ext);
  bool get _isAudio => _audioExts.contains(_ext);
  bool get _isMedia => _isImage || _isVideo || _isAudio;

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final message = await downloadRemoteFileWithCancel(
        context,
        widget.client,
        path: widget.path,
        name: widget.name,
      );
      if (!mounted) return;
      setState(() => _downloading = false);
      if (message != null) toast(context, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      toast(context, '$e', danger: true);
    }
  }

  @override
  void initState() {
    super.initState();
    // Media renders straight from its streaming URL — no text read.
    if (_isMedia) {
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final f = await widget.client.readFile(widget.path);
      if (!mounted) return;
      if (!f.binary) _controller.text = f.content;
      setState(() {
        _f = f;
        _loading = false;
        _error = null;
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

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final f = _f;
    final actions = <Widget>[
      IconBtn('download',
          tooltip: 'Download', onTap: _downloading ? null : _download),
      if (!_isMedia && !(f?.binary ?? false))
        IconBtn('edit',
            tooltip: 'Edit',
            onTap: () => presentScreen(
                  context,
                  style: PanelStyle.dialog,
                  dismissible: false,
                  builder: (_, close) => EditorScreen(
                      client: widget.client,
                      path: widget.path,
                      name: widget.name,
                      onClose: close),
                ).then((_) => _load())),
    ];
    return Scaffold(
      backgroundColor: readingBg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          if (!widget.embedded)
            SnAppBar(
                title: widget.name,
                subtitle: widget.path,
                onBack: widget.onClose ?? () => Navigator.pop(context),
                actions: actions),
          if (_isImage)
            Expanded(
              child: ColoredBox(
                color: Colors.black,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: Center(
                    child: Image.network(
                      widget.client.fileUrl(widget.path),
                      cacheWidth: (MediaQuery.sizeOf(context).width *
                              MediaQuery.devicePixelRatioOf(context))
                          .round()
                          .clamp(720, 2048),
                      cacheHeight: (MediaQuery.sizeOf(context).height *
                              MediaQuery.devicePixelRatioOf(context))
                          .round()
                          .clamp(720, 2048),
                      filterQuality: FilterQuality.low,
                      fit: BoxFit.contain,
                      loadingBuilder: (ctx, child, prog) => prog == null
                          ? child
                          : Center(
                              child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: AppColors.fg3))),
                      errorBuilder: (ctx, e, st) => EmptyState(
                          icon: 'alert-triangle',
                          title: "Can't load image",
                          body: '$e'),
                    ),
                  ),
                ),
              ),
            )
          else if (_isVideo && !kWindows)
            Expanded(child: _VideoView(url: widget.client.fileUrl(widget.path)))
          else if (_isVideo)
            Expanded(
              child: EmptyState(
                  icon: 'film',
                  title: 'No video preview on Windows',
                  body:
                      'Download the file and play it with your media player.'),
            )
          // Audio streams from the same `/fs/download` URL the video player uses
          // (the daemon serves Range requests), so playback starts without
          // fetching the whole file first.
          else if (_isAudio)
            Expanded(
              child: _AudioView(
                url: widget.client.fileUrl(widget.path),
                name: widget.name,
              ),
            )
          else if (_loading)
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
                    icon: 'alert-triangle',
                    title: 'Failed to load',
                    body: _error!))
          else if (f!.binary)
            Expanded(
              child: Center(
                child: EmptyState(
                  icon: 'file',
                  title: widget.name,
                  body: '${formatBytes(f.size)} · can\'t preview this file.',
                  action: Btn(
                    _downloading ? 'Downloading…' : 'Download',
                    icon: 'download',
                    disabled: _downloading,
                    onTap: _download,
                  ),
                ),
              ),
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border))),
              child: Text(
                  '${f.content.split('\n').length} lines · ${formatBytes(f.size)}${f.truncated ? ' · truncated' : ''}',
                  style: mono(10, color: AppColors.fg3)),
            ),
            Expanded(
              child: CodeEditor(
                controller: _controller,
                readOnly: true,
                wordWrap: false,
                style: codeEditorStyle(widget.name),
                indicatorBuilder:
                    (context, editingController, chunkController, notifier) {
                  return Row(children: [
                    DefaultCodeLineNumber(
                        controller: editingController, notifier: notifier),
                    DefaultCodeChunkIndicator(
                        width: 20,
                        controller: chunkController,
                        notifier: notifier),
                  ]);
                },
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Streaming video player (chewie over video_player). Points at the daemon's
/// /fs/download URL, which serves a video content-type and Range requests — so
/// playback streams and seeks instead of downloading the whole file first.
class _VideoView extends StatefulWidget {
  final String url;
  const _VideoView({required this.url});
  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  VideoPlayerController? _vc;
  ChewieController? _chewie;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final vc = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        // Mix with other audio rather than demanding exclusive audio focus — so
        // playback isn't silently blocked when something else holds focus (e.g.
        // an active phone call).
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      // Surface a runtime playback error (decode/source failure) instead of a
      // dead play button — video_player reports these on the value, not as a throw.
      vc.addListener(_onValue);
      await vc.initialize();
      if (!mounted) {
        vc.dispose();
        return;
      }
      setState(() {
        _vc = vc;
        _chewie = ChewieController(
          videoPlayerController: vc,
          autoPlay: true, // a tapped video should just start
          looping: false,
          allowFullScreen: true,
          aspectRatio:
              vc.value.aspectRatio == 0 ? 16 / 9 : vc.value.aspectRatio,
          errorBuilder: (ctx, msg) => EmptyState(
              icon: 'alert-triangle', title: "Can't play video", body: msg),
          materialProgressColors: ChewieProgressColors(
            playedColor: AppColors.accent,
            handleColor: AppColors.accent,
            bufferedColor: AppColors.surface3,
            backgroundColor: AppColors.surface2,
          ),
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _onValue() {
    final vc = _vc;
    if (vc != null && vc.value.hasError && _error == null && mounted) {
      setState(() => _error = vc.value.errorDescription ?? 'playback error');
    }
  }

  @override
  void dispose() {
    _vc?.removeListener(_onValue);
    _chewie?.dispose();
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    if (_error != null) {
      return EmptyState(
          icon: 'alert-triangle', title: "Can't play video", body: _error!);
    }
    final ch = _chewie;
    if (ch == null) {
      return Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.fg3)));
    }
    // Chewie sizes the video from its own aspectRatio; letterbox on black.
    return ColoredBox(color: Colors.black, child: Chewie(controller: ch));
  }
}

/// Streaming audio player for a single file.
///
/// Deliberately its own surface rather than reusing the video player: there is
/// no picture to letterbox, so the whole pane is a transport — title, scrubber,
/// elapsed/total, play. Reuses `audioplayers`, which the composer already uses
/// for voice notes, so no new dependency.
class _AudioView extends StatefulWidget {
  final String url;
  final String name;
  const _AudioView({required this.url, required this.name});
  @override
  State<_AudioView> createState() => _AudioViewState();
}

class _AudioViewState extends State<_AudioView> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  bool _ready = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _posSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      // `setSourceUrl` primes the source without starting playback, so the pane
      // shows total time before the user hits play. Loading in `initState` also
      // means a bad URL surfaces an error here rather than on first tap.
      await _player.setSourceUrl(widget.url);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
      } else if (_player.state == PlayerState.paused) {
        await _player.resume();
      } else {
        await _player.play(UrlSource(widget.url));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  static String _clock(Duration d) {
    final s = d.inSeconds.clamp(0, 359999);
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    if (_error != null) {
      return EmptyState(
          icon: 'alert-triangle', title: "Can't play audio", body: _error!);
    }
    final total = _duration.inMilliseconds;
    final value = total <= 0
        ? 0.0
        : (_position.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: AppIcon('music', size: 30, color: AppColors.fg3),
          ),
          const SizedBox(height: 16),
          Text(widget.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: sans(14, weight: W.label, color: AppColors.fg1)),
          const SizedBox(height: 18),
          // Scrubber. Seek is only offered once a duration is known, so an
          // unseekable source cannot produce a dead control.
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.surface3,
              thumbColor: AppColors.accent,
              overlayColor: AppColors.accentBg,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value,
              onChanged: total <= 0
                  ? null
                  : (v) => setState(() {
                        _position = Duration(milliseconds: (total * v).round());
                      }),
              onChangeEnd: total <= 0
                  ? null
                  : (v) =>
                      _player.seek(Duration(milliseconds: (total * v).round())),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_clock(_position),
                    style: mono(10, color: AppColors.fg3)),
                Text(_clock(_duration),
                    style: mono(10, color: AppColors.fg3)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (!_ready && _error == null)
            // Not `const`: `AppColors.fg3` is a theme GETTER, not a compile-time
            // constant, so it cannot appear in a const expression.
            SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.fg3))
          else
            IconBtn(_playing ? 'pause' : 'play',
                size: 44,
                iconSize: 22,
                tooltip: _playing ? 'Pause' : 'Play',
                onTap: _toggle),
        ]),
      ),
    );
  }
}

Future<String?> downloadRemoteFileWithCancel(
  BuildContext context,
  DaemonClient client, {
  required String path,
  required String name,
}) {
  return downloadRemoteFile(context, client, path: path, name: name);
}

/// Download a remote daemon path to the device. Used by the file viewer and by
/// agent `present_file` cards in chat. Returns a short status message, or null
/// when a modal/notification already covered the outcome.
Future<String?> downloadRemoteFile(
  BuildContext context,
  DaemonClient client, {
  required String path,
  required String name,
  bool Function()? isCancelled,
}) async {
  var cancelled = false;
  final progressId = await notifyDownloadStarted(
    name,
    onCancel: () => cancelled = true,
  );
  final tempDir = await getTemporaryDirectory();
  final tempFile = File(
      '${tempDir.path}/snippet-download-${DateTime.now().microsecondsSinceEpoch}-$name');
  try {
    await client.downloadToFile(
      path,
      tempFile,
      onProgress: (received, total) {
        if (total != null && total > 0) {
          final percent = ((received * 100) ~/ total).clamp(0, 100);
          notifyDownloadProgress(progressId, name, percent);
        }
      },
      isCancelled: () => cancelled || (isCancelled?.call() ?? false),
    );

    if (kMobile) {
      final supportFile =
          File('${(await getApplicationSupportDirectory()).path}/$name');
      await supportFile.parent.create(recursive: true);
      await tempFile.copy(supportFile.path);
      Future<String?> shareIt() async {
        final res = await SharePlus.instance
            .share(ShareParams(files: [XFile(supportFile.path, name: name)]));
        return res.status == ShareResultStatus.success ? 'Saved $name' : null;
      }

      if (Platform.isAndroid) {
        var saved = false;
        try {
          await MediaStore.ensureInitialized();
          MediaStore.appFolder = 'Snippet';
          final info = await MediaStore().saveFile(
            tempFilePath: tempFile.path,
            dirType: DirType.download,
            dirName: DirName.download,
            relativePath: FilePath.root,
          );
          saved = info != null;
        } catch (_) {
          saved = false;
        }
        if (saved) {
          await notifyDownload(name, supportFile.path, id: progressId);
          if (context.mounted) {
            await _downloadDoneSheetFor(context, name, supportFile.path);
          }
          return null;
        }
        await notifyDownloadFailure(
            progressId, name, 'Could not save to Downloads; sharing instead.');
        return shareIt();
      }
      await notifyDownload(name, supportFile.path, id: progressId);
      return shareIt();
    }

    final saved = await saveLocalFile(
        fileName: name, bytes: await tempFile.readAsBytes());
    if (saved == null) return null;
    await notifyDownload(name, saved, id: progressId);
    return 'Downloaded $name';
  } on DownloadCancelled {
    await notifyDownloadCancelled(progressId);
    return 'Download cancelled.';
  } catch (e) {
    await notifyDownloadFailure(progressId, name, e);
    rethrow;
  } finally {
    unregisterDownloadCancel(progressId);
    try {
      if (await tempFile.exists()) await tempFile.delete();
    } catch (_) {}
  }
}

Future<void> _downloadDoneSheetFor(
    BuildContext context, String name, String path) async {
  void shareFile() {
    SharePlus.instance.share(ShareParams(files: [XFile(path, name: name)]));
  }

  final action = await showAppSheet<String>(context,
      title: 'Saved to Downloads',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: sans(13, height: 1.4, color: AppColors.fg2)),
          const SizedBox(height: 16),
          Btn('Open',
              icon: 'file',
              full: true,
              onTap: () => Navigator.pop(context, 'open')),
          const SizedBox(height: 8),
          Btn('Share',
              icon: 'upload',
              variant: BtnVariant.secondary,
              full: true,
              onTap: () => Navigator.pop(context, 'share')),
          const SizedBox(height: 4),
        ],
      ));
  if (action == 'open') {
    final opened = await openLocalFile(path);
    if (!opened) shareFile();
  } else if (action == 'share') {
    shareFile();
  }
}
