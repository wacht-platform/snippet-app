import 'package:flutter/material.dart';

import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Overlay a sidebar-toggle on the welcome/empty states when the sidebar is collapsed.
class ShellWithMenu extends StatelessWidget {
  final VoidCallback? onMenu;
  final Widget child;

  const ShellWithMenu({super.key, required this.onMenu, required this.child});

  @override
  Widget build(BuildContext context) {
    if (onMenu == null) return child;
    return Stack(children: [
      child,
      Positioned(
        top: 6,
        left: 6,
        child: IconBtn(
          'sidebar',
          size: kMobile ? 44 : 38,
          iconSize: kMobile ? 25 : 19,
          tooltip: 'Sidebar',
          onTap: onMenu,
        ),
      ),
    ]);
  }
}

/// No instance connected welcome state with action to add a machine.
class ShellWelcomeView extends StatelessWidget {
  final VoidCallback onAddInstance;

  const ShellWelcomeView({super.key, required this.onAddInstance});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(R.card),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: AppIcon('server', size: 24, color: AppColors.fg3),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'No instance connected',
                textAlign: TextAlign.center,
                style: sans(16, color: AppColors.fg1),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  style: sans(12, height: 1.5, color: AppColors.fg3),
                  children: [
                    const TextSpan(text: 'Run '),
                    TextSpan(
                      text: 'snippet serve',
                      style: mono(12, color: AppColors.fg2),
                    ),
                    const TextSpan(
                      text:
                          ' on a machine, then paste the connection string it prints.',
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              Center(
                child: PillBtn(
                  'Add machine',
                  icon: 'plus',
                  onTap: onAddInstance,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// No session selected placeholder: recent sessions preview + new chat encouragement.
class ShellRecentPlaceholder extends StatelessWidget {
  final List<SessionInfo>? sessions;
  final bool sessionsLoading;
  final void Function(String id, String title, String? profile) onOpenSession;

  const ShellRecentPlaceholder({
    super.key,
    required this.sessions,
    required this.sessionsLoading,
    required this.onOpenSession,
  });

  @override
  Widget build(BuildContext context) {
    final list = (sessions ?? const <SessionInfo>[]).take(8).toList();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 24),
            children: [
              Text('Recent sessions', style: display(24)),
              const SizedBox(height: 6),
              Text(
                'Pick up where you left off, or start a new chat from Browse.',
                style: sans(12, height: 1.4, color: AppColors.fg3),
              ),
              const SizedBox(height: 18),
              if (sessionsLoading && sessions == null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.fg3,
                      ),
                    ),
                  ),
                )
              else if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No sessions yet.',
                    style: sans(12, color: AppColors.fg3),
                  ),
                )
              else
                ...list.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () => onOpenSession(s.id, s.title, s.profile),
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.title.isEmpty ? '(untitled)' : s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(13, color: AppColors.fg1),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                lastPathSegment(s.folder, ifEmpty: s.folder),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: mono(10, color: AppColors.fg3),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          relativeTime(s.lastActive),
                          style: mono(10, color: AppColors.fg3),
                        ),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
