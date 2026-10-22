import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:silero_vad/silero_vad.dart';

import '../platform.dart';
import '../settings_form.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

const _frameSeconds = SileroVad.chunkSamples / SileroVad.sampleRate;
const _history = 320;

abstract class _Engine {
  _Engine(this.name, this.note, {required this.hasProb});
  final String name;
  final String note;
  final bool hasProb;
  final List<double> history = [];
  final Stopwatch cpu = Stopwatch();
  double prob = 0;
  bool speaking = false;
  int frames = 0;
  int speechFrames = 0;
  int segments = 0;
  int _silent = 0;

  void feed(Float32List chunk, double dbfs);
  void close() {}

  void _push(double p, bool detected) {
    frames++;
    prob = p;
    history.add(p);
    if (history.length > _history) history.removeAt(0);
    if (detected && !speaking) segments++;
    speaking = detected;
    if (speaking) speechFrames++;
  }

  void _gate(double p, double threshold) {
    if (p >= threshold) {
      _silent = 0;
      _push(p, true);
    } else if (speaking && p < threshold - 0.15) {
      _silent++;
      _push(p, _silent * _frameSeconds < 0.5);
    } else {
      _push(p, speaking && _silent * _frameSeconds < 0.5);
    }
  }
}

class _SileroC extends _Engine {
  _SileroC(this.threshold)
      : _vad = SileroVad(),
        super('Silero v6 (C port)', 'Ours. Probability per frame.', hasProb: true);
  final SileroVad _vad;
  double threshold;

  @override
  void feed(Float32List chunk, double dbfs) {
    cpu.start();
    final p = _vad.process(chunk);
    cpu.stop();
    _gate(p, threshold);
  }

  @override
  void close() => _vad.close();
}

class _Sherpa extends _Engine {
  _Sherpa(super.name, super.note, this._detector) : super(hasProb: false);
  final so.VoiceActivityDetector _detector;

  @override
  void feed(Float32List chunk, double dbfs) {
    cpu.start();
    _detector.acceptWaveform(chunk);
    final detected = _detector.isDetected();
    while (!_detector.isEmpty()) {
      _detector.pop();
    }
    cpu.stop();
    _push(detected ? 1 : 0, detected);
  }

  @override
  void close() => _detector.free();
}

class _Energy extends _Engine {
  _Energy() : super('Loudness gate', 'Baseline: louder than -45 dBFS.', hasProb: true);

  @override
  void feed(Float32List chunk, double dbfs) {
    cpu.start();
    final p = ((dbfs + 60) / 40).clamp(0.0, 1.0);
    cpu.stop();
    _gate(p, 0.375);
  }
}

class VadTestScreen extends StatefulWidget {
  const VadTestScreen({super.key});

  @override
  State<VadTestScreen> createState() => _VadTestScreenState();
}

