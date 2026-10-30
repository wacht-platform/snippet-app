import 'package:flutter/material.dart';

import 'platform.dart';
import 'settings_form.dart';
import 'theme.dart';
import 'widgets.dart';

class InlineKeyRow extends StatefulWidget {
  const InlineKeyRow({
    super.key,
    required this.label,
    required this.keySet,
    required this.hint,
    required this.onSave,
    this.busy = false,
    this.optional = false,
  });
  final String label;
  final bool keySet;
  final String hint;
  final Future<void> Function(String key) onSave;
  final bool busy;
  final bool optional;

  @override
  State<InlineKeyRow> createState() => _InlineKeyRowState();
}

class _InlineKeyRowState extends State<InlineKeyRow> {
  final _ctl = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final k = _ctl.text.trim();
    if (k.isEmpty) return;
    await widget.onSave(k);
    if (mounted) {
      _ctl.clear();
      setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      final status = Text(widget.keySet ? 'Set' : 'Not set',
          style: sans(kMobile ? 15 : 13,
              color: widget.keySet || widget.optional
                  ? AppColors.fg3
                  : AppColors.danger));
      return SettingsRow(
        label: widget.label,
        onTap: widget.busy ? null : () => setState(() => _editing = true),
        trailing: kMobile
            ? status
            : Row(mainAxisSize: MainAxisSize.min, children: [
                status,
                const SizedBox(width: S.s12),
                Btn(widget.keySet ? 'Replace' : 'Add key',
                    small: true,
                    variant: BtnVariant.secondary,
                    onTap: widget.busy
                        ? null
                        : () => setState(() => _editing = true)),
              ]),
        chevron: kMobile,
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: kMobile ? 16 : 14, vertical: kMobile ? 12 : 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.keySet ? 'Replace ${widget.label}' : widget.label,
            style: sans(kMobile ? 15 : 13, color: AppColors.fg1)),
        const SizedBox(height: 8),
        TextField(
          controller: _ctl,
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => _submit(),
          style: sans(kMobile ? 15 : 13, color: AppColors.fg1),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            hintStyle: sans(kMobile ? 14 : 12.5, color: AppColors.fg4),
            filled: true,
            fillColor: AppColors.surface2,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Btn('Cancel',
              small: true,
              variant: BtnVariant.secondary,
              onTap: () => setState(() {
                    _ctl.clear();
                    _editing = false;
                  })),
          const SizedBox(width: 8),
          Btn('Save key', small: true, onTap: widget.busy ? null : _submit),
        ]),
      ]),
    );
  }
}
