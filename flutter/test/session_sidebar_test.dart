import 'package:codex_lan_flutter/app_controller.dart';
import 'package:codex_lan_flutter/protocol/bridge_messages.dart';
import 'package:codex_lan_flutter/services/bridge_socket_client.dart';
import 'package:codex_lan_flutter/sessions/session_sidebar.dart';
import 'package:codex_lan_flutter/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('shows and imports app-server Codex sessions', (tester) async {
    final socket = FakeBridgeSocketClient();
    final controller = AppController(socket: socket)
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Local chat',
            'updatedAt': '2026-06-09T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      })
      ..handleBridgeMessageForTest({
        'type': 'app.thread.list',
        'threads': [
          {
            'threadId': 'thread-1',
            'title': 'Native Codex session',
            'preview': 'worked on files',
            'createdAt': '2026-06-08T00:00:00.000Z',
            'updatedAt': '2026-06-09T00:00:00.000Z',
            'workdir': '/home/kurisu/project',
            'source': 'app-server',
          },
        ],
      })
      ..handleBridgeMessageForTest({
        'type': 'external.session.list',
        'sessions': [
          {
            'externalSessionId': 'external-1',
            'title': 'CLI history',
            'createdAt': '2026-06-08T00:00:00.000Z',
            'updatedAt': '2026-06-09T00:00:00.000Z',
            'workdir': '/home/kurisu/cli',
            'codexThreadId': 'codex-thread-1',
            'path': '/home/kurisu/.codex/sessions/session.jsonl',
          },
        ],
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          theme: buildCodexTheme(),
          home: const Scaffold(body: SessionSidebar()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('System Codex'), findsOneWidget);
    expect(find.text('Native Codex session'), findsOneWidget);
    expect(find.text('CLI history'), findsOneWidget);

    await tester.tap(find.text('Native Codex session'));
    await tester.pump();

    expect(
      socket.sentMessages,
      contains(
        predicate<Map<String, dynamic>>(
          (message) =>
              message['type'] == 'app.thread.import' &&
              message['threadId'] == 'thread-1',
        ),
      ),
    );
  });
}

class FakeBridgeSocketClient extends BridgeSocketClient {
  final sentMessages = <Map<String, dynamic>>[];

  @override
  Future<void> connect({
    required String url,
    required void Function(Map<String, dynamic> message) onMessage,
    required void Function(Object error) onError,
    required void Function() onDone,
    Duration timeout = const Duration(seconds: 8),
  }) async {}

  @override
  void send(Map<String, dynamic> message) {
    sentMessages.add(Map<String, dynamic>.from(message));
  }

  @override
  Future<void> close() async {}
}
