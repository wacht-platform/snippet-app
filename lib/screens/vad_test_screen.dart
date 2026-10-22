import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:silero_vad/silero_vad.dart';

import '../platform.dart';
import '../settings_form.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

class VadTestScreen extends StatefulWidget {
  const VadTestScreen({super.key});

  @override
  State<VadTestScreen> createState() => _VadTestScreenState();
}

class _VadTestScreenState extends State<VadTestScreen> {
  static const _history = 320;
  static const _frameSeconds = SileroVad.chunkSamples / SileroVad.sampleRate;

  final AudioRecorder _recorder = AudioRecorder();
  SileroVad? _vad;
  StreamSubscription<Uint8List>? _sub;
  final BytesBuilder _pending = BytesBuilder(copy: false);
  final List<double> _probs = [];
  final Stopwatch _clock = Stopwatch();
  final Stopwatch _inference = Stopwatch();

  bool _running = false;
  bool _speaking = false;
  double _threshold = 0.5;
  double _prob = 0;
  double _level = -90;
  int _frames = 0;
  int _speechFrames = 0;
  int _segments = 0;
  int _silentRun = 0;
  String? _error;
  Timer? _tick;

  @override
  void dispose() {
    _stop(dispose: true);
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    final granted = kMobile
        ? (await Permission.microphone.request()).isGranted
        : await _recorder.hasPermission();
    if (!granted) {
      setState(() => _error = 'Microphone permission is required.');
      return;
    }
    try {
      _vad = SileroVad();
      final stream = await _recorder.startStream(const RecordConfig(
          encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1));
      _probs.clear();
      _pending.clear();
      _frames = 0;
      _speechFrames = 0;
      _segments = 0;
      _silentRun = 0;
      _speaking = false;
      _inference.reset();
      _clock
        ..reset()
        ..start();
      _sub = stream.listen(_onAudio, onError: (Object e) {
        if (mounted) setState(() => _error = '$e');
      });
      _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) setState(() {});
      });
      setState(() => _running = true);
    } catch (e) {
      _vad?.close();
      _vad = null;
      setState(() => _error = '$e');
    }
  }

  Future<void> _stop({bool dispose = false}) async {
    _tick?.cancel();
    _tick = null;
    await _sub?.cancel();
    _sub = null;
    _clock.stop();
    if (_running) await _recorder.stop();
    _vad?.close();
    _vad = null;
    if (!dispose && mounted) {
      setState(() {
        _running = false;
        _speaking = false;
      });
    }
  }

  void _onAudio(Uint8List bytes) {
    final vad = _vad;
    if (vad == null) return;
    _pending.add(bytes);
    const chunkBytes = SileroVad.chunkSamples * 2;
    var buffer = _pending.takeBytes();
    var offset = 0;
    while (buffer.length - offset >= chunkBytes) {
      final view = ByteData.sublistView(buffer, offset, offset + chunkBytes);
      final samples = Float32List(SileroVad.chunkSamples);
      var sum = 0.0;
      for (var i = 0; i < samples.length; i++) {
        final v = view.getInt16(i * 2, Endian.little) / 32768.0;
        samples[i] = v;
        sum += v * v;
      }
      _inference.start();
      final p = vad.process(samples);
      _inference.stop();
      _consume(p, sum / samples.length);
      offset += chunkBytes;
    }
    if (offset < buffer.length) {
      _pending.add(Uint8List.sublistView(buffer, offset));
    }
  }

  void _consume(double p, double meanSquare) {
    _frames++;
    _prob = p;
    _level = meanSquare <= 1e-9 ? -90 : 10 * math.log(meanSquare) / math.ln10;
    _probs.add(p);
    if (_probs.length > _history) _probs.removeAt(0);
    if (p >= _threshold) {
      if (!_speaking) _segments++;
      _speaking = true;
      _silentRun = 0;
    } else if (_speaking && p < _threshold - 0.15) {
      _silentRun++;
      if (_silentRun * _frameSeconds >= 0.5) _speaking = false;
    }
    if (_speaking) _speechFrames++;
  }

  String _seconds(double s) {
    final m = s ~/ 60;
    final r = s - m * 60;
    return m > 0 ? '${m}m ${r.toStringAsFixed(0)}s' : '${r.toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _clock.elapsedMilliseconds / 1000;
    final speech = _speechFrames * _frameSeconds;
    final perFrameMs = _frames == 0
        ? 0.0
        : _inference.elapsedMicroseconds / 1000 / _frames;
    final audioPerSecond = _frames * _frameSeconds;
    final realtime = elapsed > 0 ? audioPerSecond / elapsed : 0.0;
    final accent = _speaking ? AppColors.accent : AppColors.fg4;
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Column(children: [
          NavBackRow(
              title: 'Voice activity test',
              backLabel: 'Voice',
              onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(kMobile ? 16 : 24, 8, kMobile ? 16 : 24, 40),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: AppColors.surface1,
                      borderRadius: BorderRadius.circular(kMobile ? 14 : 10),
                      border: Border.all(color: AppColors.line)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                  color: accent, shape: BoxShape.circle)),
                          const SizedBox(width: 10),
                          Text(
                              !_running
                                  ? 'Stopped'
                                  : _speaking
                                      ? 'Speech'
                                      : 'Silence',
                              style: sans(18, color: AppColors.fg1)),
                          const Spacer(),
                          Text(_prob.toStringAsFixed(2),
                              style: mono(16, color: accent)),
                        ]),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 96,
                          width: double.infinity,
                          child: CustomPaint(
                              painter: _ProbPainter(
                                  List.of(_probs), _threshold, AppColors.accent,
                                  AppColors.line, AppColors.fg4)),
                        ),
                        const SizedBox(height: 6),
                        Text('Last 10 seconds. The line is the threshold.',
                            style: sans(12, color: AppColors.fg4)),
                      ]),
                ),
                const SizedBox(height: 16),
                Btn(_running ? 'Stop' : 'Start listening',
                    full: true,
                    variant: _running ? BtnVariant.secondary : BtnVariant.primary,
                    onTap: _running ? _stop : _start),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!, style: sans(13, color: AppColors.danger))),
                const SizedBox(height: 22),
                SettingsGroup(header: 'Threshold', footer: 'Higher means fewer false alarms and more missed quiet speech.', children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(children: [
                      Expanded(
                        child: Slider(
                            value: _threshold,
                            min: 0.2,
                            max: 0.9,
                            onChanged: (v) => setState(() => _threshold = v)),
                      ),
                      SizedBox(
                          width: 44,
                          child: Text(_threshold.toStringAsFixed(2),
                              style: mono(13, color: AppColors.fg2))),
                    ]),
                  ),
                ]),
                SettingsGroup(header: 'This session', children: [
                  _stat('Listening for', _seconds(elapsed)),
                  _stat('Speech detected', '${_seconds(speech)}  (${elapsed > 0 ? (100 * speech / elapsed).toStringAsFixed(0) : 0}%)'),
                  _stat('Speech segments', '$_segments'),
                  _stat('Mic level', '${_level.toStringAsFixed(0)} dBFS'),
                ]),
                SettingsGroup(header: 'Performance', footer: 'Time the detector spends on each 32 ms of audio, on this device.', children: [
                  _stat('Per frame', '${perFrameMs.toStringAsFixed(3)} ms'),
                  _stat('CPU for the detector', '${(100 * perFrameMs / (_frameSeconds * 1000)).toStringAsFixed(2)}% of one core'),
                  _stat('Audio keeping up', '${realtime.toStringAsFixed(2)}x'),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _stat(String label, String value) => SettingsRow(
      label: label,
      trailing: Text(value, style: mono(13, color: AppColors.fg2)));
}

class _ProbPainter extends CustomPainter {
  _ProbPainter(this.probs, this.threshold, this.bar, this.grid, this.thresholdColor);
  final List<double> probs;
  final double threshold;
  final Color bar;
  final Color grid;
  final Color thresholdColor;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = grid..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), base);
    const slots = _VadTestScreenState._history;
    final w = size.width / slots;
    final fill = Paint()..color = bar;
    final dim = Paint()..color = bar.withValues(alpha: 0.35);
    for (var i = 0; i < probs.length; i++) {
      final h = (probs[i].clamp(0.0, 1.0)) * size.height;
      final x = (slots - probs.length + i) * w;
      canvas.drawRect(Rect.fromLTWH(x, size.height - h, math.max(w - 0.5, 0.5), h),
          probs[i] >= threshold ? fill : dim);
    }
    final y = size.height * (1 - threshold);
    canvas.drawLine(Offset(0, y), Offset(size.width, y),
        Paint()..color = thresholdColor..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_ProbPainter old) => true;
}
