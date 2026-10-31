import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../diff_counts.dart';
import '../mochi.dart';
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

const _installCommand = 'curl -fsSL https://snippet.wacht.dev/install.sh | sh';

class ShellWelcomeView extends StatefulWidget {
  final VoidCallback onAddInstance;

  const ShellWelcomeView({super.key, required this.onAddInstance});

  @override
  State<ShellWelcomeView> createState() => _ShellWelcomeViewState();
}

class _ShellWelcomeViewState extends State<ShellWelcomeView> {
  bool _localRunning = false;

  @override
  void initState() {
    super.initState();
    if (!kMobile) _probeLocal();
  }

  Future<void> _probeLocal() async {
    try {
      final r = await http
          .get(Uri.parse('http://127.0.0.1:8787/health'))
          .timeout(const Duration(milliseconds: 900));
      if (mounted && r.statusCode == 200) setState(() => _localRunning = true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
              horizontal: kMobile ? 22 : 28, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                    child: MochiIcon(
                        color: const Color(0xFFB9C6FF), size: kMobile ? 64 : 56)),
                const SizedBox(height: 18),
                Text(
                  'Connect your computer',
                  textAlign: TextAlign.center,
                  style: display(kMobile ? 24 : 21),
                ),
                const SizedBox(height: 8),
                Text(
                  'snippet runs on your own computer. This app connects to it, '
                  'so you can ask Mission Control and follow the work from here.',
                  textAlign: TextAlign.center,
                  style: sans(kMobile ? 14 : 13,
                      height: 1.5, color: AppColors.fg3),
                ),
                const SizedBox(height: 26),
                _WelcomeStep(
                  n: '1',
                  title: 'Install snippet on your computer',
                  command: _installCommand,
                ),
                const SizedBox(height: 14),
                _WelcomeStep(
                  n: '2',
                  title: _localRunning
                      ? 'snippet is already running here. Show its link with'
                      : 'Start it',
                  command: _localRunning ? 'snippet serve --status' : 'snippet serve',
                  note: _localRunning ? null : 'It prints a link and a QR code.',
                ),
                const SizedBox(height: 14),
                _WelcomeStep(
                  n: '3',
                  title: kMobile
                      ? 'Scan the QR code, or paste the link'
                      : 'Paste the link here',
                ),
                const SizedBox(height: 24),
                Center(
                  child: PillBtn(
                    kMobile ? 'Scan or paste' : 'Connect',
                    icon: kMobile ? 'scan' : 'plus',
                    onTap: widget.onAddInstance,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.n, required this.title, this.command, this.note});
  final String n;
  final String title;
  final String? command;
  final String? note;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child: Text(n, style: sans(12, weight: W.label, color: AppColors.fg2)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(title,
                  style: sans(kMobile ? 14.5 : 13, color: AppColors.fg1)),
            ),
            if (command != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                decoration: BoxDecoration(
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(R.sm),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  Expanded(
                    child: SelectableText(command!,
                        style: mono(kMobile ? 12 : 11.5, color: AppColors.fg1)),
                  ),
                  IconBtn('copy', size: 30, iconSize: 13, tooltip: 'Copy', onTap: () {
                    Clipboard.setData(ClipboardData(text: command!));
                    toast(context, 'Copied');
                  }),
                ]),
              ),
            ],
            if (note != null) ...[
              const SizedBox(height: 6),
              Text(note!, style: sans(12, height: 1.4, color: AppColors.fg4)),
            ],
          ],
        ),
      ),
    ]);
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
              Text('Recent sessions', style: display(kMobile ? 24 : 20)),
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
                    child: Spinner(size: 20, color: AppColors.fg3),
                  ),
                )
              else if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No sessions yet.',
                    style: TS.meta(),
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
                                lastPathSegment(s.projectFolder,
                                    ifEmpty: s.projectFolder),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: mono(10, color: AppColors.fg3),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              relativeTime(s.lastActive),
                              style: mono(10, color: AppColors.fg3),
                            ),
                            DiffCounts(s, size: 10.5),
                          ],
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
