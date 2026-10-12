import 'package:flutter/material.dart';

import '../api.dart';
import '../media_views.dart';
import '../menu_widgets.dart';
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'editor.dart';
import 'file_viewer.dart';

/// A file the agent handed over with `present_file`: what it is, the agent's
/// caption, and where it lives, with Open and Download.
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

  String get _folder {
    final cut = path.lastIndexOf('/');
    return cut > 0 ? path.substring(0, cut) : '';
  }

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

  Widget _downloadButton(BuildContext context) => IconBtn('download',
      size: 32,
      iconSize: 16,
      tooltip: 'Download',
      onTap: () => _download(context));

  @override
  Widget build(BuildContext context) {
    if (mediaKindOf(path) == MediaKind.image) return _image(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.border2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: AppIcon(_icon, size: 18, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(14, weight: W.label, color: AppColors.fg1)),
                    if (caption.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13, height: 18 / 13, color: AppColors.fg2)),
                    ],
                    if (_folder.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                          _ext.isEmpty
                              ? _folder
                              : '${_ext.toUpperCase()} · $_folder',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono(11.5, color: AppColors.fg4)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!kMobile) ...[
                TextButton(
                  onPressed: () => _open(context),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    backgroundColor: AppColors.surface2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(R.sm)),
                  ),
                  child: Text('Open',
                      style: sans(12.5, weight: W.label, color: AppColors.fg1)),
                ),
                const SizedBox(width: 4),
              ],
              _downloadButton(context),
            ]),
          ),
        ),
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
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (caption.isNotEmpty)
                    Text(caption,
                        style: sans(13, height: 18 / 13, color: AppColors.fg2)),
                  Text(_name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(11.5, color: AppColors.fg4)),
                ],
              ),
            ),
            _downloadButton(context),
          ]),
        ]),
      ),
    );
  }
}
