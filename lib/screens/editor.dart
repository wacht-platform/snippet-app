import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../api.dart';
import '../highlight.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Editable code view for one file. Loads via /fs/file, edits with re_editor
/// (syntax highlighting + line numbers), saves via /fs/write with optimistic
/// concurrency — if the file changed on disk since open, the user chooses to
/// overwrite or reload. Binary/oversized files are refused (read-only viewer).
class EditorScreen extends StatefulWidget {
  final DaemonClient client;
  final String path;
  final String name;
  final VoidCallback? onClose; // dismiss when hosted in a desktop panel
  const EditorScreen(
      {super.key,
      required this.client,
      required this.path,
      required this.name,
      this.onClose});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final CodeLineEditingController _controller = CodeLineEditingController();
  final FocusNode _focus = FocusNode();
  bool _wrap = kMobile;
  String _hash = '';
  String _initial = '';
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _focus.addListener(_onFocus);
    _load();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  // Whether the file arrived with CRLF endings (restored on save).
  bool _crlf = false;

  String _normalized(String s) =>
      s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  String _forSave() {
    final text = _normalized(_controller.text);
    return _crlf ? text.replaceAll('\n', '\r\n') : text;
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  void _onChanged() {
    final d = _normalized(_controller.text) != _initial;
    if (d != _dirty && mounted) setState(() => _dirty = d);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final f = await widget.client.readFile(widget.path);
      if (!mounted) return;
      if (!f.editable) {
        setState(() {
          _error = f.binary
              ? 'Binary file — not editable.'
              : 'File is too large to edit safely.';
          _loading = false;
        });
        return;
      }
      // The editor normalizes to LF internally: remember the file's dominant
      // line ending so the dirty check compares like-for-like and save restores
      // the original style instead of rewriting every line ending.
      _crlf = f.content.contains('\r\n');
      _initial = _normalized(f.content);
      _hash = f.hash;
      _controller.text = f.content;
      setState(() {
        _loading = false;
        _dirty = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save({bool force = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final r = await widget.client
          .writeFile(widget.path, _forSave(), prevHash: force ? null : _hash);
      if (!mounted) return;
      if (r['ok'] == true) {
        _initial = _normalized(_controller.text);
        _hash = r['hash'] as String? ?? _hash;
        setState(() {
          _dirty = false;
          _saving = false;
        });
        toast(context, 'Saved');
        return;
      }
      setState(() => _saving = false);
      if (r['conflict'] == true) {
        await _conflictSheet();
      } else {
        toast(context, (r['error'] as String?) ?? 'Save failed', danger: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        toast(context, '$e', danger: true);
      }
    }
  }

  Future<void> _conflictSheet() async {
    final choice = await showAppSheet<String>(context,
        title: 'File changed on disk',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                'This file was modified on the server since you opened it (likely by the agent). Keep your version, or reload theirs and lose your edits?',
                style: TS.ui()),
            const SizedBox(height: 16),
            Btn('Overwrite with mine',
                icon: 'check',
                onTap: () => Navigator.pop(context, 'overwrite')),
            const SizedBox(height: 8),
            Btn('Reload theirs',
                variant: BtnVariant.secondary,
                onTap: () => Navigator.pop(context, 'reload')),
            const SizedBox(height: 8),
            Btn('Cancel',
                variant: BtnVariant.ghost, onTap: () => Navigator.pop(context)),
          ],
        ));
    if (choice == 'overwrite') {
      await _save(force: true);
    } else if (choice == 'reload') {
      await _load();
    }
  }

  void _exit() => (widget.onClose ?? () => Navigator.pop(context))();

  Future<void> _maybePop() async {
    if (!_dirty) {
      _exit();
      return;
    }
    final discard = await confirmAction(
      context,
      title: 'Discard changes?',
      body: 'You have unsaved edits to this file.',
      confirmLabel: 'Discard',
    );
    if (discard && mounted) _exit();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _maybePop();
      },
      child: Scaffold(
        backgroundColor: readingBg,
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            SnAppBar(
              title: widget.name,
              subtitle: _folder,
              onBack: _maybePop,
              actions: [
                if (!_loading && _error == null) ...[
                  ValueListenableBuilder<CodeLineEditingValue>(
                    valueListenable: _controller,
                    builder: (_, __, ___) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconBtn('undo',
                            size: 36,
                            iconSize: 18,
                            tooltip: 'Undo',
                            onTap:
                                _controller.canUndo ? _controller.undo : null),
                        IconBtn('redo',
                            size: 36,
                            iconSize: 18,
                            tooltip: 'Redo',
                            onTap:
                                _controller.canRedo ? _controller.redo : null),
                      ],
                    ),
                  ),
                  IconBtn('wrap',
                      size: 36,
                      iconSize: 18,
                      active: _wrap,
                      tooltip: _wrap ? 'Stop wrapping lines' : 'Wrap lines',
                      onTap: () => setState(() => _wrap = !_wrap)),
                  const SizedBox(width: S.s4),
                  Btn(_saving ? 'Saving' : 'Save',
                      small: true,
                      variant:
                          _dirty ? BtnVariant.primary : BtnVariant.secondary,
                      disabled: _saving || !_dirty,
                      onTap: () => _save()),
                  const SizedBox(width: S.s8),
                ],
              ],
            ),
            if (_saving)
              LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: AppColors.surface2,
                  color: AppColors.accent),
            if (_loading)
              const Expanded(child: Center(child: DelayedSpinner(size: 22)))
            else if (_error != null)
              Expanded(
                  child: EmptyState(
                      icon: 'file', title: "Can't edit", body: _error!))
            else ...[
              Expanded(
                child: CodeEditor(
                  controller: _controller,
                  focusNode: _focus,
                  wordWrap: _wrap,
                  padding: const EdgeInsets.fromLTRB(S.s4, S.s8, S.s12, S.s32),
                  style: codeEditorStyle(widget.name),
                  indicatorBuilder:
                      (context, editingController, chunkController, notifier) {
                    return Row(children: [
                      DefaultCodeLineNumber(
                          controller: editingController, notifier: notifier),
                      if (kMobile) const SizedBox(width: S.s8),
                      if (!kMobile)
                        DefaultCodeChunkIndicator(
                            width: 20,
                            controller: chunkController,
                            notifier: notifier),
                    ]);
                  },
                ),
              ),
              if (kMobile && _focus.hasFocus)
                _KeyBar(controller: _controller, onDone: _focus.unfocus),
            ],
          ]),
        ),
      ),
    );
  }

  String get _folder {
    final i = widget.path.lastIndexOf('/');
    if (i <= 0) return widget.path;
    final dir = widget.path.substring(0, i);
    final parts = dir.split('/').where((p) => p.isNotEmpty).toList();
    return parts.length <= 2
        ? dir
        : '…/${parts.sublist(parts.length - 2).join('/')}';
  }
}

