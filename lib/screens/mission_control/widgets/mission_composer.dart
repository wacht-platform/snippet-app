/// Same tall outlined composer as the session input bar: "Ask anything",
/// circular send, no extra chrome.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../platform.dart';
import '../../../theme.dart';
import '../../../widgets.dart';
import '../mission_control_state.dart';

class MissionComposer extends StatefulWidget {
  const MissionComposer({super.key, required this.state});
  final MissionControlState state;

  @override
  State<MissionComposer> createState() => _MissionComposerState();
}

class _MissionComposerState extends State<MissionComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void deactivate() {
    _focus.unfocus();
    super.deactivate();
  }

  @override
  void dispose() {
    _focus.unfocus();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !widget.state.sending && _controller.text.trim().isNotEmpty;

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.state.sending) return;
    widget.state.sendMessage(text);
    _controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sending = widget.state.sending;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(R.card),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.fromLTRB(18, 20, 12, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): () {
                  if (!kMobile && _canSend) _send();
                },
                const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                    () {
                  if (_canSend) _send();
                },
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    () {
                  if (_canSend) _send();
                },
              },
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                minLines: 1,
                maxLines: 8,
                cursorColor: AppColors.fg1,
                onSubmitted: (_) => _send(),
                onChanged: (_) => setState(() {}),
                style: sans(16, height: 1.45, color: AppColors.fg1),
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.fromLTRB(2, 4, 8, 14),
                  border: InputBorder.none,
                  hintText: 'Ask anything',
                  hintStyle: sans(16, height: 1.45, color: AppColors.fg4),
                ),
              ),
            ),
            Row(children: [
              const Spacer(),
              Material(
                color: _canSend || sending ? AppColors.fg1 : AppColors.surface2,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: sending || !_canSend ? null : _send,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: sending
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.bg,
                              ),
                            )
                          : AppIcon('arrow-up',
                              size: 16,
                              color: _canSend ? AppColors.bg : AppColors.fg4),
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
