import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

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

class _UsageScreenState extends State<UsageScreen> {
  late Future<UsageSummary> _future;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _future = widget.client.getUsage();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    setState(() => _future = widget.client.getUsage());
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final body = FutureBuilder<UsageSummary>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: DelayedSpinner(size: 22));
        }
        if (snap.hasError) {
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
        final summary = snap.data!;
        if (summary.providers.isEmpty) {
          return const EmptyState(
              icon: 'analytics',
              title: 'No usage yet',
              body: 'Token counts appear here once a session has run.');
        }
        return PageBody(children: [
          for (var i = 0; i < summary.providers.length; i++) ...[
            if (i > 0) const SizedBox(height: S.s12),
            _ProviderCard(provider: summary.providers[i]),
          ],
          const SettingsNote(
              'Token totals since the daemon started. Rate limits come from each provider\'s own reports.'),
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
    return AppCard(
      padding: const EdgeInsets.all(S.s16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(provider.provider, style: TS.rowTitle()),
          ),
          Tag('${provider.sessions} session${provider.sessions == 1 ? '' : 's'}'),
        ]),
        if (provider.profile != null || provider.model.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
              [if (provider.profile != null) provider.profile!, provider.model]
                  .join(' · '),
              style: TS.meta()),
        ],
        if (hasTokens) ...[
          const SizedBox(height: S.s16),
          Row(children: [
            Expanded(child: _Metric('Total', fmtSi(provider.totalTokens))),
            Expanded(child: _Metric('Input', fmtSi(provider.promptTokens))),
            Expanded(
                child: _Metric('Output', fmtSi(provider.completionTokens))),
          ]),
        ],
        if (provider.rateLimits.isEmpty) ...[
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
        ] else ...[
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
