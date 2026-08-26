/// Mobile Mission Control — full-screen, single column. The MC agent lives in
/// the header, the activity feed is the body, the composer is pinned to the
/// bottom. Tap a task to expand it in a draggable bottom sheet; tap the bell
/// to see unresolved notifications.
library;

import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets.dart';
import '../mission_control_screen.dart' show ChangeNotifierProvider;
import '../mission_control_state.dart';
import '../widgets/mission_control_header.dart';
import '../widgets/activity_feed.dart';
import '../widgets/mission_composer.dart';
import '../widgets/task_detail_sheet.dart';
import '../widgets/notification_inbox.dart';

class MobileMissionControl extends StatelessWidget {
  const MobileMissionControl({super.key});

  @override
  Widget build(BuildContext context) {
    final state = ChangeNotifierProvider.of<MissionControlState>(context);
    return Scaffold(
      backgroundColor: readingBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            MissionControlHeader.compact(state: state),
            Expanded(
              child: ActivityFeed(
                state: state,
                onTapTask: (task) => _openTaskSheet(context, state, task),
                onTapQuestion: (question) =>
                    _openQuestionReply(context, state, question),
              ),
            ),
            MissionComposer(state: state),
          ],
        ),
      ),
    );
  }

  Future<void> _openTaskSheet(
    BuildContext context,
    MissionControlState state,
    task,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => TaskDetailSheet(task: task, state: state),
    );
    if (state.hasListeners) {
      state.refresh(silent: true);
    }
  }

  Future<void> _openQuestionReply(
    BuildContext context,
    MissionControlState state,
    QuestionItem q,
  ) async {
    final controller = TextEditingController();
    final reply = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            20,
            16,
            16 + MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Agent is asking'),
              const SizedBox(height: 8),
              Text(q.question, style: sans(14, color: AppColors.fg1)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                minLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Type your reply…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(sheetCtx, controller.text.trim()),
                    child: const Text('Send'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (reply != null && reply.isNotEmpty) {
      await state.sendMessage(reply);
    }
  }
}

/// Convenience re-export so the inbox popover can be opened from anywhere.
Future<void> showNotificationInbox(
  BuildContext context,
  MissionControlState state,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => NotificationInbox(state: state),
    );
