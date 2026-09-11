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
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
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
                    style: mono(10.5, color: AppColors.fg4)),
              ),
              const SizedBox(height: 10),
              Btn('Retry', small: true, onTap: _refresh),
            ]),
          );
        }
        final summary = snap.data!;
        if (summary.providers.isEmpty) {
          return Center(
              child: Text('No provider usage has been reported yet.',
                  style: sans(12.5, color: AppColors.fg3)));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: summary.providers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _ProviderCard(provider: summary.providers[i]),
        );
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
      backgroundColor: AppColors.surface1,
      body: Column(children: [
        SnAppBar(title: 'Usage', onBack: () => Navigator.pop(context)),
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
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(provider.provider,
                style: sans(14, weight: FontWeight.w500, color: AppColors.fg1)),
          ),
          Text(
              '${provider.sessions} session${provider.sessions == 1 ? '' : 's'}',
              style: mono(10.5, color: AppColors.fg4)),
        ]),
        if (provider.profile != null || provider.model.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
              [if (provider.profile != null) provider.profile!, provider.model]
                  .join(' · '),
              style: sans(11, color: AppColors.fg3)),
        ],
        if (hasTokens) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Metric('Total', fmtSi(provider.totalTokens))),
            Expanded(child: _Metric('Input', fmtSi(provider.promptTokens))),
            Expanded(
                child: _Metric('Output', fmtSi(provider.completionTokens))),
          ]),
        ],
        if (provider.rateLimits.isEmpty) ...[
          const SizedBox(height: 12),
          Text('No reported rate-limit usage yet.',
              style: sans(11.5, color: AppColors.fg4)),
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
          Text(label, style: sans(10.5, color: AppColors.fg4)),
          const SizedBox(height: 2),
          Text(value, style: mono(12, color: AppColors.fg2)),
        ],
      );
}

class _RateRow extends StatelessWidget {
  final RateWindow rate;
  const _RateRow({required this.rate});

  @override
  Widget build(BuildContext context) {
    final remaining = rate.leftPercent;
    final color = remaining < 20
        ? AppColors.danger
        : remaining < 50
            ? AppColors.run
            : AppColors.ok;
    final reset = rateResetLabel(rate.resetsAt);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(rateWindowLabel(rate.windowMinutes),
            style: sans(11.5, color: AppColors.fg2)),
        Text('${remaining.round()}% left', style: mono(10.5, color: color)),
      ]),
      const SizedBox(height: 5),
      Progress(pct: remaining, color: color, height: 6),
      if (reset != null) ...[
        const SizedBox(height: 4),
        Text(reset, style: mono(10, color: AppColors.fg4)),
      ],
    ]);
  }
}
