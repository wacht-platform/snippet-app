/// Same tall outlined composer as the session input bar: "Ask anything",
/// circular send, no extra chrome.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../drafts.dart';
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

  // Unsent text survives leaving Mission Control, like a session's draft.
  String get _draftKey =>
      Drafts.keyFor(widget.state.client.baseUrl, 'mission-control');

  void _saveDraft() =>
      Drafts.instance.save(_draftKey, Draft(text: _controller.text));

  @override
  void initState() {
    super.initState();
    _controller.text = Drafts.instance.of(_draftKey)?.text ?? '';
    _controller.addListener(_saveDraft);
  }

  @override
  void deactivate() {
    _focus.unfocus();
    super.deactivate();
  }

  @override
  void dispose() {
    _focus.unfocus();
    _controller.removeListener(_saveDraft);
    Drafts.instance.save(_draftKey, Draft(text: _controller.text), now: true);
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
        kMobile ? M.gutter : 20,
        8,
        kMobile ? M.gutter : 20,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.raised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        padding: kMobile
            ? const EdgeInsets.fromLTRB(14, 14, 12, 12)
            : const EdgeInsets.fromLTRB(14, 12, 12, 12),
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
                cursorColor: AppColors.accent,
                onSubmitted: (_) => _send(),
                onChanged: (_) => setState(() {}),
                style: TS.body(AppColors.fg1),
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.fromLTRB(2, 4, 8, 14),
                  border: InputBorder.none,
                  hintText: 'Ask anything',
                  hintStyle: TS.body(AppColors.fg4),
                ),
              ),
            ),
            Row(children: [
              const Spacer(),
              Material(
                color: _canSend || sending
                    ? AppColors.accentFill
                    : AppColors.hover,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  customBorder: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  onTap: sending || !_canSend ? null : _send,
                  child: SizedBox(
                    width: kMobile ? 40 : 36,
                    height: kMobile ? 40 : 36,
                    child: Center(
                      child: sending
                          ? Spinner(size: 14, color: AppColors.accentFg)
                          : AppIcon('arrow-up',
                              size: 16,
                              color: _canSend
                                  ? AppColors.accentFg
                                  : AppColors.fg4),
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
