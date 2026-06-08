import 'package:codex_lan_flutter/services/bridge_socket_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes pasted tunnel URLs into websocket URLs', () {
    expect(
      normalizeBridgeWebSocketUrl('https://unit.trycloudflare.com'),
      'wss://unit.trycloudflare.com',
    );
    expect(
      normalizeBridgeWebSocketUrl('http://127.0.0.1:8787'),
      'ws://127.0.0.1:8787',
    );
    expect(
      normalizeBridgeWebSocketUrl('unit.trycloudflare.com'),
      'wss://unit.trycloudflare.com',
    );
    expect(
      normalizeBridgeWebSocketUrl('wss://unit.trycloudflare.com/ws'),
      'wss://unit.trycloudflare.com/ws',
    );
  });
}
