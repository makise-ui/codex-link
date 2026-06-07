import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../protocol/bridge_codec.dart';

class BridgeSocketClient {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  Future<void> connect({
    required String url,
    required void Function(Map<String, dynamic>) onMessage,
    required void Function(Object error) onError,
    required void Function() onDone,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await close();
    final uri = Uri.parse(url);
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    _subscription = channel.stream.listen(
      (raw) {
        try {
          onMessage(decodeBridgeMessage(raw));
        } catch (error) {
          onError(error);
        }
      },
      onError: onError,
      onDone: onDone,
      cancelOnError: false,
    );

    try {
      await channel.ready.timeout(timeout);
    } catch (error) {
      await close();
      throw TimeoutException('Could not reach the Codex LAN host at $url within ${timeout.inSeconds}s. Check that the host is running, the phone is on the same Wi-Fi, and the port is not blocked.', timeout);
    }
  }

  void send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) {
      throw StateError('Bridge socket is not connected');
    }
    channel.sink.add(encodeBridgeMessage(message));
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }
}
