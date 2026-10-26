import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../settings_form.dart';
import '../swr.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

String _providerTitle(String id) => switch (id.toLowerCase()) {
      'anthropic' => 'Anthropic',
      'claude-code' || 'claude_code' => 'Claude Code',
      'openai' => 'OpenAI',
      'chatgpt' => 'ChatGPT',
      'gemini' || 'google' => 'Gemini',
      'xai' || 'grok' => 'xAI',
      'openrouter' => 'OpenRouter',
      'antigravity' => 'Antigravity',
      _ => id.isEmpty ? 'Provider' : id,
    };

String _windowTitle(RateWindow r) {
  final base = switch (r.windowMinutes) {
    300 => '5-hour window',
    180 => '3-hour window',
    60 => 'Hourly window',
    1440 => 'Daily window',
    10080 => 'Weekly window',
    43200 => 'Monthly window',
    _ => rateWindowLabel(r.windowMinutes),
  };
  return (r.label == null || r.label!.isEmpty) ? base : '${r.label} · $base';
}

class UsageScreen extends StatefulWidget {
  final DaemonClient client;
  final bool embedded;
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
  late Swr<UsageSummary> _usage = _watch();
  _Period _period = _Period.all;

  Swr<UsageSummary> _watch() => Swr<UsageSummary>(
        client: widget.client,
        key: 'usage:${_period.name}',
        fetch: () => widget.client.getUsage(since: _period.since),
        revalidateOn: (e) =>
            const {'idle', 'done', 'error'}.contains(e['kind']),
        onChange: () {
          if (mounted) setState(() {});
        },
        debounce: const Duration(seconds: 2),
      );

  @override
  void dispose() {
    _usage.dispose();
    super.dispose();
  }

  void _refresh() => _usage.refresh();

