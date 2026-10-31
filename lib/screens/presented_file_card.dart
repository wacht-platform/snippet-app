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
    this.grouped = false,
  });

  final DaemonClient client;
  final String path;
  final String caption;
  final bool grouped;
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
          customBorder: const CircleBorder(),
          child: Container(
            width: kMobile ? 36 : 28,
            height: kMobile ? 36 : 28,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: AppColors.surface3, shape: BoxShape.circle),
            child: AppIcon('download',
                size: kMobile ? 16 : 14, color: AppColors.fg2),
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
        grouped: grouped,
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
    this.grouped = false,
  });

  final String icon;
  final String name;
  final String detail;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final row = InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: kMobile ? 60 : 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(9),
              ),
              child: AppIcon(icon, size: 17, color: AppColors.fg2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(kMobile ? 14.5 : 13.5,
                          weight: W.label, color: AppColors.fg1)),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(kMobile ? 13 : 12, color: AppColors.fg4)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ]),
        ),
      ),
    );
    if (grouped) return Material(color: Colors.transparent, child: row);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: kMobile ? 4 : 3),
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: row,
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

  Widget _row(({String path, String caption}) f, {bool grouped = false}) =>
      PresentedFileCard(
        client: widget.client,
        path: f.path,
        caption: f.caption,
        onOpenFileTab: widget.onOpenFileTab,
        grouped: grouped,
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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Material(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0) Container(height: 1, color: AppColors.line),
                _row(visible[i], grouped: true),
              ],
            ]),
          ),
        ),
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
