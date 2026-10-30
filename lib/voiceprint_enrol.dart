import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'platform.dart';
import 'settings_form.dart';
import 'theme.dart';
import 'widgets.dart';

const kEnrolTarget = 3;
const kEnrolMax = Duration(seconds: 5);
const kEnrolMinStop = Duration(milliseconds: 2500);
const kEnrolMinVoiced = Duration(milliseconds: 1500);
const kEnrolTooQuiet = 'Too quiet: move closer and try again.';

const enrolSentences = [
  'I usually check my messages first thing in the morning, before breakfast.',
  'Could you remind me to call the dentist on Thursday afternoon?',
  'The weather looks lovely today, so I might walk to the shops later.',
];

double _rms(Uint8List pcm, int start, int samples) {
  final view = ByteData.sublistView(pcm);
  var sum = 0.0;
  for (var i = 0; i < samples; i++) {
    final s = view.getInt16(start + i * 2, Endian.little).toDouble();
    sum += s * s;
  }
  return samples == 0 ? 0 : math.sqrt(sum / samples);
}

/// Total length of 20 ms frames whose RMS clears [threshold] (16-bit mono PCM).
Duration voicedDuration(
  Uint8List pcm, {
  int sampleRate = 16000,
  double threshold = 400,
  int frameMs = 20,
}) {
  final frame = sampleRate * frameMs ~/ 1000;
  final total = pcm.lengthInBytes ~/ 2;
  var voiced = 0;
  for (var i = 0; i + frame <= total; i += frame) {
    if (_rms(pcm, i * 2, frame) >= threshold) voiced++;
  }
  return Duration(milliseconds: voiced * frameMs);
}

/// Perceptual 0..1 input level for one chunk of 16-bit mono PCM.
double pcmLevel(Uint8List pcm) {
  final r = _rms(pcm, 0, pcm.lengthInBytes ~/ 2);
  return math.sqrt((r / 5000).clamp(0.0, 1.0));
}

enum EnrolPhase { idle, recording, saving }

class EnrolLive {
  const EnrolLive(this.elapsed, this.levels);
  final Duration elapsed;
  final List<double> levels;
}

class VoiceprintGroup extends StatelessWidget {
  const VoiceprintGroup({
    super.key,
    required this.ambient,
    required this.phase,
    required this.live,
    required this.manageOpen,
    required this.busy,
    this.error,
    required this.onRecord,
    required this.onStop,
    required this.onCancel,
    required this.onRecent,
    required this.onToggleManage,
    required this.onRemove,
    required this.onClear,
  });

  final AmbientSettings ambient;
  final EnrolPhase phase;
  final ValueListenable<EnrolLive> live;
  final bool manageOpen;
  final bool busy;
  final String? error;
  final VoidCallback onRecord;
  final VoidCallback onStop;
  final VoidCallback onCancel;
  final VoidCallback onRecent;
  final VoidCallback onToggleManage;
  final void Function(String id) onRemove;
  final VoidCallback onClear;

  int get _count => ambient.voiceprints.where((v) => v.current).length;

  @override
  Widget build(BuildContext context) {
    final a = ambient;
    final vps = a.voiceprints;
    return SettingsGroup(
      header: 'Voiceprint recognition',
      footer: a.voiceprintAdaptive > 0
          ? 'It also learns from your clear lines; ${a.voiceprintAdaptive} learned on this device so far.'
          : 'It also learns from your clear lines as you talk.',
      children: [
        _block(),
        if (vps.isNotEmpty)
          SettingsRow(
            label: 'Manage samples (${vps.length})',
            onTap: onToggleManage,
            trailing: Text(manageOpen ? 'Hide' : 'Show',
                style: sans(13, color: AppColors.fg3)),
          ),
        if (manageOpen) ...[
          for (final vp in vps)
            SettingsRow(
              label: vp.label,
              sub: vp.current ? null : 'Old model, no longer counts',
              trailing: Btn('Remove',
                  small: true,
                  variant: BtnVariant.ghost,
                  disabled: busy || phase != EnrolPhase.idle,
                  onTap: () => onRemove(vp.id)),
            ),
          if (vps.length > 1)
            SettingsRow(
              label: 'Clear all samples',
              danger: true,
              onTap: busy || phase != EnrolPhase.idle ? null : onClear,
            ),
        ],
      ],
    );
  }

