import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/bindings.dart';

class SileroVad {
  static const chunkSamples = 512;
  static const contextSamples = 64;
  static const sampleRate = 16000;
  static const _inputSamples = contextSamples + chunkSamples;

  final Pointer<Void> _model;
  final Pointer<Float> _input = calloc<Float>(_inputSamples);
  final Pointer<Float> _output = calloc<Float>(1);
  bool _closed = false;

  SileroVad._(this._model);

  factory SileroVad() {
    final model = sileroCreate(sileroWeights(), _inputSamples);
    if (model == nullptr) throw StateError('Silero VAD model init failed');
    return SileroVad._(model);
  }

  double process(Float32List chunk) {
    if (_closed) throw StateError('SileroVad is closed');
    if (chunk.length != chunkSamples) {
      throw ArgumentError('Expected $chunkSamples samples, got ${chunk.length}');
    }
    final buffer = _input.asTypedList(_inputSamples);
    buffer.setRange(contextSamples, _inputSamples, chunk);
    final status = sileroForward(_model, _input, _output);
    if (status != 0) throw StateError('Silero VAD forward failed: $status');
    buffer.setRange(0, contextSamples, buffer, chunkSamples);
    return _output.value;
  }

  double processPcm16(Int16List chunk) {
    final floats = Float32List(chunk.length);
    for (var i = 0; i < chunk.length; i++) {
      floats[i] = chunk[i] / 32768.0;
    }
    return process(floats);
  }

  void reset() {
    sileroReset(_model);
    _input.asTypedList(contextSamples).fillRange(0, contextSamples, 0);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    sileroDestroy(_model);
    calloc.free(_input);
    calloc.free(_output);
  }
}
