import 'package:codex_lan_flutter/app_controller.dart';
import 'package:codex_lan_flutter/chat/chat_screen.dart';
import 'package:codex_lan_flutter/protocol/bridge_messages.dart';
import 'package:codex_lan_flutter/services/bridge_socket_client.dart';
import 'package:codex_lan_flutter/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('slash commands render inline above the composer', (
    tester,
  ) async {
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..commands.add(
        const CodexCommandInfo(
          commandId: 'codex.explain',
          title: 'explain',
          description: 'Explain the selected context',
          category: 'agent',
        ),
      )
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Inline commands',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(theme: buildCodexTheme(), home: const ChatScreen()),
      ),
    );

    await tester.enterText(find.byType(TextField).last, '/');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('slash-command-suggestions')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('slash-command-/send')), findsOneWidget);
    expect(find.text('/explain'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('command shortcuts are only shown after typing slash', (
    tester,
  ) async {
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..commands.addAll([
        const CodexCommandInfo(
          commandId: 'codex.workspace',
          title: 'workspace',
          description: 'Open workspace settings',
          category: 'session',
        ),
        const CodexCommandInfo(
          commandId: 'codex.review',
          title: 'review',
          description: 'Start review',
          category: 'agent',
        ),
      ])
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Commands',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(theme: buildCodexTheme(), home: const ChatScreen()),
      ),
    );

    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('/workspace'), findsNothing);

    await tester.enterText(find.byType(TextField).last, '/work');
    await tester.pump();

    expect(find.text('/workspace'), findsOneWidget);
  });

  testWidgets('slash picker shows all normal commands in the scrollable list', (
    tester,
  ) async {
    final commands = List<CodexCommandInfo>.generate(
      12,
      (index) => CodexCommandInfo(
        commandId: 'codex.command$index',
        title: 'command$index',
        description: 'Command $index',
        category: 'agent',
      ),
    );
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..commands.addAll([
        ...commands,
        const CodexCommandInfo(
          commandId: 'mode.yolo',
          title: 'Yolo mode',
          description: 'Danger full access',
          category: 'mode',
        ),
      ])
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Full commands',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(theme: buildCodexTheme(), home: const ChatScreen()),
      ),
    );

    await tester.enterText(find.byType(TextField).last, '/');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('slash-command-suggestions')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('slash-command-codex.command0')),
      findsOneWidget,
    );
    await tester.drag(
      find.byKey(const ValueKey('slash-command-suggestions')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('slash-command-codex.command11')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('slash-command-mode.yolo')), findsNothing);
  });

  testWidgets('goal slash command inserts an editable goal prompt', (
    tester,
  ) async {
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..commands.add(
        const CodexCommandInfo(
          commandId: 'codex.goal',
          title: 'goal',
          description: 'Set or inspect the active goal',
          category: 'agent',
        ),
      )
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Goal command',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(theme: buildCodexTheme(), home: const ChatScreen()),
      ),
    );

    await tester.enterText(find.byType(TextField).last, '/go');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('slash-command-codex.goal')));
    await tester.pump();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, '/goal ');
  });

  testWidgets('active goal appears as a compact top bar chip', (tester) async {
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Goal banner',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
            'goal': {
              'threadId': 'thread-1',
              'objective': 'Keep polishing the app-server UI',
              'status': 'active',
              'tokenBudget': 20000,
              'tokensUsed': 55,
              'timeUsedSeconds': 8,
              'createdAt': 1,
              'updatedAt': 3,
            },
          },
        ],
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(theme: buildCodexTheme(), home: const ChatScreen()),
      ),
    );

    expect(find.byKey(const ValueKey('active-goal-chip')), findsOneWidget);
    expect(find.textContaining('Keep polishing'), findsOneWidget);
    expect(find.text('Goal active'), findsNothing);
  });

  testWidgets('app-server plan updates render as a collapsible composer bar', (
    tester,
  ) async {
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Plan bar',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'running',
            'mode': 'safe',
            'sandbox': 'workspace-write',
            'activeRunId': 'run-1',
          },
        ],
      })
      ..handleBridgeMessageForTest({
        'type': 'session.plan.updated',
        'sessionId': 's1',
        'runId': 'run-1',
        'title': 'Plan',
        'text':
            'Checking the mobile bridge polish\n- completed: Move plan out of chat\n- in_progress: Render a composer bar',
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(theme: buildCodexTheme(), home: const ChatScreen()),
      ),
    );

    expect(find.byKey(const ValueKey('session-plan-bar')), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.textContaining('Move plan out of chat'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('session-plan-bar')));
    await tester.pump(AppMotion.quick);

    expect(find.textContaining('Move plan out of chat'), findsOneWidget);
  });

  testWidgets('goal slash prompt shows subcommand suggestions above composer', (
    tester,
  ) async {
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Goal subcommands',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(theme: buildCodexTheme(), home: const ChatScreen()),
      ),
    );

    await tester.enterText(find.byType(TextField).last, '/goal ');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('slash-subcommand-suggestions')),
      findsOneWidget,
    );
    expect(find.text('/goal clear'), findsOneWidget);
    expect(find.text('/goal complete'), findsOneWidget);
  });

  testWidgets(
    'connection state is shown below the chat instead of top chrome',
    (tester) async {
      final controller = AppController()
        ..phase = ConnectionPhase.connected
        ..handleBridgeMessageForTest({
          'type': 'host.info',
          'version': 7,
          'connectionMode': 'tunnel',
          'tunnelProvider': 'cloudflared',
          'publicUrl': 'wss://unit.trycloudflare.com',
          'localUrl': 'ws://127.0.0.1:8787',
          'hostLabel': 'Codex Link',
          'yoloAllowed': false,
        })
        ..handleBridgeMessageForTest({
          'type': 'session.list',
          'activeSessionId': 's1',
          'sessions': [
            {
              'sessionId': 's1',
              'title': 'Tunnel placement',
              'updatedAt': '2026-06-08T00:00:00.000Z',
              'workspaceId': 'default',
              'workdir': '/tmp/repo',
              'lastStatus': 'idle',
              'mode': 'safe',
              'sandbox': 'workspace-write',
            },
          ],
        });

      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: controller,
          child: MaterialApp(
            theme: buildCodexTheme(),
            home: const ChatScreen(),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('bottom-connection-chip')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'run completion notice previews the final response in dark chrome',
    (tester) async {
      final controller = AppController()
        ..phase = ConnectionPhase.connected
        ..statusText = 'Running'
        ..handleBridgeMessageForTest({
          'type': 'session.list',
          'activeSessionId': 's1',
          'sessions': [
            {
              'sessionId': 's1',
              'title': 'Completion preview',
              'updatedAt': '2026-06-08T00:00:00.000Z',
              'workspaceId': 'default',
              'workdir': '/tmp/repo',
              'lastStatus': 'running',
              'mode': 'safe',
              'sandbox': 'workspace-write',
              'activeRunId': 'run-1',
            },
          ],
        })
        ..handleBridgeMessageForTest({
          'type': 'message.history',
          'sessionId': 's1',
          'messages': [
            {
              'messageId': 'r1',
              'role': 'assistant',
              'kind': 'response',
              'title': 'Response',
              'text':
                  'First useful line\nSecond useful line\nThird useful line',
              'createdAt': '2026-06-08T00:00:01.000Z',
              'complete': true,
            },
          ],
        });

      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: controller,
          child: MaterialApp(
            theme: buildCodexTheme(),
            home: const ChatScreen(),
          ),
        ),
      );

      controller.handleBridgeMessageForTest({
        'type': 'run.completed',
        'sessionId': 's1',
        'runId': 'run-1',
        'exitCode': 0,
      });
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('chat-notice-banner')), findsOneWidget);
      expect(
        find.text('First useful line\nSecond useful line\nThird useful line'),
        findsOneWidget,
      );
    },
  );

  testWidgets('top bar opens command center separately from settings', (
    tester,
  ) async {
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Command center',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(theme: buildCodexTheme(), home: const ChatScreen()),
      ),
    );

    await tester.tap(find.byTooltip('Commands'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsNothing);
    expect(find.text('Commands'), findsWidgets);
  });

  testWidgets('composer can send a steer message while a run is active', (
    tester,
  ) async {
    final socket = FakeBridgeSocketClient();
    final controller = AppController(socket: socket)
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Running',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'running',
            'mode': 'safe',
            'sandbox': 'workspace-write',
            'activeRunId': 'run-1',
          },
        ],
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(theme: buildCodexTheme(), home: const ChatScreen()),
      ),
    );

    await tester.enterText(find.byType(TextField).last, 'also check tests');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(socket.sentMessages.last, {
      'type': 'prompt.send',
      'sessionId': 's1',
      'prompt': 'also check tests',
    });
    expect(
      socket.sentMessages.where((message) => message['type'] == 'run.cancel'),
      isEmpty,
    );
  });

  testWidgets('pending approvals are available above the composer', (
    tester,
  ) async {
    final socket = FakeBridgeSocketClient();
    final controller = AppController(socket: socket)
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Approvals',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'running',
            'mode': 'safe',
            'sandbox': 'workspace-write',
            'activeRunId': 'run-1',
          },
        ],
      })
      ..handleBridgeMessageForTest({
        'type': 'approval.requested',
        'sessionId': 's1',
        'approvalId': 'approval-1',
        'title': 'Run command',
        'body': 'pnpm test',
        'riskLevel': 'medium',
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(theme: buildCodexTheme(), home: const ChatScreen()),
      ),
    );

    expect(find.byKey(const ValueKey('approval-queue-bar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('approval-queue-approve')));
    await tester.pump();

    expect(socket.sentMessages.last, {
      'type': 'approval.decision',
      'sessionId': 's1',
      'approvalId': 'approval-1',
      'decision': 'approve',
    });
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
