import 'package:flutter/material.dart';

import '../api.dart';
import '../media_views.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'file_viewer.dart';

/// A file the agent handed over with `present_file`: a card on a phone and a
/// compact line on desktop, opening the file, with a download button.
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
    presentFileOnDesktop(context, client: client, path: path, name: _name);
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

  String get _kindLabel => switch (_icon) {
        'file-text' => 'Document',
        'globe' => 'Web page',
        'pdf' => 'PDF',
        'list' => 'Table',
        'archive' => 'Archive',
        'film' => 'Video',
        'music' => 'Audio',
        'file-code' => 'Code',
        _ => _ext.isEmpty ? 'File' : _ext.toUpperCase(),
      };

  Widget _downloadButton(BuildContext context) => Tooltip(
        message: 'Download',
        child: InkWell(
          onTap: () => _download(context),
          borderRadius: BorderRadius.circular(R.xs),
          child: SizedBox(
            width: kMobile ? 40 : 28,
            height: kMobile ? 40 : 24,
            child: Center(
                child: AppIcon('download',
                    size: kMobile ? 18 : 14, color: AppColors.fg3)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (mediaKindOf(path) == MediaKind.image) return _image(context);
    return Tooltip(
      message: path,
      waitDuration: const Duration(milliseconds: 600),
      child: MediaRow(
        icon: _icon,
        name: _name,
        detail: [_kindLabel, if (caption.isNotEmpty) caption].join(' · '),
        onTap: () => _open(context),
        trailing: _downloadButton(context),
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

class MediaRow extends StatelessWidget {
  const MediaRow({
    super.key,
    required this.icon,
    required this.name,
    required this.detail,
    required this.onTap,
    this.trailing,
  });

  final String icon;
  final String name;
  final String detail;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final nameStyle = sans(kMobile ? 14 : 13.5, weight: W.label, color: AppColors.fg1);
    final detailStyle = sans(kMobile ? 13 : 12.5, color: AppColors.fg3);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: kMobile ? 4 : 3),
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: kMobile ? 52 : 40),
            child: Padding(
              padding: EdgeInsets.fromLTRB(kMobile ? 10 : 8, 0, 8, 0),
              child: Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accentBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: AppIcon(icon, size: 16, color: AppColors.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: kMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: nameStyle),
                            if (detail.isNotEmpty)
                              Text(detail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: detailStyle),
                          ],
                        )
                      : Text.rich(
                          TextSpan(children: [
                            TextSpan(text: name, style: nameStyle),
                            if (detail.isNotEmpty)
                              TextSpan(text: '  $detail', style: detailStyle),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 4),
                  trailing!,
                ],
                const SizedBox(width: 4),
                AppIcon('chevron-right', size: 14, color: AppColors.fg4),
                const SizedBox(width: 4),
              ]),
            ),
          ),
        ),
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
          padding: const EdgeInsets.fromLTRB(2, S.s4, 0, S.s2),
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
              padding: const EdgeInsets.fromLTRB(2, S.s4, 0, S.s4),
              child: Text(_all ? 'Show fewer' : 'Show $hidden more',
                  style: TS.meta(AppColors.accent)),
            ),
          ),
      ],
    );
  }
}
