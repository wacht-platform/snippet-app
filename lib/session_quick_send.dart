import 'dart:async';
import 'dart:convert';

import 'api.dart';
import 'models.dart';
import 'store.dart';

/// A decision or reply sent from outside the session screen (toast, notch,
/// OS notification action).
sealed class QuickAction {
  const QuickAction();
  Map<String, dynamic> frame(String nonce);
}

class QuickReply extends QuickAction {
  const QuickReply(this.text);
  final String text;
  @override
  Map<String, dynamic> frame(String nonce) =>
      {'kind': 'user_message', 'value': text, 'nonce': nonce};
}

class QuickAnswer extends QuickAction {
  const QuickAnswer(this.text);
  final String text;
  @override
  Map<String, dynamic> frame(String nonce) =>
      {'kind': 'answer', 'value': text, 'nonce': nonce};
}

class QuickApprove extends QuickAction {
  const QuickApprove();
  @override
  Map<String, dynamic> frame(String nonce) =>
      {'kind': 'approve', 'nonce': nonce};
}

class QuickDeny extends QuickAction {
  const QuickDeny();
  @override
  Map<String, dynamic> frame(String nonce) => {'kind': 'deny', 'nonce': nonce};
}

int _nonceCounter = 0;

/// Resolves the machine from a notification payload (`url`, then `name`, then
/// the only saved machine), the same order the shell uses for taps.
Future<Instance?> resolveInstanceForPayload(Map<String, dynamic> payload,
    {InstanceStore? store}) async {
  final items = await (store ?? InstanceStore()).load();
  final url = '${payload['url'] ?? ''}';
  final name = '${payload['name'] ?? ''}';
  return items.where((i) => url.isNotEmpty && i.url == url).firstOrNull ??
      items.where((i) => name.isNotEmpty && i.name == name).firstOrNull ??
      (items.length == 1 ? items.first : null);
}

/// Opens a short-lived `/attach` socket, sends one frame and closes. The
/// daemon applies frames on receipt and dedupes by nonce, so a retry from the
/// session screen can't double-apply.
Future<bool> quickSend({
  required DaemonClient client,
  required String session,
  required QuickAction action,
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (session.isEmpty) return false;
  final nonce = 'q${++_nonceCounter}-${DateTime.now().microsecondsSinceEpoch}';
  try {
    final ch = client.attach(session);
    await ch.ready.timeout(timeout);
    ch.sink.add(jsonEncode(action.frame(nonce)));
    // Wait for the first server frame so the send is flushed before closing.
    await ch.stream.first.timeout(timeout, onTimeout: () => null);
    await ch.sink.close();
    return true;
  } catch (_) {
    return false;
  }
}

/// Payload-driven convenience used by every notification surface.
Future<bool> quickSendForPayload(
    Map<String, dynamic> payload, QuickAction action) async {
  final instance = await resolveInstanceForPayload(payload);
  if (instance == null) return false;
  final dest = payload['destination'];
  final session =
      '${payload['session'] ?? (dest is Map ? dest['session'] ?? dest['id'] : '') ?? ''}';
  return quickSend(
    client: DaemonClient(instance.url, instance.token),
    session: session,
    action: action,
  );
}
