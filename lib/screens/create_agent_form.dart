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
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Describe the agent in plain language. It will research the role, create its identity, and propose the tools it needs.',
              style: sans(13, color: AppColors.fg3, height: 1.45),
            ),
            const SizedBox(height: 18),
            AppField(
              controller: _prompt,
              label: 'What should this agent become?',
              hint:
                  'Create a Rust security reviewer that researches current dependency auditing practices and can inspect repositories without modifying them.',
              minLines: 5,
              maxLines: 8,
              autofocus: true,
            ),
            const SizedBox(height: 10),
            Text(
              'The agent chooses its name, personality, capabilities, and initial tool proposals from this brief.',
              style: sans(12, color: AppColors.fg4, height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: sans(12, color: AppColors.danger)),
            ],
            const SizedBox(height: 20),
            Btn(
              _busy ? 'Starting build…' : 'Build agent',
              full: true,
              disabled: _busy,
              icon: 'sparkles',
              onTap: _submit,
            ),
          ],
        ),
      );
}
