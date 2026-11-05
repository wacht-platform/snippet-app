import 'dart:async';

import 'package:flutter/services.dart';

// The native channel holds one sink, so a second direct listener would steal
// ambient's stream and cancelling it would stop ambient's mic.
class MacosMic {
  static const _channel = EventChannel('snippet/macos_aec_mic');
  static StreamSubscription<Uint8List>? _native;

  static final StreamController<Uint8List> _out =
      StreamController<Uint8List>.broadcast(
    onListen: () {
      _native = _channel
          .receiveBroadcastStream()
          .where((event) => event is Uint8List)
          .cast<Uint8List>()
          .listen(_out.add, onError: _out.addError);
    },
    onCancel: () async {
      final native = _native;
      _native = null;
      await native?.cancel();
    },
  );

  static Stream<Uint8List> get stream => _out.stream;
}
