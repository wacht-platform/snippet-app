part of 'session.dart';

var _maxRecordingDuration = const Duration(minutes: 3);

String _limitLabel(Duration d) =>
    d.inSeconds % 60 == 0 ? '${d.inMinutes}-minute' : '${d.inSeconds}-second';

extension _SessionScreenRecorderExt on _SessionScreenState {
  Future<void> _onAttachTap() async {
    if (_maxAttachments - _attachments.length <= 0) {
      _toast('Up to $_maxAttachments attachments.');
      return;
    }
    if (!kMobile) {
      _pickFiles();
      return;
    }
    final choice = await showAppSheet<String>(context,
        title: 'Add context',
        child: Row(children: [
          _ctxOption('camera', 'Camera', 'camera'),
          const SizedBox(width: S.s8),
          _ctxOption('image', 'Photos', 'photos'),
          const SizedBox(width: S.s8),
          _ctxOption('file', 'Files', 'files'),
        ]));
    if (choice == 'camera') {
      _pickCamera();
    } else if (choice == 'photos') {
      _pickPhotos();
    } else if (choice == 'files') {
      _pickFiles();
    }
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
    // Flip the UI first so the tap feels instant; permission + encoder
    // setup still happen before audio is captured.
    if (mounted) {
      _setState(() {
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
      if (mounted) _setState(() => _isRecording = false);
      _toast(kMobile
          ? 'Microphone permission is required.'
          : 'Microphone permission is required by macOS.');
      if (kMobile) {
        final status = await Permission.microphone.status;
        if (status.isPermanentlyDenied) await openAppSettings();
      }
      return;
    }
    try {
      final voice =
          (await widget.client.getConfig().timeout(const Duration(seconds: 3)))
              .voice;
      if (!voice.enabled) {
        if (mounted) _setState(() => _isRecording = false);
        _toast('Voice notes are turned off in Settings → Voice.');
        return;
      }
      _maxRecordingDuration = Duration(seconds: voice.maxSeconds);
    } catch (_) {}
    try {
      // Starting a new take replaces an unconfirmed take only after the user
      // explicitly chose to record again.
      if (_recordingPath != null || _recordingBytes != null) {
        await _discardRecording();
      }
      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/snippet-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: kMobile ? 16000 : 44100,
          numChannels: 1,
        ),
        path: path,
      );
      if (!await _recorder.isRecording()) {
        await _recorder.cancel();
        if (mounted) _setState(() => _isRecording = false);
        _toast('Could not start recording.');
        return;
      }
      _amplitudeSub?.cancel();
      _amplitudeSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((a) {
        final level = ((a.current + 60) / 60).clamp(0.04, 1.0).toDouble();
        if (!mounted) return;
        _waveform.add(level);
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final next = _recordingElapsed + const Duration(seconds: 1);
        if (next >= _maxRecordingDuration) {
          _setState(() => _recordingElapsed = _maxRecordingDuration);
          unawaited(_stopRecording());
          _toast(
              'Recording stopped at the ${_limitLabel(_maxRecordingDuration)} limit.');
        } else {
          _recordingElapsed = next;
          _recorderTick.value++;
        }
      });
      if (mounted) _setState(() => _recordingPath = path);
    } catch (e) {
      if (mounted) _setState(() => _isRecording = false);
      _toast('Could not start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    if (mounted) _setState(() => _isRecording = false);
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      final stoppedPath = await _recorder.stop();
      final path = stoppedPath ?? _recordingPath;
      if (path == null) {
        _toast('No recording was captured.');
        return;
      }
      // macOS AVFoundation finishes the .m4a after stop() returns — wait
      // for the file instead of racing PathNotFoundException on attach.
      final bytes = await _waitForRecordingFile(path);
      if (bytes == null || bytes.isEmpty) {
        await _discardRecording();
        _toast('The recording was empty.');
        return;
      }
      if (mounted) {
        _setState(() {
          _recordingPath = path;
          _recordingBytes = bytes;
        });
      } else {
        _recordingPath = path;
        _recordingBytes = bytes;
      }
    } catch (e) {
      _toast('Could not finish recording: $e');
    }
  }

  /// Wait until [path] exists and is non-empty. AVCaptureAudioFileOutput on
  /// macOS writes the container asynchronously after stopRecording().
  Future<Uint8List?> _waitForRecordingFile(String path) async {
    final file =
        File(path.startsWith('file://') ? Uri.parse(path).toFilePath() : path);
    const attempts = 120; // ~6s
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

  Future<void> _toggleRecordingPlayback() async {
    final path = _recordingPath;
    if (path == null || _isRecording) return;
    try {
      if (_isPlayingRecording) {
        await _audioPlayer.pause();
      } else if (_audioPlayer.state == PlayerState.paused) {
        await _audioPlayer.resume();
      } else {
        await _audioPlayer.play(DeviceFileSource(path),
            position: _playbackPosition);
      }
    } catch (e) {
      _toast('Could not play recording: $e');
    }
  }

  Future<bool> _confirmRecording() async {
    final path = _recordingPath;
    var bytes = _recordingBytes;
    if ((path == null && bytes == null) ||
        _isRecording ||
        _confirmingRecording) {
      return false;
    }
    _confirmingRecording = true;
    // Clear immediately so a second confirm tap cannot race the first.
    _recordingPath = null;
    _recordingBytes = null;
    try {
      if (bytes == null || bytes.isEmpty) {
        if (path != null) bytes = await _waitForRecordingFile(path);
      }
      if (bytes == null || bytes.isEmpty) {
        await _discardRecording();
        _toast('The recording was empty.');
        return false;
      }
      await _ingest([
        (
          name: 'voice-${DateTime.now().microsecondsSinceEpoch}.m4a',
          localPath: null,
          readBytes: () async => bytes!,
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
        _setState(() {
          _waveform.clear();
          _playbackPosition = Duration.zero;
          _playbackDuration = Duration.zero;
          _isPlayingRecording = false;
        });
      }
      return true;
    } catch (e) {
      // Put the take back so a failed upload can be retried.
      _recordingPath = path;
      _recordingBytes = bytes;
      _toast('Could not attach recording: $e');
      return false;
    } finally {
      _confirmingRecording = false;
    }
  }

  Future<void> _discardRecording() async {
    final path = _recordingPath;
    if (_isRecording) {
      try {
        await _recorder.cancel();
      } catch (_) {}
    }
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
      _setState(() {
        _isRecording = false;
        _recordingPath = null;
        _recordingBytes = null;
        _recordingElapsed = Duration.zero;
        _playbackPosition = Duration.zero;
        _playbackDuration = Duration.zero;
        _waveform.clear();
        _isPlayingRecording = false;
      });
    }
  }

  String _audioTime(Duration d) {
    final seconds = d.inSeconds.clamp(0, 5999);
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  Widget _mobileRecorder(bool running) {
    final reviewing = !_isRecording && _recordingPath != null;
    final total = _playbackDuration > Duration.zero
        ? _playbackDuration
        : _recordingElapsed;
    final showPosition =
        reviewing && (_isPlayingRecording || _playbackPosition > Duration.zero);
    final time = !reviewing
        ? _audioTime(_recordingElapsed)
        : '${_audioTime(showPosition ? _playbackPosition : Duration.zero)} / ${_audioTime(total)}';
    final progress = !reviewing || total.inMilliseconds <= 0
        ? null
        : (_playbackPosition.inMilliseconds / total.inMilliseconds)
            .clamp(0.0, 1.0);
    return DesktopRecorderStrip(
      recording: _isRecording,
      time: time,
      wave: LiveRecordingWave(
          buffer: _waveform, live: _isRecording, progress: progress),
      playing: _isPlayingRecording,
      onDiscard: () => unawaited(_discardRecording()),
      onPlay: () => unawaited(_toggleRecordingPlayback()),
      onStop: () => unawaited(_stopRecording()),
      onSend: () => unawaited(_sendMessage()),
      onSeek: reviewing ? (f) => unawaited(_seekRecording(f, total)) : null,
    );
  }

  Future<void> _seekRecording(double fraction, Duration total) async {
    if (total <= Duration.zero) return;
    final target =
        Duration(milliseconds: (total.inMilliseconds * fraction).round());
    try {
      if (_audioPlayer.state == PlayerState.stopped ||
          _audioPlayer.state == PlayerState.completed) {
        final path = _recordingPath;
        if (path == null) return;
        await _audioPlayer.setSource(DeviceFileSource(path));
      }
      await _audioPlayer.seek(target);
      _playbackPosition = target;
      _recorderTick.value++;
    } catch (_) {}
  }

  Widget _ctxOption(String icon, String label, String value) {
    return Expanded(
      child: Builder(
        builder: (tileContext) => Material(
          color: SurfaceScope.groupOf(tileContext),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.md),
            side: BorderSide(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.pop(tileContext, value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: S.s12),
              child: Column(children: [
                AppIcon(icon, size: 20, color: AppColors.fg1),
                const SizedBox(height: S.s6),
                Text(label, style: TS.label(AppColors.fg2)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFiles() async {
    List<PickedLocalFile> files;
    try {
      files = await pickLocalFiles();
    } catch (e) {
      _toast('$e');
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

  Future<void> _pickPhotos() async {
    final xs =
        await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2200);
    if (xs.isEmpty) return;
    await _ingest(xs
        .map((x) => (name: x.name, localPath: x.path, readBytes: x.readAsBytes))
        .toList());
  }

  Future<void> _pickCamera() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.camera, imageQuality: 85, maxWidth: 2200);
    if (x == null) return;
    await _ingest(
        [(name: x.name, localPath: x.path, readBytes: x.readAsBytes)]);
  }

  // Create attachment chips for the picked items (capped to 10 total) and upload each.
  Future<void> _ingest(
      List<
              ({
                String name,
                String? localPath,
                Future<Uint8List> Function() readBytes
              })>
          picked) async {
    final remaining = _maxAttachments - _attachments.length;
    if (remaining <= 0) return;
    var items = picked;
    if (items.length > remaining) {
      items = items.take(remaining).toList();
      _toast('Added $remaining (max $_maxAttachments).');
    }
    final entries = items
        .map((p) => _Attachment(
            name: p.name,
            isImage: _isImageName(p.name),
            isAudio: isAudioAttachmentPath(p.name),
            localPath: p.localPath))
        .toList();
    if (entries.isEmpty) return;
    _setState(() => _attachments.addAll(entries));
    final generation = _attachmentGeneration;
    final draftKey = _draftKey;
    for (var i = 0; i < entries.length; i++) {
      final p = items[i];
      final a = entries[i];
      try {
        final bytes = await p.readBytes();
        final path = await widget.client.uploadFile(bytes, name: p.name);
        if (!mounted || generation != _attachmentGeneration) {
          // The composer moved on mid-upload: the file still belongs to the
          // session it was attached in, as part of that session's draft.
          a.remotePath = path;
          a.uploading = false;
          Drafts.instance.addAttachment(draftKey, a.toDraft());
          continue;
        }
        _setState(() {
          a.remotePath = path;
          a.uploading = false;
        });
      } catch (e) {
        if (!mounted) return;
        _setState(() => _attachments.remove(a));
        _toast('upload failed: ${p.name}');
      }
    }
  }

  Future<void> _consumeInboundShare(SharedInbound share) async {
    if (_consumedShare == share || share.isEmpty) return;
    _consumedShare = share;
    // Drop it at the source immediately: mobile destroys non-active session
    // states, and a fresh state re-runs initState → consume → resend.
    widget.onShareConsumed?.call();
    // Stage the share in the composer — text pre-filled, attachments attached
    // — but never auto-send. The user writes their message around it and sends
    // like they normally would.
    if (share.text.trim().isNotEmpty) {
      final existing = _input.text;
      _input.text = existing.isEmpty
          ? share.text.trim()
          : '${existing.trim()}\n\n${share.text.trim()}';
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
    if (share.paths.isNotEmpty) {
      await _ingest([
        for (var i = 0; i < share.paths.length; i++)
          (
            name: i < share.names.length && share.names[i].isNotEmpty
                ? share.names[i]
                : share.paths[i].split('/').last,
            localPath: share.paths[i],
            readBytes: () => File(share.paths[i]).readAsBytes(),
          ),
      ]);
    }
    if (share.send) {
      for (var i = 0; i < 50 && mounted && _channel == null; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      if (mounted) await _sendMessage();
    }
  }

  Future<void> _disposeRecorder() async {
    try {
      if (_isRecording) await _recorder.cancel();
    } catch (_) {}
    final pendingPath = _recordingPath;
    _recordingBytes = null;
    if (pendingPath != null) {
      try {
        final file = File(pendingPath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    try {
      if (kCanRecord) {
        await _recorder.dispose();
      }
    } catch (_) {}
  }
}

/// The newest samples, right-aligned so the wave scrolls in as you speak; in
/// review the part already played is drawn in the accent.