class _KeyBar extends StatelessWidget {
  const _KeyBar({required this.controller, required this.onDone});

  final CodeLineEditingController controller;
  final VoidCallback onDone;

  static const _symbols = [
    '{',
    '}',
    '(',
    ')',
    '[',
    ']',
    '<',
    '>',
    '=',
    ';',
    ':',
    '"',
    "'",
    '/',
    '\\',
    '|',
    '&',
    '_',
    '-',
    '+',
    '*',
    '!',
    '?',
    '#',
    r'$',
    '%',
    '`',
    '~',
  ];

  void _tap(VoidCallback action) {
    HapticFeedback.selectionClick();
    action();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: AppColors.overlay,
      child: Row(children: [
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: S.s6, vertical: S.s6),
            children: [
              _Key(label: 'Tab', onTap: () => _tap(controller.applyIndent)),
              _Key(
                  icon: 'arrow-left',
                  onTap: () =>
                      _tap(() => controller.moveCursor(AxisDirection.left))),
              _Key(
                  icon: 'arrow-right',
                  onTap: () =>
                      _tap(() => controller.moveCursor(AxisDirection.right))),
              _Key(
                  icon: 'chevron-up',
                  onTap: () =>
                      _tap(() => controller.moveCursor(AxisDirection.up))),
              _Key(
                  icon: 'chevron-down',
                  onTap: () =>
                      _tap(() => controller.moveCursor(AxisDirection.down))),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(
                    horizontal: S.s6, vertical: S.s6),
                color: AppColors.line,
              ),
              for (final sym in _symbols)
                _Key(
                    label: sym,
                    onTap: () => _tap(() => controller.replaceSelection(sym))),
            ],
          ),
        ),
        _Key(icon: 'keyboard', onTap: () => _tap(onDone)),
        const SizedBox(width: S.s6),
      ]),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, required this.onTap});

  final String? label;
  final String? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.s2),
      child: Material(
        color: AppColors.hover,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(R.sm),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 36),
            padding: const EdgeInsets.symmetric(horizontal: S.s8),
            alignment: Alignment.center,
            child: icon != null
                ? AppIcon(icon!, size: 16, color: AppColors.fg1)
                : Text(label!, style: TS.code(AppColors.fg1)),
          ),
        ),
      ),
    );
  }
}
