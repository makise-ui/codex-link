import 'package:codex_lan_flutter/app_controller.dart';
import 'package:codex_lan_flutter/protocol/bridge_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offline phase keeps cached chat visible without enabling sends', () {
    final controller = AppController()..phase = ConnectionPhase.offline;

    expect(controller.canShowChat, isTrue);
    expect(controller.isOffline, isTrue);
    expect(controller.isConnected, isFalse);
  });
}
