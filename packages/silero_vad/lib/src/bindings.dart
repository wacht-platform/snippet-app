import 'dart:ffi';

@Native<Pointer<Void> Function()>(symbol: 'silero_vad_get_embedded_weights')
external Pointer<Void> sileroWeights();

@Native<Pointer<Void> Function(Pointer<Void>, Size)>(
    symbol: 'silero_vad_model_create')
external Pointer<Void> sileroCreate(Pointer<Void> weights, int inputSamples);

@Native<Void Function(Pointer<Void>)>(symbol: 'silero_vad_model_destroy')
external void sileroDestroy(Pointer<Void> model);

@Native<Void Function(Pointer<Void>)>(symbol: 'silero_vad_model_reset')
external void sileroReset(Pointer<Void> model);

@Native<Int32 Function(Pointer<Void>, Pointer<Float>, Pointer<Float>)>(
    symbol: 'silero_vad_model_forward')
external int sileroForward(
    Pointer<Void> model, Pointer<Float> input, Pointer<Float> probability);
