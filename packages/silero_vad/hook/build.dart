import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final code = input.config.code;
    final arch = code.targetArchitecture;
    final defines = <String, String?>{
      'SILERO_VAD_BUILD_DLL': '1',
      if (arch == Architecture.arm64) 'SILERO_VAD_ENABLE_NEON': '1',
      if (arch == Architecture.x64) 'SILERO_VAD_ENABLE_SSE': '1',
    };
    await CBuilder.library(
      name: 'silero_vad',
      assetName: 'src/bindings.dart',
      sources: ['src/silero_vad.c', 'src/silero_vad_weights.c'],
      includes: ['src'],
      defines: defines,
      libraries: code.targetOS == OS.windows ? const [] : const ['m'],
    ).run(input: input, output: output);
  });
}
