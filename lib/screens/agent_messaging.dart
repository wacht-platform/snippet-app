import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../api.dart';
import '../desktop_pick.dart';
import '../models.dart';
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Pick one agent from the directory, as an anchored DROPDOWN.
///
/// Returns null when dismissed. Shared by the composer's recipient picker and
/// the message sheet so both offer the same list, in the same order.
///
/// Mission Control is NOT offered. It is the coordinator, reached by opening its
/// own session, so listing it as a recipient elsewhere would be a second path to
/// the same place — and would let a message meant for a worker land on the
/// coordinator. Agents reach Mission Control through their own tools, not here.
Future<CoordinationAgent?> pickAgentId(
  BuildContext context,
  DaemonClient client, {
  String title = 'Select an agent',
  Set<String> exclude = const {},
  String? currentAgentId,
  BuildContext? anchor,
}) async {
  List<CoordinationAgent> agents;
  try {
    agents = await client.coordinationAgents();
  } catch (e) {
    if (context.mounted) toast(context, '$e', danger: true);
    return null;
  }
  final candidates = agents
      .where((a) =>
          !exclude.contains(a.id) &&
          // Mission Control is reached through its own chat, not picked here.
          // Offering it would let a message aimed at a worker land on the
          // coordinator.
          !a.isMissionControl)
      .toList();
  if (!context.mounted) return null;
  if (candidates.isEmpty) {
    toast(context, 'No agents available');
    return null;
  }
  candidates.sort((a, b) => a.displayName.compareTo(b.displayName));

  // A dropdown, the SAME control as the approval and inference pickers: an
  // anchored popover on desktop, a bottom sheet on mobile. A centered dialog
  // for a short list of destinations was heavier than the thing it replaced.
  final picked = await showAppMenu<String>(
    context,
    anchor: anchor ?? context,
    minWidth: 260,
    maxWidth: 340,
    items: [
      appMenuHeading<String>(title),
      for (final a in candidates)
        appMenuRow<String>(
          value: a.id,
          icon: 'agent',
          label: a.displayName.trim().isEmpty ? a.id : a.displayName,
          description: '${a.handle} · ${a.role} · ${a.status}',
          selected: a.id == currentAgentId,
        ),
    ],
  );
  if (picked == null) return null;
  for (final a in candidates) {
    if (a.id == picked) return a;
  }
  return null;
}

/// Message one agent from one session.
///
/// The sheet collects only what a human can decide — who, and what to say. It
/// sends a DIRECT MESSAGE carrying this session as its origin, so the agent
/// knows which session to reply in and which session to request dispatch on.
/// Nothing here creates work: dispatching belongs to Mission Control.
class AgentWorkSheet extends StatefulWidget {
  const AgentWorkSheet({
    super.key,
    required this.client,
    required this.sessionId,
    this.initialAgentId,
    this.workspaceLabel,
  });

  final DaemonClient client;

  /// The durable session the work lands in.
  final String sessionId;

  /// Pre-selected agent, when the sheet was opened from that agent's row.
  final String? initialAgentId;

  /// Shown as read-only context so the user can confirm the target workspace.
  final String? workspaceLabel;

  @override
  State<AgentWorkSheet> createState() => _AgentWorkSheetState();
}

class _AgentWorkSheetState extends State<AgentWorkSheet> {
  final _message = TextEditingController();

