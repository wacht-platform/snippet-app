import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../menu_widgets.dart';
import '../mochi.dart';
import '../models.dart';
import '../panel.dart';
import '../theme.dart';
import '../widgets.dart';
import 'new_session_picker.dart';

class NewSessionDraft extends StatefulWidget {
  const NewSessionDraft({
    super.key,
    required this.client,
    required this.machineLabel,
    required this.onStart,
    this.folder,
  });

  final DaemonClient client;
  final String machineLabel;
  final String? folder;
  final Future<void> Function(
          String folder, WorkspaceMode mode, String? profile, String text)
      onStart;

  @override
  State<NewSessionDraft> createState() => _NewSessionDraftState();
}

class _NewSessionDraftState extends State<NewSessionDraft> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  String? _folder;
  WorkspaceMode _mode = WorkspaceMode.worktree;
  bool _isRepo = false;
  String? _branch;
  List<InferenceProfile> _profiles = const [];
  String? _profile;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _folder = widget.folder;
    _input.addListener(() => setState(() {}));
    _loadRepo();
    _loadProfiles();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    try {
      final cfg = await widget.client.getConfig();
      if (!mounted) return;
      setState(() {
        _profiles = cfg.profiles;
        _profile = cfg.active ??
            cfg.profiles.where((p) => p.active).firstOrNull?.name;
      });
    } catch (_) {}
  }

  Future<void> _loadRepo() async {
    final f = _folder;
    if (f == null || f.isEmpty) {
      setState(() {
        _isRepo = false;
        _branch = null;
      });
      return;
    }
    try {
      final r = await widget.client.worktrees(f);
      if (!mounted || _folder != f) return;
      final main = r.worktrees.where((w) => w.path == r.repo).firstOrNull ??
          r.worktrees.firstOrNull;
      setState(() {
        _isRepo = r.repo != null;
        _branch = main?.branch;
        if (!_isRepo) _mode = WorkspaceMode.folder;
      });
    } catch (_) {
      if (mounted) setState(() => _isRepo = false);
    }
  }

  Future<void> _pickFolder() async {
    await presentScreen(
      context,
      style: PanelStyle.dialog,
      maxWidth: 440,
      maxHeight: 500,
      builder: (_, close) => NewSessionPicker(
        client: widget.client,
        machineLabel: widget.machineLabel,
        startPath: _folder,
        onClose: close,
        onOpenFolder: (folder, mode) async {
          setState(() {
            _folder = folder;
            _mode = mode;
          });
          close();
          _loadRepo();
        },
      ),
    );
    if (mounted) _focus.requestFocus();
  }

  Future<void> _start() async {
    final text = _input.text.trim();
    if (_starting) return;
    if (_folder == null) {
      await _pickFolder();
      return;
    }
    if (text.isEmpty) return;
    setState(() => _starting = true);
    try {
      await widget.onStart(_folder!, _mode, _profile, text);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _pickProfile(BuildContext anchor) async {
    if (_profiles.isEmpty) return;
    final picked = await showAppMenu<String>(
      anchor,
      items: [
        for (final p in _profiles)
          appMenuItem(
              value: p.name,
              label: p.name,
              detail: p.model,
              selected: p.name == _profile),
      ],
    );
    if (picked != null && mounted) setState(() => _profile = picked);
  }

  Widget _chip(String icon, String label,
          {VoidCallback? onTap, bool filled = false}) =>
      Material(
        color: filled ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(icon, size: 13, color: AppColors.fg3),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12.5, color: AppColors.fg3)),
              ),
            ]),
          ),
        ),
      );

  Widget _worktreeToggle() {
    final on = _mode == WorkspaceMode.worktree;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => setState(() => _mode =
            on ? WorkspaceMode.folder : WorkspaceMode.worktree),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 22,
              height: 13,
              padding: const EdgeInsets.all(2),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: on
                    ? AppColors.accent.withValues(alpha: 0.35)
                    : AppColors.surface3,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: on ? AppColors.accent : AppColors.fg4,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Text('Worktree',
                style: sans(12.5, color: on ? AppColors.fg2 : AppColors.fg4)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final folderName = _folder == null
        ? 'Choose folder'
        : lastPathSegment(_folder!, ifEmpty: _folder!);
    final current = _profiles.where((p) => p.name == _profile).firstOrNull;
    final canSend = !_starting && _input.text.trim().isNotEmpty;
    return Container(
      color: AppColors.bg,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 70),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const DottedMochi(width: 300),
                  const SizedBox(height: 10),
                  Text('What are we making?',
                      style: sans(26, spacing: -0.5, color: AppColors.fg1)),
                  const SizedBox(height: 26),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 660),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface1,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            child: Wrap(spacing: 6, children: [
                              _chip('folder', folderName,
                                  filled: true, onTap: _pickFolder),
                              if (_isRepo && (_branch ?? '').isNotEmpty)
                                _chip('git-branch', _branch!),
                              if (_isRepo) _worktreeToggle(),
                            ]),
                          ),
                          CallbackShortcuts(
                            bindings: {
                              const SingleActivator(LogicalKeyboardKey.enter):
                                  _start,
                            },
                            child: TextField(
                              controller: _input,
                              focusNode: _focus,
                              minLines: 2,
                              maxLines: 10,
                              style: sans(14.5,
                                  height: 1.5, color: AppColors.fg1),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.fromLTRB(18, 12, 18, 6),
                                hintText: 'Ask, build, or type / for commands',
                                hintStyle:
                                    sans(14.5, color: AppColors.fg4),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                            child: Row(children: [
                              const Spacer(),
                              if (current != null)
                                Builder(
                                  builder: (anchor) => Material(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(15),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(15),
                                      onTap: () => _pickProfile(anchor),
                                      child: Container(
                                        height: 30,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10),
                                        child: Row(children: [
                                          ProviderLogo(current.provider,
                                              size: 13),
                                          const SizedBox(width: 7),
                                          Text(current.name,
                                              style: sans(12.5,
                                                  color: AppColors.fg2)),
                                          if (current
                                              .reasoningEffort.isNotEmpty) ...[
                                            const SizedBox(width: 5),
                                            Text(
                                                current.reasoningEffort[0]
                                                        .toUpperCase() +
                                                    current.reasoningEffort
                                                        .substring(1),
                                                style: sans(12.5,
                                                    color: AppColors.fg4)),
                                          ],
                                        ]),
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 6),
                              Material(
                                color: canSend
                                    ? AppColors.fg1
                                    : AppColors.surface2,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: canSend ? _start : null,
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: Center(
                                      child: _starting
                                          ? const Spinner(size: 14)
                                          : AppIcon('arrow-up',
                                              size: 16,
                                              color: canSend
                                                  ? AppColors.bg
                                                  : AppColors.fg4),
                                    ),
                                  ),
                                ),
                              ),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