class _VadTestScreenState extends State<VadTestScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final BytesBuilder _pending = BytesBuilder(copy: false);
  final Stopwatch _clock = Stopwatch();
  List<_Engine> _engines = [];
  Timer? _tick;
  bool _running = false;
  bool _starting = false;
  double _threshold = 0.5;
  double _level = -90;
  String? _error;
  static bool _bindingsReady = false;

  @override
  void dispose() {
    _stop(dispose: true);
    _recorder.dispose();
    super.dispose();
  }

  Future<String> _stage(String asset, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    final data = await rootBundle.load(asset);
    await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true);
    return file.path;
  }

  Future<List<_Engine>> _build() async {
    if (!_bindingsReady) {
      so.initBindings();
      _bindingsReady = true;
    }
    final silero = await _stage('assets/vad/silero_v5_sherpa.onnx', 'silero_v5.onnx');
    final ten = await _stage('assets/vad/ten_vad.onnx', 'ten_vad.onnx');
    final engines = <_Engine>[_SileroC(_threshold)];
    engines.add(_Sherpa(
        'Silero v5 (onnxruntime)',
        'Older Silero through sherpa-onnx. On/off only.',
        so.VoiceActivityDetector(
            config: so.VadModelConfig(
                sileroVad: so.SileroVadModelConfig(
                    model: silero,
                    threshold: _threshold,
                    minSilenceDuration: 0.5,
                    minSpeechDuration: 0.1,
                    windowSize: 512),
                debug: false),
            bufferSizeInSeconds: 30)));
    engines.add(_Sherpa(
        'TEN VAD (onnxruntime)',
        'Challenger through sherpa-onnx. On/off only.',
        so.VoiceActivityDetector(
            config: so.VadModelConfig(
                tenVad: so.TenVadModelConfig(
                    model: ten,
                    threshold: _threshold,
                    minSilenceDuration: 0.5,
                    minSpeechDuration: 0.1,
                    windowSize: 256),
                debug: false),
            bufferSizeInSeconds: 30)));
    engines.add(_Energy());
    return engines;
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _error = null;
      _starting = true;
    });
    try {
      final granted = kMobile
          ? (await Permission.microphone.request()).isGranted
          : await _recorder.hasPermission();
      if (!granted) {
        setState(() => _error = 'Microphone permission is required.');
        return;
      }
      _engines = await _build();
      final stream = await _recorder.startStream(const RecordConfig(
          encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1));
      _pending.clear();
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
      for (final engine in _engines) {
        engine.close();
      }
      _engines = [];
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop({bool dispose = false}) async {
    _tick?.cancel();
    _tick = null;
    await _sub?.cancel();
    _sub = null;
    _clock.stop();
    if (_running) await _recorder.stop();
    for (final engine in _engines) {
      engine.close();
    }
    if (!dispose && mounted) {
      setState(() {
        _running = false;
        for (final e in _engines) {
          e.speaking = false;
        }
        _engines = [for (final e in _engines) e];
      });
    }
  }

  Future<void> _restartEngines() async {
    if (!_running) return;
    final old = _engines;
    final fresh = await _build();
    if (!mounted || !_running) {
      for (final e in fresh) {
        e.close();
      }
      return;
    }
    setState(() => _engines = fresh);
    for (final e in old) {
      e.close();
    }
  }

  void _onAudio(Uint8List bytes) {
    if (_engines.isEmpty) return;
    _pending.add(bytes);
    const chunkBytes = SileroVad.chunkSamples * 2;
    final buffer = _pending.takeBytes();
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
      final mean = sum / samples.length;
      _level = mean <= 1e-9 ? -90 : 10 * math.log(mean) / math.ln10;
      for (final engine in _engines) {
        if (engine is _SileroC) engine.threshold = _threshold;
        engine.feed(samples, _level);
      }
      offset += chunkBytes;
    }
    if (offset < buffer.length) {
      _pending.add(Uint8List.sublistView(buffer, offset));
    }
  }

  String _seconds(double s) {
    final m = s ~/ 60;
    final r = s - m * 60;
    return m > 0 ? '${m}m ${r.toStringAsFixed(0)}s' : '${r.toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _clock.elapsedMilliseconds / 1000;
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
              padding: EdgeInsets.fromLTRB(
                  kMobile ? 16 : 24, 8, kMobile ? 16 : 24, 40),
              children: [
                Btn(_running ? 'Stop' : (_starting ? 'Loading models' : 'Start listening'),
                    full: true,
                    disabled: _starting,
                    variant: _running ? BtnVariant.secondary : BtnVariant.primary,
                    onTap: _running ? _stop : _start),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!,
                          style: sans(13, color: AppColors.danger))),
                const SizedBox(height: 18),
                SettingsGroup(
                    header: 'Session',
                    footer: 'All models listen to the same microphone at once.',
                    children: [
                      _stat('Listening for', _seconds(elapsed)),
                      _stat('Mic level', '${_level.toStringAsFixed(0)} dBFS'),
                    ]),
                SettingsGroup(
                    header: 'Threshold',
                    footer:
                        'Applies to the three Silero and TEN models. Changing it restarts them.',
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(children: [
                          Expanded(
                            child: Slider(
                                value: _threshold,
                                min: 0.2,
                                max: 0.9,
                                onChanged: (v) => setState(() => _threshold = v),
                                onChangeEnd: (_) => _restartEngines()),
                          ),
                          SizedBox(
                              width: 44,
                              child: Text(_threshold.toStringAsFixed(2),
                                  style: mono(13, color: AppColors.fg2))),
                        ]),
                      ),
                    ]),
                for (final engine in _engines) _card(engine, elapsed),
                if (_engines.isEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                          'Silero v6 (our C port), Silero v5 and TEN VAD through onnxruntime, and a plain loudness gate. Start listening to compare them live.',
                          style: sans(13, height: 1.5, color: AppColors.fg4))),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _card(_Engine e, double elapsed) {
    final accent = e.speaking ? AppColors.accent : AppColors.fg4;
    final msPerFrame =
        e.frames == 0 ? 0.0 : e.cpu.elapsedMicroseconds / 1000 / e.frames;
    final speech = e.speechFrames * _frameSeconds;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(kMobile ? 14 : 10),
            border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(e.name, style: sans(15, color: AppColors.fg1))),
            Text(
                !_running
                    ? ''
                    : e.hasProb
                        ? e.prob.toStringAsFixed(2)
                        : (e.speaking ? 'speech' : 'silence'),
                style: mono(13, color: accent)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            width: double.infinity,
            child: CustomPaint(
                painter: _ChartPainter(List.of(e.history),
                    e.hasProb ? _threshold : 0.5, AppColors.accent, AppColors.line)),
          ),
          const SizedBox(height: 8),
          Text(
              'Speech ${_seconds(speech)} (${elapsed > 0 ? (100 * speech / elapsed).toStringAsFixed(0) : 0}%)  ·  ${e.segments} segments  ·  ${msPerFrame.toStringAsFixed(3)} ms/frame',
              style: sans(12.5, color: AppColors.fg2)),
          const SizedBox(height: 2),
          Text(e.note, style: sans(12, color: AppColors.fg4)),
        ]),
      ),
    );
  }

  Widget _stat(String label, String value) => SettingsRow(
      label: label, trailing: Text(value, style: mono(13, color: AppColors.fg2)));
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.values, this.threshold, this.bar, this.grid);
  final List<double> values;
  final double threshold;
  final Color bar;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height),
        Paint()..color = grid..strokeWidth = 1);
    final w = size.width / _history;
    final fill = Paint()..color = bar;
    final dim = Paint()..color = bar.withValues(alpha: 0.3);
    for (var i = 0; i < values.length; i++) {
      final h = values[i].clamp(0.0, 1.0) * size.height;
      final x = (_history - values.length + i) * w;
      canvas.drawRect(
          Rect.fromLTWH(x, size.height - h, math.max(w - 0.5, 0.5), h),
          values[i] >= threshold ? fill : dim);
    }
    final y = size.height * (1 - threshold);
    canvas.drawLine(Offset(0, y), Offset(size.width, y),
        Paint()..color = grid..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}
