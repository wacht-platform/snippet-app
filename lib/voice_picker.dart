import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

class PickVoice {
  const PickVoice(this.id, this.name, {this.sub = '', this.group = ''});
  final String id;
  final String name;
  final String sub;
  final String group;
}

const _langNames = {
  'eng': 'English',
  'spa': 'Spanish',
  'fra': 'French',
  'ger': 'German',
  'por': 'Portuguese',
  'jpn': 'Japanese',
  'ara': 'Arabic',
  'hin': 'Hindi',
  'ita': 'Italian',
  'nld': 'Dutch',
};

Map<String, dynamic>? _rimeCatalogue;

Future<List<PickVoice>> rimeVoices(String model) async {
  try {
    _rimeCatalogue ??= jsonDecode((await http
            .get(Uri.parse('https://users.rime.ai/data/voices/all-v2.json'))
            .timeout(const Duration(seconds: 8)))
        .body) as Map<String, dynamic>;
  } catch (_) {
    return const [];
  }
  final langs = _rimeCatalogue?[model];
  if (langs is! Map) return const [];
  return [
    for (final e in langs.entries)
      for (final v in (e.value as List))
        PickVoice('$v', '${'$v'[0].toUpperCase()}${'$v'.substring(1)}',
            group: _langNames[e.key] ?? '${e.key}'),
  ];
}

Future<String?> showVoicePicker(BuildContext context,
    {required String title,
    required List<PickVoice> voices,
    required String selected}) {
  return showAppSheet<String>(context,
      title: title,
      maxWidth: 420,
      maxHeight: 560,
      child: _VoicePicker(voices: voices, selected: selected));
}

class _VoicePicker extends StatefulWidget {
  const _VoicePicker({required this.voices, required this.selected});
  final List<PickVoice> voices;
  final String selected;

  @override
  State<_VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<_VoicePicker> {
  String _q = '';
  String? _group;

  @override
  Widget build(BuildContext context) {
    final groups = <String>[
      for (final g in widget.voices.map((v) => v.group).toSet())
        if (g.isNotEmpty) g
    ];
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final v in widget.voices)
        if ((_group == null || v.group == _group) &&
            (q.isEmpty ||
                v.name.toLowerCase().contains(q) ||
                v.sub.toLowerCase().contains(q)))
          v
    ];
    final h = MediaQuery.of(context).size.height;
    return SizedBox(
      height: (h * 0.62).clamp(320.0, 460.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          onChanged: (v) => setState(() => _q = v),
          style: sans(kMobile ? 15 : 13, color: AppColors.fg1),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search ${widget.voices.length} voices',
            hintStyle: sans(kMobile ? 14 : 12.5, color: AppColors.fg4),
            filled: true,
            fillColor: AppColors.surface2,
            prefixIcon: Padding(
              padding: const EdgeInsets.all(12),
              child: AppIcon('search', size: 14, color: AppColors.fg4),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none),
          ),
        ),
        if (groups.length > 1) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _chip('All', _group == null, () => setState(() => _group = null)),
              for (final g in groups)
                _chip(g, _group == g, () => setState(() => _group = g)),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text('No voices match',
                      style: sans(13, color: AppColors.fg4)))
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final v = shown[i];
                    final on = v.id == widget.selected;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => Navigator.pop(context, v.id),
                      child: Container(
                        constraints:
                            BoxConstraints(minHeight: kMobile ? 48 : 38),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: on ? AppColors.surface2 : null,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(v.name,
                                      style: sans(kMobile ? 15 : 13,
                                          color: AppColors.fg1)),
                                  if (v.sub.isNotEmpty)
                                    Text(v.sub,
                                        style: sans(12, color: AppColors.fg4)),
                                ]),
                          ),
                          if (v.group.isNotEmpty && _group == null)
                            Text(v.group,
                                style: sans(12, color: AppColors.fg4)),
                          if (on) ...[
                            const SizedBox(width: 10),
                            AppIcon('check', size: 14, color: AppColors.fg1),
                          ],
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: on ? AppColors.fg1 : AppColors.surface2,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(label,
                style: sans(12.5, color: on ? AppColors.bg : AppColors.fg3)),
          ),
        ),
      );
}
