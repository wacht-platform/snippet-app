part of 'session.dart';

const _maxRecordingDuration = Duration(minutes: 3);

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
      // Starting a new take replaces an unconfirmed take only after the user
      // explicitly chose to record again.
      if (_recordingPath != null || _recordingBytes != null) {
        await _discardRecording();
      }
      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/snippet-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
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
          // Keep a denser rolling waveform so the bars stay close together
          // when the strip spans the full composer width.
          if (_waveform.length > 180) _waveform.removeAt(0);
        _recorderTick.value++;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final next = _recordingElapsed + const Duration(seconds: 1);
        if (next >= _maxRecordingDuration) {
          _setState(() => _recordingElapsed = _maxRecordingDuration);
          unawaited(_stopRecording());
          _toast('Recording stopped at the 3-minute limit.');
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
    final file = File(path);
    const attempts = 40; // ~2s
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
        await _audioPlayer.play(DeviceFileSource(path));
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

  Widget _recordingPanel() {
    final reviewing = !_isRecording && _recordingPath != null;
    final position = reviewing ? _playbackPosition : _recordingElapsed;
    final samples = List<double>.of(_waveform);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(children: [
        InkWell(
          onTap: _isRecording ? _stopRecording : _toggleRecordingPlayback,
          borderRadius: BorderRadius.circular(R.pill),
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

  Widget _ctxOption(String icon, String label, String value) {
    return Expanded(
      child: Builder(
        builder: (tileContext) => Material(
          color: SurfaceScope.groupOf(tileContext),
          borderRadius: BorderRadius.circular(R.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.md),
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