  String? _agentId;
  String? _agentName;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _agentId = widget.initialAgentId;
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final agents = await widget.client.coordinationAgents();
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Resolve a display name for a pre-selected agent; leave the choice
        // open otherwise.
        for (final a in agents) {
          if (a.id == _agentId) {
            _agentName = a.displayName.trim().isEmpty ? a.id : a.displayName;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _chooseAgent(BuildContext anchor) async {
    final picked = await pickAgentId(context, widget.client, anchor: anchor);
    if (picked == null || !mounted) return;
    setState(() {
      _agentId = picked.id;
      _agentName =
          picked.displayName.trim().isEmpty ? picked.id : picked.displayName;
    });
  }

  Future<void> _submit() async {
    final agentId = _agentId;
    if (agentId == null) {
      setState(() => _error = 'Choose an agent');
      return;
    }
    final message = _message.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Write a message');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.client.sendAgentMessage(
        toAgentId: agentId,
        body: message,
        // Ask FROM this session. The agent then knows which session to reply in
        // AND which session to request dispatch on — the whole reason this is a
        // message rather than a dispatch.
        originSession: widget.sessionId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // Keep the sheet and its input: a failed send must not cost the user what
      // they just typed.
      setState(() {
        _sending = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final workspace = widget.workspaceLabel?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (workspace.isNotEmpty) ...[
          Text('workspace', style: mono(10, color: AppColors.fg3)),
          const SizedBox(height: 4),
          Text(workspace,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: AppColors.fg2)),
          const SizedBox(height: 14),
        ],
        Text('agent', style: mono(10, color: AppColors.fg3)),
        const SizedBox(height: 4),
        Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.sm),
          child: Builder(
            builder: (ctx) => InkWell(
              onTap: _sending ? null : () => _chooseAgent(ctx),
              borderRadius: BorderRadius.circular(R.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              child: Row(children: [
                AppIcon('agent', size: 15, color: AppColors.fg3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_agentName ?? 'Choose an agent',
                      style: sans(13,
                          color: _agentName == null
                              ? AppColors.fg4
                              : AppColors.fg1)),
                ),
                AppIcon('chevron-down', size: 13, color: AppColors.fg4),
              ]),
            ),
          ),
        ),
        ),
        const SizedBox(height: 14),
        AppField(
          label: 'message',
          controller: _message,
          hint: 'What should this agent do?',
          minLines: 3,
          maxLines: 7,
          enabled: !_sending,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: sans(12, color: AppColors.danger)),
        ],
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: Btn('Cancel',
                variant: BtnVariant.ghost,
                full: true,
                disabled: _sending,
                onTap: () => Navigator.of(context).pop(false)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Btn(_sending ? 'Sending…' : 'Send',
                full: true,
                disabled: _sending,
                onTap: _submit),
          ),
        ]),
      ],
    );
  }
}

/// A direct conversation with one agent.
///
/// This is conversation, not work control: it shows what was said and lets the
/// user reply. A message never authorises a workspace change, so a chat cannot
/// silently start work.
class AgentThreadScreen extends StatefulWidget {
  const AgentThreadScreen({
    super.key,
    required this.client,
    required this.agentId,
    required this.agentName,
    this.subtitle,
    this.onClose,
    this.embedded = false,
  });

  final DaemonClient client;
  final String agentId;
  final String agentName;

  /// Identity line under the name (`@handle · role · status`). Supplied by the
  /// caller, which owns the agent record.
  final String? subtitle;

  final VoidCallback? onClose;

  /// Nested under a host that already draws `NavBackRow`.
  final bool embedded;

  @override
  State<AgentThreadScreen> createState() => _AgentThreadScreenState();
}

class _AgentThreadScreenState extends State<AgentThreadScreen> {
  static const _maxAttachments = 10;
  static const _maxRecordingDuration = Duration(minutes: 3);

  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<CoordinationEvent> _events = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _pollTimer;

  final List<_AgentAttachment> _attachments = [];
  int _attachmentGeneration = 0;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  StreamSubscription<Amplitude>? _amplitudeSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  Timer? _recordingTimer;

