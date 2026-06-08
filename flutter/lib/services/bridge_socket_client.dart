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
    final normalizedUrl = normalizeBridgeWebSocketUrl(url);
    final uri = Uri.parse(normalizedUrl);
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
      throw TimeoutException(
        'Could not reach the Codex Link host at $url within ${timeout.inSeconds}s. Check that the host is running and the LAN or tunnel URL is reachable.',
        timeout,
      );
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

String normalizeBridgeWebSocketUrl(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return trimmed;
  final withScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed)
      ? trimmed
      : '${_looksLocalBridgeTarget(trimmed) ? 'ws' : 'wss'}://$trimmed';
  final uri = Uri.parse(withScheme);
  return switch (uri.scheme) {
    'http' => uri.replace(scheme: 'ws').toString(),
    'https' => uri.replace(scheme: 'wss').toString(),
    _ => uri.toString(),
  };
}

bool _looksLocalBridgeTarget(String value) {
  final host = value.split('/').first.split(':').first.toLowerCase();
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host.startsWith('192.168.') ||
      host.startsWith('10.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host);
}
