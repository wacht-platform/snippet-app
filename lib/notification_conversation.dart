import 'package:flutter/material.dart';
import 'api.dart';
import 'screens/agent_messaging.dart';

Future<bool> openNotificationConversation(
  BuildContext context,
  DaemonClient client,
  String threadId,
) async {
  final threads = await client.directThreads();
  if (!context.mounted) return false;
  for (final thread in threads) {
    if (thread.threadId == threadId && thread.peerKind == 'agent') {
      openAgentThread(context,
          client: client, agentId: thread.peerId, agentName: thread.title);
      return true;
    }
  }
  return false;
}
