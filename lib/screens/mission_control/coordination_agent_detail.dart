import 'package:flutter/material.dart';

import '../../models.dart';
import '../../theme.dart';

/// Read-only detail view for one coordination agent. Opened by tapping a row in
/// [CoordinationAgentDirectory]. Shows the directory identity plus its configured
/// capacity; no actions yet.
class CoordinationAgentDetail extends StatelessWidget {
  const CoordinationAgentDetail({super.key, required this.agent});

  final CoordinationAgent agent;

  @override
  Widget build(BuildContext context) {
    final initial = agent.displayName.trim().isEmpty
        ? '?'
        : agent.displayName.trim()[0].toUpperCase();
    return Scaffold(
      appBar: AppBar(title: Text(agent.displayName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.accentBg,
                foregroundColor: AppColors.accent,
                child: Text(initial,
                    style:
                        sans(20, weight: FontWeight.w600, color: AppColors.accent)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(agent.displayName,
                        style: sans(18,
                            weight: FontWeight.w600, color: AppColors.fg1)),
                    const SizedBox(height: 4),
                    Text('@${agent.handle}',
                        style: sans(13, color: AppColors.fg3)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _Section(
            title: 'Role',
            children: [
              _Field('Kind', agent.kind),
              _Field('Role', agent.role),
              _Field('Status', agent.status),
              _Field('Version', 'v${agent.version}'),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Capacity',
            children: [
              _Field(
                  'Concurrent assignments',
                  '${agent.maxConcurrentAssignments}'),
            ],
          ),
          if (agent.capabilities.isNotEmpty) ...[
            const SizedBox(height: 20),
            _Section(
              title: 'Capabilities',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final capability in agent.capabilities)
                      _CapabilityChip(capability),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: sans(11,
                  weight: FontWeight.w600,
                  color: AppColors.fg4,
                  spacing: 0.6)),
          const SizedBox(height: 10),
          ...children,
        ],
      );
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 168,
              child: Text(label, style: sans(13, color: AppColors.fg3)),
            ),
            Expanded(
              child: Text(value,
                  style: sans(13,
                      weight: FontWeight.w500, color: AppColors.fg1)),
            ),
          ],
        ),
      );
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label, style: sans(12, color: AppColors.fg2)),
      );
}
