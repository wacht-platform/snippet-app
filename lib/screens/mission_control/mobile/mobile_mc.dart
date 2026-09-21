library;

import 'package:flutter/material.dart';

import '../../../panel.dart';
import '../../../platform.dart';
import '../../../theme.dart';
import '../../../widgets.dart';
import '../mission_control_screen.dart' show ChangeNotifierProvider;
import '../mission_control_state.dart';
import '../widgets/mission_control_header.dart';
import '../widgets/activity_feed.dart';
import '../widgets/mission_composer.dart';
import '../widgets/task_detail_sheet.dart';
import '../widgets/notification_inbox.dart';

Future<void> showMissionControlPanel(
  BuildContext context,
  Widget child,
) {
  if (!kMobile) {
    return presentScreen<void>(
      context,
      style: PanelStyle.drawer,
      builder: (_, close) => child,
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.56),
    builder: (sheetContext) {
      final height = MediaQuery.sizeOf(sheetContext).height * 0.92;
      return SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Material(
            color: AppColors.bg,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(R.sheetTop),
            ),
            child: Column(children: [
              const SizedBox(height: 8),
              Container(
                width: 30,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(child: child),
            ]),
          ),
        ),
      );
    },
  );
}

/// Mobile Mission Control — full-screen, single column. The MC agent lives in
/// the header, the activity feed is the body, the composer is pinned to the
/// bottom. Tap a task to expand it in a draggable bottom sheet; tap the bell
/// to see unresolved notifications.
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
    if (!kMobile) {
      await presentScreen<void>(
        context,
        style: PanelStyle.drawer,
        builder: (_, close) => TaskDetailSheet(task: task, state: state),
      );
      state.refresh(silent: true);
      return;
    }
    await showMissionControlPanel(
      context,
      TaskDetailSheet(task: task, state: state),
    );
    state.refresh(silent: true);
  }

  Future<void> _openQuestionReply(
    BuildContext context,
    MissionControlState state,
    QuestionItem q,
  ) async {
    final controller = TextEditingController();
    Widget buildBody(BuildContext ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(ctx, controller.text.trim()),
                  child: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final String? reply;
    if (!kMobile) {
      reply = await showAppSheet<String>(
        context,
        title: 'Reply to agent',
        maxWidth: 480,
        child: Builder(builder: buildBody),
      );
    } else {
      reply = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.bg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheetCtx) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: buildBody(sheetCtx),
        ),
      );
    }
    if (reply != null && reply.isNotEmpty) {
      await state.sendMessage(reply);
    }
  }
}

/// Convenience re-export so the inbox popover can be opened from anywhere.
Future<void> showNotificationInbox(
  BuildContext context,
  MissionControlState state,
) {
  if (!kMobile) {
    return presentScreen<void>(
      context,
      style: PanelStyle.drawer,
      builder: (_, close) => NotificationInbox(state: state),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => NotificationInbox(state: state),
  );
}
