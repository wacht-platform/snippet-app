import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';
import '../live_refresh.dart';

class UsageScreen extends StatefulWidget {
  final DaemonClient client;
  final bool embedded;

  /// Host-supplied back action for [embedded] use. This screen draws its OWN
  /// `NavBackRow`, so exactly one header exists per level.
  final VoidCallback? onBack;

  const UsageScreen({
    super.key,
    required this.client,
    this.embedded = false,
    this.onBack,
  });

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

enum _Period { day, week, month, all }

extension on _Period {
  String get label => switch (this) {
        _Period.day => 'Today',
        _Period.week => '7 days',
        _Period.month => '30 days',
        _Period.all => 'All time',
      };

  DateTime? get since {
    final now = DateTime.now();
    return switch (this) {
      _Period.day => DateTime(now.year, now.month, now.day),
      _Period.week => now.subtract(const Duration(days: 7)),
      _Period.month => now.subtract(const Duration(days: 30)),
      _Period.all => null,
    };
  }
}

class _UsageScreenState extends State<UsageScreen> {
  late Future<UsageSummary> _future;
  UsageSummary? _last;
  LiveRefresh? _live;
  _Period _period = _Period.all;

  Future<UsageSummary> _load() => widget.client
      .getUsage(since: _period.since)
      .then((value) => _last = value);

  @override
  void initState() {
    super.initState();
    _future = _load();
    _live = LiveRefresh(
      client: widget.client,
      when: (e) => const {'idle', 'done', 'error'}.contains(e['kind']),
      refresh: () {
        if (mounted) _refresh();
      },
      debounce: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _live?.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  void _setPeriod(_Period period) {
    if (period == _period) return;
    _period = period;
    _last = null;
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final body = FutureBuilder<UsageSummary>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data ?? _last;
        if (data == null && !snap.hasError) {
          return const Center(child: DelayedSpinner(size: 22));
        }
        if (data == null) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Unable to load usage',
                  style: sans(13, color: AppColors.fg1)),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('${snap.error}',
                    textAlign: TextAlign.center,
                    style: mono(10, color: AppColors.fg3)),
              ),
              const SizedBox(height: 10),
              Btn('Retry', small: true, onTap: _refresh),
            ]),
          );
        }
        final summary = data;
        return PageBody(children: [
          _PeriodTabs(value: _period, onChanged: _setPeriod),
          const SizedBox(height: S.s16),
          if (summary.providers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.s32),
              child: Text('No model calls in this period.',
                  textAlign: TextAlign.center, style: TS.meta()),
            ),
          for (var i = 0; i < summary.providers.length; i++) ...[
            if (i > 0) const SizedBox(height: S.s12),
            _ProviderCard(provider: summary.providers[i]),
          ],
          const SettingsNote(
              'Every model call is recorded against the provider and model that served it. Input includes cached tokens; rate limits come from each provider\'s own reports.'),
        ]);
      },
    );
    if (widget.embedded) {
      // No back action → desktop dialog pane, where the host's section chip strip
      // is the navigation. Drawing a row anyway duplicates it.
      if (widget.onBack == null) return body;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavBackRow(title: 'Usage', onBack: widget.onBack!),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      body: Column(children: [
        SnAppBar(
            title: 'Usage',
            compact: true,
            onBack: () => Navigator.pop(context)),
        Expanded(child: body),
      ]),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final UsageProvider provider;
  const _ProviderCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final hasTokens = provider.totalTokens > 0;
    final sessions =
        '${provider.sessions} session${provider.sessions == 1 ? '' : 's'}';
    final models = provider.models.where((m) => m.model.isNotEmpty).toList();
    return AppCard(
      padding: const EdgeInsets.all(S.s16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(provider.legacy ? 'Before tracking' : provider.provider,
                style: TS.rowTitle()),
          ),
          Tag(sessions),
        ]),
        const SizedBox(height: 3),
        Text(
            provider.legacy
                ? 'Lifetime totals recorded before per-call tracking. They can’t be split by provider or model.'
                : '${provider.calls} call${provider.calls == 1 ? '' : 's'}',
            style: TS.meta()),
        if (hasTokens) ...[
          const SizedBox(height: S.s16),
          Row(children: [
            Expanded(child: _Metric('Total', fmtSi(provider.totalTokens))),
            Expanded(child: _Metric('Input', fmtSi(provider.promptTokens))),
            Expanded(child: _Metric('Cached', fmtSi(provider.cacheReadTokens))),
            Expanded(
                child: _Metric('Output', fmtSi(provider.completionTokens))),
          ]),
        ],
        if (models.length > 1 ||
            (models.length == 1 && !provider.legacy)) ...[
          const SizedBox(height: S.s12),
          for (final m in models)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.s4),
              child: Row(children: [
                Expanded(
                  child: Text(m.model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TS.codeSmall(AppColors.fg2)),
                ),
                Text('${fmtSi(m.totalTokens)} · ${m.calls}×',
                    style: TS.meta().copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
        ],
        if (!provider.legacy && provider.rateLimits.isEmpty) ...[
          const SizedBox(height: 12),
          // THREE states, worded distinctly — a single generic "no usage yet"
          // said the wrong thing in two of them:
          //   true  → provider publishes limits, we just haven't seen one yet
          //   false → provider never publishes them; "yet" would promise a
          //           number the API cannot produce
          //   null  → daemon predates the flag; assert nothing either way
          Row(children: [
            AppIcon(
                switch (provider.rateLimitsSupported) {
                  true => 'clock',
                  false => 'alert-circle',
                  null => 'sparkles',
                },
                size: 14,
                color: AppColors.fg4),
            const SizedBox(width: S.s8),
            Expanded(
              child: Text(
                  switch (provider.rateLimitsSupported) {
                    true =>
                      'No rate-limit report yet — this provider publishes them, none seen so far.',
                    // Not "doesn't publish rate limits": xAI does send
                    // x-ratelimit-* headers, but they are flat API caps with no
                    // window or reset — not the subscription quota shown here.
                    // Claiming it publishes nothing would be false, and showing
                    // those numbers would invent an unrelated figure.
                    false =>
                      'Subscription limits aren’t exposed by this provider’s API.',
                    null => 'No reported rate-limit usage.',
                  },
                  style: TS.meta()),
            ),
          ]),
        ] else if (!provider.legacy) ...[
          const SizedBox(height: 12),
          for (final rate in provider.rateLimits) ...[
            _RateRow(rate: rate),
            const SizedBox(height: 10),
          ],
        ],
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TS.meta()),
          const SizedBox(height: S.s2),
          Text(value,
              style: TS.sectionTitle().copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      );
}