  Widget _block() {
    final n = _count;
    final reenrol = ambient.voiceprintReenrol && n < kEnrolTarget;
    final done = n >= kEnrolTarget;
    final (title, tag, tone) = done
        ? ('Recognises your voice', 'Done', Tone.ok)
        : reenrol
            ? (
                n == 0
                    ? 'Upgraded: record 3 new samples'
                    : 'Upgraded: $n of 3 re-recorded',
                'Re-record',
                Tone.run
              )
            : n == 0
                ? ('Not set up', 'Off', Tone.neutral)
                : ('$n of 3 recorded', 'In progress', Tone.accent);
    final sub = done
        ? 'Snippet can tell your voice from others.'
        : reenrol && n == 0
            ? 'Voice recognition was upgraded, so your old samples no longer count.'
            : 'Read three short lines aloud, about 5 seconds each.';
    final pad = kMobile ? 16.0 : 14.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, S.s12, pad, S.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: sans(kMobile ? 16 : 14,
                        weight: W.label, color: AppColors.fg1))),
            const SizedBox(width: S.s8),
            Tag(tag, tone: tone),
          ]),
          const SizedBox(height: S.s4),
          Text(sub, style: sans(13, color: AppColors.fg3, height: 1.4)),
          const SizedBox(height: S.s12),
          _Steps(done: n, active: phase != EnrolPhase.idle, tone: tone),
          const SizedBox(height: S.s12),
          switch (phase) {
            EnrolPhase.recording => _recording(n),
            EnrolPhase.saving => Text('Checking your sample…',
                style: sans(13, color: AppColors.fg2)),
            EnrolPhase.idle => _idle(n, done),
          },
        ],
      ),
    );
  }

  Widget _idle(int n, bool done) {
    final off = busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!done && error == null)
          _Sentence(text: enrolSentences[n % enrolSentences.length], n: n),
        if (error != null) ...[
          Text(error!, style: sans(13, color: AppColors.danger, height: 1.4)),
          const SizedBox(height: S.s8),
        ],
        if (!done && error == null) const SizedBox(height: S.s12),
        Wrap(
            alignment: WrapAlignment.start,
            spacing: S.s8,
            runSpacing: S.s8,
            children: [
              Btn(
                error != null
                    ? 'Retry'
                    : done
                        ? 'Record another'
                        : 'Record sample ${n + 1}',
                small: true,
                variant: done ? BtnVariant.surface : BtnVariant.primary,
                disabled: off,
                onTap: onRecord,
              ),
              Btn('Use last turn',
                  small: true,
                  variant: BtnVariant.ghost,
                  disabled: off,
                  onTap: onRecent),
            ]),
      ],
    );
  }

  Widget _recording(int n) {
    return ValueListenableBuilder<EnrolLive>(
      valueListenable: live,
      builder: (context, l, _) {
        final secs = l.elapsed.inMilliseconds / 1000;
        final canStop = l.elapsed >= kEnrolMinStop;
        final frac = (l.elapsed.inMilliseconds / kEnrolMax.inMilliseconds)
            .clamp(0.0, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Sentence(text: enrolSentences[n % enrolSentences.length], n: n),
            const SizedBox(height: S.s12),
            Row(children: [
              Expanded(child: _Meter(levels: l.levels)),
              const SizedBox(width: S.s12),
              Text('${secs.toStringAsFixed(1)} / 5 s',
                  style: TS.codeSmall(AppColors.fg2)),
            ]),
            const SizedBox(height: S.s8),
            _Bar(frac: frac),
            const SizedBox(height: S.s8),
            Text(
              canStop ? 'Good. Stop now or keep going.' : 'Keep reading…',
              style: sans(13, color: AppColors.fg3),
            ),
            const SizedBox(height: S.s12),
            Wrap(spacing: S.s8, runSpacing: S.s8, children: [
              Btn('Stop',
                  small: true,
                  disabled: !canStop,
                  onTap: canStop ? onStop : null),
              Btn('Cancel',
                  small: true, variant: BtnVariant.ghost, onTap: onCancel),
            ]),
          ],
        );
      },
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.done, required this.active, required this.tone});
  final int done;
  final bool active;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, _) = toneColors(tone == Tone.neutral ? Tone.accent : tone);
    return Row(children: [
      for (var i = 0; i < kEnrolTarget; i++) ...[
        if (i > 0) const SizedBox(width: S.s8),
        Container(
          width: 28,
          height: 6,
          decoration: BoxDecoration(
            color: i < done
                ? fg
                : (active && i == done
                    ? fg.withValues(alpha: 0.45)
                    : AppColors.hover),
            borderRadius: BorderRadius.circular(R.pill),
          ),
        ),
      ],
      const SizedBox(width: S.s12),
      Text('${done.clamp(0, kEnrolTarget)}/$kEnrolTarget',
          style: TS.codeSmall(AppColors.fg3)),
    ]);
  }
}

class _Sentence extends StatelessWidget {
  const _Sentence({required this.text, required this.n});
  final String text;
  final int n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(S.s12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('READ ALOUD', style: TS.overline(AppColors.fg4)),
        const SizedBox(height: S.s4),
        Text('“$text”',
            style: sans(kMobile ? 16 : 15, color: AppColors.fg1, height: 1.4)),
      ]),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.levels});
  final List<double> levels;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final l in levels) ...[
            Expanded(
              child: Center(
                child: Container(
                  height: 4 + 28 * l.clamp(0.0, 1.0),
                  constraints: const BoxConstraints(maxWidth: 8),
                  decoration: BoxDecoration(
                    color: l > 0.08 ? AppColors.accent : AppColors.hover,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.frac});
  final double frac;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final tick =
          c.maxWidth * kEnrolMinStop.inMilliseconds / kEnrolMax.inMilliseconds;
      return SizedBox(
        height: 4,
        child: Stack(children: [
          Container(
            decoration: BoxDecoration(
                color: AppColors.hover,
                borderRadius: BorderRadius.circular(R.pill)),
          ),
          Container(
            width: c.maxWidth * frac,
            decoration: BoxDecoration(
                color: AppColors.accentFill,
                borderRadius: BorderRadius.circular(R.pill)),
          ),
          Positioned(
              left: tick,
              child: Container(width: 2, height: 4, color: AppColors.fg4)),
        ]),
      );
    });
  }
}
