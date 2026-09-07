import 'dart:convert';

/// Compact, typed representation of a daemon `/events` message.
/// Unknown kinds are preserved and ignored safely by consumers.
class DeviceEvent {
  final String kind;
  final String action;
  final String session;
  final String status;
  final String queueId;

  const DeviceEvent({
    required this.kind,
    this.action = '',
    this.session = '',
    this.status = '',
    this.queueId = '',
  });

  factory DeviceEvent.fromJson(Object? raw) {
    if (raw is! Map) return const DeviceEvent(kind: '');
    return DeviceEvent(
      kind: raw['kind']?.toString() ?? '',
      action: raw['action']?.toString() ?? '',
      session: raw['session']?.toString() ?? '',
      status: raw['status']?.toString() ?? '',
      queueId: raw['queue_id']?.toString() ?? '',
    );
  }

  static DeviceEvent? decode(Object? message) {
    try {
      final raw = message is String ? jsonDecode(message) : message;
      final event = DeviceEvent.fromJson(raw);
      return event.kind.isEmpty ? null : event;
    } catch (_) {
      return null;
    }
  }
}