  void _setPeriod(_Period period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _usage.dispose();
      _usage = _watch();
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final data = _usage.data;
    final Widget content;
    if (data == null && _usage.error == null) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: Spinner(size: 18)),
      );
    } else if (data == null) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: S.s24),
        child: Column(children: [
          Text('Unable to load usage', style: sans(13, color: AppColors.fg1)),
          const SizedBox(height: 6),
          Text('${_usage.error}',
              textAlign: TextAlign.center,
              style: mono(11, color: AppColors.fg3)),
          const SizedBox(height: 10),
          Btn('Retry', small: true, onTap: _refresh),
        ]),
      );
    } else if (data.providers.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: S.s32),
        child: Text('No model calls in this period.',
            textAlign: TextAlign.center, style: TS.meta()),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in data.providers) _ProviderSection(provider: p),
        ],
      );
    }

    final Widget body;
    if (kMobile) {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          _PeriodTabs(value: _period, onChanged: _setPeriod),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: Motion.quick,
            child: KeyedSubtree(
              key: ValueKey(data == null
                  ? (_usage.error == null ? 'loading' : 'error')
                  : 'data:${_period.name}'),
              child: content,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Text(
              'Every model call is recorded against the provider and model that served it. Input includes cached tokens; rate limits come from each provider\'s own reports.',
              style: sans(12.5, height: 1.5, color: AppColors.fg4),
            ),
          ),
        ],
      );
    } else {
      body = ListView(
        padding: widget.embedded
            ? EdgeInsets.zero
            : const EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, S.s40),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _PeriodTabs(value: _period, onChanged: _setPeriod),
          ),
          const SizedBox(height: S.s20),
          AnimatedSwitcher(
            duration: Motion.quick,
            child: KeyedSubtree(
              key: ValueKey(data == null
                  ? (_usage.error == null ? 'loading' : 'error')
                  : 'data:${_period.name}'),
              child: content,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Every model call is recorded against the provider and model that served it. Input includes cached tokens; rate limits come from each provider\'s own reports.',
              style: sans(12.5, height: 1.5, color: AppColors.fg4),
            ),
          ),
        ],
      );
    }

    if (widget.embedded) {
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

class _ProviderSection extends StatelessWidget {
  final UsageProvider provider;
  const _ProviderSection({required this.provider});

  @override
  Widget build(BuildContext context) {
    final hasTokens = provider.totalTokens > 0;
    final sessions =
        '${provider.sessions} session${provider.sessions == 1 ? '' : 's'}';
    final calls = '${provider.calls} call${provider.calls == 1 ? '' : 's'}';
    final models = provider.models.where((m) => m.model.isNotEmpty).toList();

    return SettingsGroup(
      children: [
        SettingsRow(
          leading: ProviderLogo(provider.provider, size: kMobile ? 18 : 16),
          label: _providerTitle(provider.provider),
          sub: provider.model.isNotEmpty && models.isEmpty
              ? provider.model
              : null,
          trailing: Text(
            '$sessions · $calls',
            style: sans(kMobile ? 13 : 12, color: AppColors.fg4, tabular: true),
          ),
        ),
        if (provider.rateLimits.isNotEmpty)
          for (final r in provider.rateLimits) _RateRow(rate: r)
        else
          SettingsRow(
            label: switch (provider.rateLimitsSupported) {
              true => 'No rate-limit data yet',
              false => 'Subscription limits aren\'t exposed by this API',
              null => 'Rate limits update after the next turn',
            },
            labelWidget: Text(
              switch (provider.rateLimitsSupported) {
                true => 'No rate-limit data yet — send a message to refresh.',
                false =>
                  'Subscription limits aren\'t exposed by this provider\'s API.',
                null => 'Rate limits appear after the next turn.',
              },
              style: sans(kMobile ? 13 : 12.5, color: AppColors.fg4),
            ),
          ),
        if (hasTokens)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: kMobile ? 16 : 14,
              vertical: kMobile ? 12 : 10,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Metric('Total', fmtSi(provider.totalTokens)),
                _Metric('Input', fmtSi(provider.promptTokens)),
                _Metric('Cached', fmtSi(provider.cacheReadTokens)),
                _Metric('Output', fmtSi(provider.completionTokens)),
              ],
            ),
          ),
        for (final m in models)
          SettingsRow(
            label: m.model,
            labelWidget: Text(
              m.model,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(kMobile ? 13 : 12, color: AppColors.fg2),
            ),
            trailing: Text(
              '${fmtSi(m.totalTokens)} · ${m.calls}×',
              style: mono(kMobile ? 12.5 : 11.5, color: AppColors.fg4),
            ),
          ),
      ],
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
          Text(label, style: sans(11.5, color: AppColors.fg4)),
          const SizedBox(height: 3),
          Text(
            value,
            style: mono(
              kMobile ? 15 : 14,
              weight: FontWeight.w500,
              color: AppColors.fg1,
            ),
          ),
        ],
      );
}

class _RateRow extends StatelessWidget {
  final RateWindow rate;
  const _RateRow({required this.rate});

  @override
  Widget build(BuildContext context) {
    final title = _windowTitle(rate);
    final reset = rateResetLabel(rate.resetsAt);
    if (rate.isExpired) {
      return SettingsRow(
        label: title,
        sub: 'Rolled over · awaiting the next report',
      );
    }

    final remaining = rate.leftPercent;
    final color = remaining < 20
        ? AppColors.danger
        : remaining < 50
            ? AppColors.run
            : AppColors.ok;

    return SettingsRow(
      label: title,
      sub: reset,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: kMobile ? 76 : 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 5,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: AppColors.surface3),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (remaining / 100).clamp(0.0, 1.0),
                      child: Container(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 68,
            child: Text(
              '${remaining.round()}% left',
              textAlign: TextAlign.right,
              style: mono(12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodTabs extends StatelessWidget {
  final _Period value;
  final ValueChanged<_Period> onChanged;
  const _PeriodTabs({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (kMobile) {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(children: [
          for (final p in _Period.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(p),
                child: AnimatedContainer(
                  duration: Motion.quick,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p == value ? AppColors.surface3 : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    p.label,
                    style: sans(
                      13,
                      weight:
                          p == value ? FontWeight.w500 : FontWeight.w400,
                      color: p == value ? AppColors.fg1 : AppColors.fg3,
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in _Period.values)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(p),
              child: AnimatedContainer(
                duration: Motion.quick,
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p == value ? AppColors.surface3 : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  p.label,
                  style: sans(
                    12,
                    weight: p == value ? FontWeight.w500 : FontWeight.w400,
                    color: p == value ? AppColors.fg1 : AppColors.fg3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
