import 'package:flutter/material.dart';

import '../api.dart';
import '../media_views.dart';
import '../menu_widgets.dart';
import '../panel.dart';
import '../theme.dart';
import '../widgets.dart';
import 'editor.dart';
import 'file_viewer.dart';

/// A file the agent handed over with `present_file`: one line with its name
/// and the agent's caption that opens it, and a download button.
class PresentedFileCard extends StatelessWidget {
  const PresentedFileCard({
    super.key,
    required this.client,
    required this.path,
    required this.caption,
    this.onOpenFileTab,
  });

  final DaemonClient client;
  final String path;
  final String caption;
  final void Function(String path, String name)? onOpenFileTab;

  String get _name => path.split('/').last;

  String get _ext {
    final dot = _name.lastIndexOf('.');
    return dot > 0 ? _name.substring(dot + 1).toLowerCase() : '';
  }

  String get _icon => switch (_ext) {
        'md' || 'markdown' || 'txt' || 'rst' || 'doc' || 'docx' => 'file-text',
        'html' || 'htm' => 'globe',
        'pdf' => 'pdf',
        'csv' || 'tsv' || 'xls' || 'xlsx' => 'list',
        'zip' || 'tar' || 'gz' || 'tgz' || 'apk' || 'dmg' => 'archive',
        'mp4' || 'mov' || 'webm' || 'mkv' => 'film',
        'mp3' || 'wav' || 'm4a' || 'ogg' => 'music',
        'json' || 'yaml' || 'yml' || 'toml' || 'rs' || 'dart' || 'py' || 'js' ||
        'ts' || 'tsx' || 'go' || 'sh' || 'sql' =>
          'file-code',
        _ => 'file',
      };

  void _open(BuildContext context) {
    if (openFileForViewing(context, client: client, path: path, name: _name)) {
      return;
    }
    if (onOpenFileTab != null) {
      onOpenFileTab!(path, _name);
      return;
    }
    presentScreen(
      context,
      builder: (_, close) =>
          EditorScreen(client: client, path: path, name: _name, onClose: close),
    );
  }

  Future<void> _download(BuildContext context) async {
    try {
      toast(context, 'Downloading $_name…');
      final msg = await downloadRemoteFileWithCancel(context, client,
          path: path, name: _name);
      if (msg != null && context.mounted) toast(context, msg);
    } catch (e) {
      if (context.mounted) toast(context, '$e', danger: true);
    }
  }

  Widget _downloadButton(BuildContext context) => Tooltip(
        message: 'Download',
        child: InkWell(
          onTap: () => _download(context),
          borderRadius: BorderRadius.circular(R.xs),
          child: SizedBox(
            width: 30,
            height: 26,
            child: Center(
                child: AppIcon('download', size: 14, color: AppColors.fg3)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (mediaKindOf(path) == MediaKind.image) return _image(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.s2),
        child: Row(children: [
          SizedBox(
            width: 16,
            child: Center(child: AppIcon(_icon, size: 14, color: AppColors.accent)),
          ),
          const SizedBox(width: S.s8),
          Expanded(
            child: Tooltip(
              message: path,
              waitDuration: const Duration(milliseconds: 600),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: _name, style: TS.ui(AppColors.fg1)),
                  if (caption.isNotEmpty)
                    TextSpan(text: '  $caption', style: TS.ui(AppColors.fg3)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: S.s4),
          _downloadButton(context),
        ]),
      ),
    );
  }

  Widget _image(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: double.infinity,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SingleImage(client: client, path: path),
          const SizedBox(height: S.s4),
          Row(children: [
            Expanded(
              child: Text(caption.isNotEmpty ? caption : _name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TS.meta(AppColors.fg3)),
            ),
            _downloadButton(context),
          ]),
        ]),
      ),
    );
  }
}

/// Files sent in one go: a single file is its own row; several share a header
/// and show the first few, with the rest a tap away.
class PresentedFiles extends StatefulWidget {
  const PresentedFiles({
    super.key,
    required this.client,
    required this.files,
    this.onOpenFileTab,
  });

  final DaemonClient client;
  final List<({String path, String caption})> files;
  final void Function(String path, String name)? onOpenFileTab;

  @override
  State<PresentedFiles> createState() => _PresentedFilesState();
}

class _PresentedFilesState extends State<PresentedFiles> {
  static const _shown = 3;
  bool _all = false;

  Future<void> _downloadAll() async {
    try {
      toast(context, 'Preparing ${widget.files.length} files…');
      final path = await widget.client
          .zipFiles('files', [for (final f in widget.files) f.path]);
      if (!mounted) return;
      final msg = await downloadRemoteFileWithCancel(context, widget.client,
          path: path, name: 'files.zip');
      if (msg != null && mounted) toast(context, msg);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Widget _row(({String path, String caption}) f) => PresentedFileCard(
        client: widget.client,
        path: f.path,
        caption: f.caption,
        onOpenFileTab: widget.onOpenFileTab,
      );

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    if (files.length == 1) return _row(files.first);
    final visible = _all ? files : files.take(_shown).toList();
    final hidden = files.length - visible.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, S.s4, 0, S.s2),
          child: Row(children: [
            Expanded(
              child: Text('Shared ${files.length} files',
                  style: TS.meta(AppColors.fg3)),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _downloadAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text('Download all', style: TS.meta(AppColors.accent)),
              ),
            ),
          ]),
        ),
        for (final f in visible) _row(f),
        if (hidden > 0 || (_all && files.length > _shown))
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _all = !_all),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, S.s4, 0, S.s4),
              child: Text(_all ? 'Show fewer' : 'Show $hidden more',
                  style: TS.meta(AppColors.accent)),
            ),
          ),
      ],
    );
  }
}