  bool _isRecording = false;
  String? _recordingPath;
  Uint8List? _recordingBytes;
  Duration _recordingElapsed = Duration.zero;
  Duration _playbackPosition = Duration.zero;
  bool _isPlayingRecording = false;
  final List<double> _waveform = [];

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && !_sending) {
        _load(silent: true);
      }
    });
    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlayingRecording = state == PlayerState.playing);
    });
    _positionSub = _audioPlayer.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _playbackPosition = position);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _amplitudeSub?.cancel();
    _recordingTimer?.cancel();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    if (_isRecording) {
      unawaited(_recorder.cancel());
    }
    if (kCanRecord) {
      unawaited(_recorder.dispose());
    }
    unawaited(_audioPlayer.dispose());
    final pendingPath = _recordingPath;
    if (pendingPath != null) {
      try {
        final f = File(pendingPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && _events.isEmpty) {
      setState(() => _loading = true);
    }
    try {
      final events = await widget.client.agentThread(peerId: widget.agentId);
      if (!mounted) return;
      final hadNew = events.length > _events.length;
      setState(() {
        _events = events;
        _loading = false;
        _error = null;
      });
      unawaitedMarkRead();
      if (hadNew) {
        _jumpToBottom(animated: silent);
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void unawaitedMarkRead() {
    widget.client.markAgentThreadRead(peerId: widget.agentId).catchError((_) {});
  }

  void _jumpToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        if (animated) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: Motion.fast,
            curve: Motion.enter,
          );
        } else {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      }
    });
  }

  Future<void> _onMicTap() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!kCanRecord) return;
    if (mounted) {
      setState(() {
        _isRecording = true;
        _recordingElapsed = Duration.zero;
        _waveform
          ..clear()
          ..add(0.08);
      });
    }
    final granted = kMobile
        ? (await Permission.microphone.request()).isGranted
        : await _recorder.hasPermission();
    if (!granted) {
      if (mounted) setState(() => _isRecording = false);
      if (mounted) {
        toast(
          context,
          kMobile
              ? 'Microphone permission is required.'
              : 'Microphone permission is required by macOS.',
          danger: true,
        );
        if (kMobile) {
          final status = await Permission.microphone.status;
          if (status.isPermanentlyDenied) await openAppSettings();
        }
      }
      return;
    }
    try {
      if (_recordingPath != null || _recordingBytes != null) {
        await _discardRecording();
      }
      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/snippet-agent-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (!await _recorder.isRecording()) {
        if (mounted) setState(() => _isRecording = false);
        if (mounted) toast(context, 'Could not start recording.', danger: true);
        return;
      }
      _amplitudeSub?.cancel();
      _amplitudeSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((a) {
        final level = ((a.current + 60) / 60).clamp(0.04, 1.0).toDouble();
        if (!mounted) return;
        setState(() {
          _waveform.add(level);
          if (_waveform.length > 180) _waveform.removeAt(0);
        });
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final next = _recordingElapsed + const Duration(seconds: 1);
        if (next >= _maxRecordingDuration) {
          setState(() => _recordingElapsed = _maxRecordingDuration);
          unawaited(_stopRecording());
          toast(context, 'Recording stopped at the 3-minute limit.');
        } else {
          setState(() => _recordingElapsed = next);
        }
      });
      if (mounted) setState(() => _recordingPath = path);
    } catch (e) {
      if (mounted) setState(() => _isRecording = false);
      if (mounted) toast(context, 'Could not start recording: $e', danger: true);
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    if (mounted) setState(() => _isRecording = false);
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      final stoppedPath = await _recorder.stop();
      final path = stoppedPath ?? _recordingPath;
      if (path == null) {
        if (mounted) toast(context, 'No recording was captured.');
        return;
      }
      final bytes = await _waitForRecordingFile(path);
      if (bytes == null || bytes.isEmpty) {
        await _discardRecording();
        if (mounted) toast(context, 'The recording was empty.');
        return;
      }
      if (mounted) {
        setState(() {
          _recordingPath = path;
          _recordingBytes = bytes;
        });
      } else {
        _recordingPath = path;
        _recordingBytes = bytes;
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not finish recording: $e', danger: true);
    }
  }

  Future<Uint8List?> _waitForRecordingFile(String path) async {
    final file = File(path);
    const attempts = 40;
    for (var i = 0; i < attempts; i++) {
      try {
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) return bytes;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  Future<void> _discardRecording() async {
    final path = _recordingPath;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingPath = null;
        _recordingBytes = null;
        _recordingElapsed = Duration.zero;
        _playbackPosition = Duration.zero;
        _waveform.clear();
        _isPlayingRecording = false;
      });
    }
  }

  Future<bool> _confirmRecording() async {
    final path = _recordingPath;
    final bytes = _recordingBytes;
    if (path == null && bytes == null) return false;
    try {
      if (bytes == null || bytes.isEmpty) {
        await _discardRecording();
        if (mounted) toast(context, 'The recording was empty.');
        return false;
      }
      await _ingest([
        (
          name: 'voice-${DateTime.now().microsecondsSinceEpoch}.m4a',
          localPath: null,
          readBytes: () async => bytes,
        )
      ]);
      await _audioPlayer.stop();
      if (path != null) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordingPath = null;
          _recordingBytes = null;
          _recordingElapsed = Duration.zero;
          _waveform.clear();
          _playbackPosition = Duration.zero;
          _isPlayingRecording = false;
        });
      }
      return true;
    } catch (e) {
      if (mounted) toast(context, 'Could not attach recording: $e', danger: true);
      return false;
    }
  }

  Future<void> _toggleRecordingPlayback() async {
    final path = _recordingPath;
    if (path == null || _isRecording) return;
    try {
      if (_isPlayingRecording) {
        await _audioPlayer.pause();
      } else if (_audioPlayer.state == PlayerState.paused) {
        await _audioPlayer.resume();
      } else {
        await _audioPlayer.play(DeviceFileSource(path));
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not play preview: $e', danger: true);
    }
  }

  String _audioTime(Duration d) {
    final seconds = d.inSeconds.clamp(0, 5999);
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  bool _isImageName(String n) {
    final l = n.toLowerCase();
    return const [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.heic',
      '.heif'
    ].any(l.endsWith);
  }

  Future<void> _onAttachTap() async {
    if (!kMobile) {
      await _pickFiles();
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Row(
            children: [
              _attachOption('camera', 'Camera', 'camera'),
              const SizedBox(width: 10),
              _attachOption('image', 'Photos', 'photos'),
              const SizedBox(width: 10),
              _attachOption('file', 'Files', 'files'),
            ],
          ),
        ),
      ),
    );
    if (choice == 'camera') {
      await _pickCamera();
    } else if (choice == 'photos') {
      await _pickPhotos();
    } else if (choice == 'files') {
      await _pickFiles();
    }
  }

  Widget _attachOption(String icon, String label, String value) {
    return Expanded(
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: () => Navigator.pop(context, value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon, size: 22, color: AppColors.fg2),
                const SizedBox(height: 8),
                Text(label, style: sans(12, color: AppColors.fg1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhotos() async {
    final xs = await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2200);
    if (xs.isEmpty) return;
    await _ingest(xs
        .map((x) => (name: x.name, localPath: x.path, readBytes: x.readAsBytes))
        .toList());
  }

  Future<void> _pickCamera() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.camera, imageQuality: 85, maxWidth: 2200);
    if (x == null) return;
    await _ingest([(name: x.name, localPath: x.path, readBytes: x.readAsBytes)]);
  }

  Future<void> _pickFiles() async {
    List<PickedLocalFile> files;
    try {
      files = await pickLocalFiles();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
      return;
    }
    if (files.isEmpty) return;
    await _ingest(files
        .map((f) => (
              name: f.name,
              localPath: f.path,
              readBytes: f.readAsBytes,
            ))
        .toList());
  }

  Future<void> _ingest(
      List<
              ({
                String name,
                String? localPath,
                Future<Uint8List> Function() readBytes
              })>
          picked) async {
    final remaining = _maxAttachments - _attachments.length;
    if (remaining <= 0) {
      toast(context, 'Max $_maxAttachments attachments reached.');
      return;
    }
    var items = picked;
    if (items.length > remaining) {
      items = items.take(remaining).toList();
      toast(context, 'Added $remaining (max $_maxAttachments).');
    }
    final entries = items
        .map((p) => _AgentAttachment(
              name: p.name,
              isImage: _isImageName(p.name),
              isAudio: isAudioAttachmentPath(p.name),
              localPath: p.localPath,
            ))
        .toList();
    if (entries.isEmpty) return;
    setState(() => _attachments.addAll(entries));
    final generation = _attachmentGeneration;
    for (var i = 0; i < entries.length; i++) {
      final p = items[i];
      final a = entries[i];
      try {
        final bytes = await p.readBytes();
        final path = await widget.client.uploadFile(bytes, name: p.name);
        if (!mounted || generation != _attachmentGeneration) return;
        setState(() {
          a.remotePath = path;
          a.uploading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _attachments.remove(a));
        toast(context, 'Upload failed: ${p.name}', danger: true);
      }
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    if (_isRecording) {
      await _stopRecording();
    }
    if (_recordingPath != null) {
      final ok = await _confirmRecording();
      if (!ok) return;
    }
    if (_attachments.any((a) => a.uploading)) {
      if (!mounted) return;
      toast(context, 'Please wait for attachments to upload');
      return;
    }
    final ready = _attachments.where((a) => a.remotePath != null).toList();
    final markers = ready
        .map((a) => a.isImage
            ? '[attached image — call read_image on this exact path to view it: ${a.remotePath}]'
            : '[attached file — read it at this exact path: ${a.remotePath}]')
        .toList();
    var body = _input.text.trim();
    if (markers.isNotEmpty) {
      body = body.isEmpty ? markers.join('\n\n') : '$body\n\n${markers.join('\n\n')}';
    }
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.client.sendAgentMessage(
        toAgentId: widget.agentId,
        body: body,
      );
      if (!mounted) return;
      _input.clear();
      _attachmentGeneration++;
      _attachments.clear();
      _discardRecording();
      setState(() => _sending = false);
      await _load(silent: true);
      _jumpToBottom(animated: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      toast(context, '$e', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wrapped in Material because presentScreen's non-rounded frames are plain
    // Containers — no Material ancestor — while a TextField and the icon buttons
    // here require one.
    final hideChrome = widget.embedded;
    return Material(
      color: readingBg,
      child: SafeArea(
        top: !hideChrome,
        bottom: false,
        child: Column(
          children: [
            if (!hideChrome) ...[
              _header(),
              Divider(height: 1, color: AppColors.border),
            ],
            Expanded(child: _body()),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final subtitle = widget.subtitle?.trim() ?? '';
    final canGoBack = widget.onClose != null || Navigator.of(context).canPop();
    return Container(
      height: M.appBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: AppColors.bg,
      child: Row(
        children: [
          if (canGoBack)
            IconBtn(
              'chevron-left',
              size: M.minTarget,
              iconSize: 20,
              tooltip: 'Back',
              onTap: () {
                if (widget.onClose != null) {
                  widget.onClose!();
                } else {
                  Navigator.of(context).maybePop();
                }
              },
            ),
          SizedBox(width: canGoBack ? 4 : 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.agentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      sans(M.sectionTitle, weight: W.label, color: AppColors.fg1),
                ),
                if (!kMobile && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(M.monoMeta, color: AppColors.fg3),
                  ),
                ],
              ],
            ),
          ),
          IconBtn(
            'refresh',
            size: M.minTarget,
            iconSize: 18,
            tooltip: 'Refresh',
            onTap: () => _load(silent: false),
          ),
          if (!kMobile && widget.onClose != null) ...[
            const SizedBox(width: 4),
            IconBtn(
              'x',
              size: M.minTarget,
              iconSize: 16,
              tooltip: 'Close',
              onTap: widget.onClose!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon('alert-circle', size: 24, color: AppColors.danger),
              const SizedBox(height: 10),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: sans(13, color: AppColors.danger)),
              const SizedBox(height: 14),
              Btn('Retry', small: true, onTap: () => _load(silent: false)),
            ],
          ),
        ),
      );
    }
    if (_events.isEmpty) {
      return RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.45,
              child: Center(
                child: EmptyState(
                  icon: 'message',
                  title: 'Chat with ${widget.agentName}',
                  body: 'Send a message to discuss tasks or coordinate work directly.',
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: () => _load(silent: true),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: _events.length,
        itemBuilder: (_, i) => _bubble(_events[i]),
      ),
    );
  }

  Widget _bubble(CoordinationEvent e) {
    // The local human is the only `human` actor, so everything else is the peer.
    final mine = e.actorKind == 'human';
    if (mine) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Bubble(mine: true, text: e.body),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon('agent', size: 12, color: AppColors.accent),
                const SizedBox(width: 5),
                Text(
                  widget.agentName,
                  style: sans(11, weight: W.label, color: AppColors.accent),
                ),
              ],
            ),
          ),
          Bubble(mine: false, text: e.body),
        ],
      ),
    );
  }

  Widget _recordingPanel() {
    final reviewing = !_isRecording && _recordingPath != null;
    final position = reviewing ? _playbackPosition : _recordingElapsed;
    final samples = List<double>.of(_waveform);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(children: [
        InkWell(
          onTap: _isRecording ? _stopRecording : _toggleRecordingPlayback,
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: AppIcon(
                _isRecording
                    ? 'stop'
                    : (_isPlayingRecording ? 'pause' : 'play'),
                size: 16,
                color: _isRecording ? AppColors.accent : AppColors.fg1,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(_audioTime(position),
            style: mono(11,
                color: _isRecording ? AppColors.accent : AppColors.fg3)),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 22,
            child: CustomPaint(painter: _WaveformPainter(samples)),
          ),
        ),
        if (reviewing) ...[
          IconBtn('x',
              size: 28,
              iconSize: 14,
              tooltip: 'Discard',
              onTap: _discardRecording),
          IconBtn('check',
              size: 28,
              iconSize: 14,
              tooltip: 'Use recording',
              onTap: () => unawaited(_confirmRecording())),
        ],
      ]),
    );
  }

  Widget _attachmentBar() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => _attachmentTile(_attachments[i]),
      ),
    );
  }

  Widget _attachmentTile(_AgentAttachment a) {
    final thumb = a.isImage && a.localPath != null;
    final isAudio = a.isAudio;
    final body = thumb
        ? ClipRRect(
            borderRadius: BorderRadius.circular(R.sm),
            child: Image.file(File(a.localPath!),
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                cacheWidth: 72,
                cacheHeight: 72),
          )
        : Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isAudio ? AppColors.accentBg : AppColors.surface2,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(isAudio ? 'mic' : (a.isImage ? 'image' : 'file'),
                  size: 12, color: isAudio ? AppColors.accent : AppColors.fg3),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 100),
                child: Text(a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(10,
                        color: isAudio ? AppColors.accent : AppColors.fg2)),
              ),
            ]),
          );
    return Stack(children: [
      body,
      if (a.uploading)
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(R.sm)),
            alignment: Alignment.center,
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.fg2)),
          ),
        ),
      Positioned(
        top: 3,
        right: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => setState(() => _attachments.remove(a)),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
                color: Colors.black87, shape: BoxShape.circle),
            child: AppIcon('x', size: 8, color: Colors.white),
          ),
        ),
      ),
    ]);
  }

  Widget _composer() {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    return AnimatedPadding(
      duration: Motion.fast,
      curve: Motion.enter,
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          kMobile ? M.gutter : (widget.embedded ? kComposerGutter : 20),
          8,
          kMobile ? M.gutter : (widget.embedded ? kComposerGutter : 20),
          10 + (keyboard > 0 ? 8 : mq.padding.bottom),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isRecording || _recordingPath != null) ...[
                _recordingPanel(),
                const SizedBox(height: 8),
              ],
              if (_attachments.isNotEmpty) ...[
                _attachmentBar(),
                const SizedBox(height: 6),
              ],
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter): () {
                    if (!kMobile) _send();
                  },
                  const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
                    _send();
                  },
                  const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
                    _send();
                  },
                },
                child: TextField(
                  controller: _input,
                  minLines: 2,
                  maxLines: 8,
                  cursorColor: AppColors.fg1,
                  onSubmitted: (_) {
                    if (!kMobile) _send();
                  },
                  style: sans(kMobile ? M.body : 16,
                      height: 1.45, color: AppColors.fg1),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.fromLTRB(2, 2, 8, 10),
                    border: InputBorder.none,
                    hintText: 'Message ${widget.agentName}…',
                    hintStyle: sans(kMobile ? M.body : 16,
                        height: 1.45, color: AppColors.fg4),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(R.sm),
                    child: InkWell(
                      onTap: _onAttachTap,
                      borderRadius: BorderRadius.circular(R.sm),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: AppIcon('plus', size: 18, color: AppColors.fg3),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(R.sm),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon('agent', size: 12, color: AppColors.fg3),
                        const SizedBox(width: 5),
                        Text(widget.agentName,
                            style: mono(11, color: AppColors.fg2)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (kCanRecord) ...[
                    Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(R.sm),
                      child: InkWell(
                        onTap: _onMicTap,
                        borderRadius: BorderRadius.circular(R.sm),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: AppIcon(
                            _isRecording ? 'mic-off' : 'mic',
                            size: 18,
                            color: _isRecording ? AppColors.danger : AppColors.fg3,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _input,
                    builder: (_, val, __) {
                      final canSend = (val.text.trim().isNotEmpty ||
                              _attachments.isNotEmpty ||
                              _isRecording ||
                              _recordingPath != null) &&
                          !_sending;
                      return _SendBtn(
                        enabled: canSend,
                        sending: _sending,
                        onTap: canSend ? _send : null,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendBtn extends StatelessWidget {
  final bool enabled;
  final bool sending;
  final VoidCallback? onTap;
  const _SendBtn({required this.enabled, this.sending = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final size = kMobile ? M.minTarget : 28.0;
    return Material(
      color: enabled ? AppColors.fg1 : AppColors.surface2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: sending
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: AppColors.bg,
                    ),
                  )
                : AppIcon('arrow-up',
                    size: 15,
                    color: enabled ? AppColors.bg : AppColors.fg4),
          ),
        ),
      ),
    );
  }
}

/// Open the message sheet for a session, reporting whether anything was sent so
/// the caller can refresh a roster or board.
Future<bool> showAgentWorkSheet(
  BuildContext context, {
  required DaemonClient client,
  required String sessionId,
  String? initialAgentId,
  String? workspaceLabel,
}) async {
  final done = await showAppSheet<bool>(
    context,
    title: 'Message an agent',
    child: AgentWorkSheet(
      client: client,
      sessionId: sessionId,
      initialAgentId: initialAgentId,
      workspaceLabel: workspaceLabel,
    ),
  );
  return done == true;
}

/// Open a direct conversation with one agent.
void openAgentThread(
  BuildContext context, {
  required DaemonClient client,
  required String agentId,
  required String agentName,
}) {
  if (kMobile) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AgentThreadScreen(
          client: client,
          agentId: agentId,
          agentName: agentName,
          onClose: () => Navigator.pop(context),
        ),
      ),
    );
    return;
  }
  presentScreen(
    context,
    style: PanelStyle.drawer,
    maxWidth: 720,
    maxHeight: 720,
    builder: (_, close) => AgentThreadScreen(
      client: client,
      agentId: agentId,
      agentName: agentName,
      onClose: close,
    ),
  );
}

class _AgentAttachment {
  final String name;
  final bool isImage;
  final bool isAudio;
  final String? localPath;
  String? remotePath;
  bool uploading;
  _AgentAttachment({
    required this.name,
    required this.isImage,
    required this.isAudio,
    this.localPath,
  }) : uploading = true;
}

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  const _WaveformPainter(this.samples);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (samples.isEmpty) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint..color = AppColors.fg4,
      );
      return;
    }
    final waveformWidth = math.min(size.width, samples.length * 4.0);
    for (var i = 0; i < samples.length; i++) {
      final amplitude = samples[i].clamp(0.04, 1.0).toDouble();
      final half =
          (size.height * 0.45 * amplitude).clamp(2.0, size.height * 0.45);
      final x = i * 4.0 + 2.0;
      if (x > waveformWidth) break;
      canvas.drawLine(
        Offset(x, size.height / 2 - half),
        Offset(x, size.height / 2 + half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.samples != samples;
}