class _RateRow extends StatelessWidget {
  final RateWindow rate;
  const _RateRow({required this.rate});

  @override
  Widget build(BuildContext context) {
    final reset = rateResetLabel(rate.resetsAt);
    // The window rolled over since this snapshot was taken. Do NOT draw the bar
    // or the percentage: both would state the PREVIOUS window's usage as if it
    // were current (99% used / 1% left on a window that has already reset).
    if (rate.isExpired) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(rateWindowLabel(rate.windowMinutes), style: TS.ui()),
        const SizedBox(height: S.s4),
        Text('Rolled over · awaiting the next report', style: TS.meta()),
      ]);
    }

    final remaining = rate.leftPercent;
    final color = remaining < 20
        ? AppColors.danger
        : remaining < 50
            ? AppColors.run
            : AppColors.ok;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(rateWindowLabel(rate.windowMinutes), style: TS.ui()),
        Text('${remaining.round()}% left', style: TS.label(color)),
      ]),
      const SizedBox(height: S.s6),
      Progress(pct: remaining, color: color, height: 6),
      if (reset != null) ...[
        const SizedBox(height: S.s4),
        Text(reset, style: TS.meta()),
      ],
    ]);
  }
}

class _PeriodTabs extends StatelessWidget {
  final _Period value;
  final ValueChanged<_Period> onChanged;
  const _PeriodTabs({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(S.s2),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Row(children: [
          for (final p in _Period.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(p),
                child: AnimatedContainer(
                  duration: Motion.quick,
                  height: kMobile ? 36 : 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p == value ? AppColors.surface3 : Colors.transparent,
                    borderRadius: BorderRadius.circular(R.md - S.s2),
                  ),
                  child: Text(p.label,
                      style: TS.label(
                          p == value ? AppColors.fg1 : AppColors.fg3)),
                ),
              ),
            ),
        ]),
      );
}
