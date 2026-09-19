import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Describe an agent in prose; the runtime researches and builds it.
///
/// ONE form, two hosts: Mission Control's agent directory presents it as a
/// sheet, and the shell's agents panel opens it as a popover under its "+".
/// It lives here rather than inside either host because a second copy is how
/// the two drift — the panel briefly grew its own variant that could not even
/// enable its submit button.
///
/// The prompt field is deliberately the whole form. The daemon takes only
/// `{prompt}` and derives name, handle, role and capabilities itself, so
/// exposing those as inputs would offer controls it ignores.
class CreateAgentForm extends StatefulWidget {
  const CreateAgentForm({super.key, required this.client});

  final DaemonClient client;

  @override
  State<CreateAgentForm> createState() => _CreateAgentFormState();
}

class _CreateAgentFormState extends State<CreateAgentForm> {
  final _prompt = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final prompt = _prompt.text.trim();
    // Validated here, not by disabling the button: `AppField` exposes no
    // `onChanged`, so a disabled-by-length budget could never rebuild as you
    // type and the button would stay dead.
    if (prompt.length < 12) {
      setState(() => _error = 'Describe the agent you want it to become.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.buildCoordinationAgent(prompt);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppField(
            controller: _prompt,
            hint: 'A security reviewer that inspects repos without changing them.',
            minLines: 4,
            maxLines: 6,
            autofocus: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: sans(12, color: AppColors.danger)),
          ],
          const SizedBox(height: 14),
                      Btn(
              _busy ? 'Starting build…' : 'Build agent',
              small: true,
              full: true,
            disabled: _busy,
            icon: 'sparkles',
            onTap: _submit,
          ),
        ],
      );
}
