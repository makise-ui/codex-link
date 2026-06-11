import 'package:codex_lan_flutter/app_controller.dart';
import 'package:codex_lan_flutter/chat/chat_screen.dart';
import 'package:codex_lan_flutter/protocol/bridge_messages.dart';
import 'package:codex_lan_flutter/services/bridge_socket_client.dart';
import 'package:codex_lan_flutter/services/voice_transcription_service.dart';
import 'package:codex_lan_flutter/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('composer separates the attach control from the input shell', (
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
            'title': 'Composer',
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

    expect(
      find.byKey(const ValueKey('floating-attach-button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('composer-input-shell')), findsOneWidget);
    final attachSize = tester.getSize(
      find.byKey(const ValueKey('floating-attach-button')),
    );
    final inputSize = tester.getSize(
      find.byKey(const ValueKey('composer-input-shell')),
    );
    expect((attachSize.height - inputSize.height).abs(), lessThanOrEqualTo(4));
    expect(attachSize.width, 44);

    await tester.enterText(find.byType(TextField).last, 'Center this');
    await tester.pump();

    final shellRect = tester.getRect(
      find.byKey(const ValueKey('composer-input-shell')),
    );
    final editableRect = tester.getRect(find.byType(EditableText));
    expect(
      (editableRect.center.dy - shellRect.center.dy).abs(),
      lessThanOrEqualTo(3),
    );
  });

  testWidgets('composer stays editable while cached chat is offline', (
    tester,
  ) async {
    final controller = AppController()
      ..phase = ConnectionPhase.offline
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Offline composer',
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

    await tester.enterText(find.byType(TextField).last, 'keep typing');
    await tester.pump();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, 'keep typing');
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

  testWidgets('app-server non-subagent activity stays in chat', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Activity',
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
            'messageId': 'u1',
            'role': 'user',
            'kind': 'response',
            'text': 'Use subagents',
            'createdAt': '2026-06-08T00:00:00.000Z',
            'complete': true,
          },
          {
            'messageId': 'w1',
            'role': 'system',
            'kind': 'system',
            'title': 'Warning',
            'text': 'Unit warning',
            'runId': 'run-1',
            'createdAt': '2026-06-08T00:00:01.000Z',
            'complete': true,
          },
          {
            'messageId': 'e1',
            'role': 'system',
            'kind': 'system',
            'title': 'stderr',
            'text': 'failed to connect to websocket',
            'runId': 'run-1',
            'createdAt': '2026-06-08T00:00:02.000Z',
            'complete': true,
          },
          {
            'messageId': 'r1',
            'role': 'assistant',
            'kind': 'response',
            'title': 'Response',
            'text': 'Finished.',
            'runId': 'run-1',
            'createdAt': '2026-06-08T00:00:03.000Z',
            'complete': true,
          },
        ],
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(theme: buildCodexTheme(), home: const ChatScreen()),
      ),
    );

    expect(find.text('Finished.'), findsOneWidget);
    expect(find.text('Unit warning'), findsOneWidget);
    expect(find.text('failed to connect to websocket'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-activity-chip')), findsNothing);
  });

  testWidgets('structured subagent activity shows floating summary only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Subagents',
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
        'type': 'session.subagents.updated',
        'sessionId': 's1',
        'runId': 'run-1',
        'parentThreadId': 'thread-parent',
        'subagents': [
          {
            'threadId': 'thread-child',
            'parentThreadId': 'thread-parent',
            'title': 'Protocol explorer',
            'preview': 'Checking app-server protocol',
            'status': 'running',
            'agentNickname': 'Explorer',
            'agentRole': 'explorer',
            'updatedAt': '2026-06-08T00:00:01.000Z',
          },
        ],
      })
      ..handleBridgeMessageForTest({
        'type': 'message.history',
        'sessionId': 's1',
        'messages': [
          {
            'messageId': 'u1',
            'role': 'user',
            'kind': 'response',
            'text': 'Use subagents',
            'createdAt': '2026-06-08T00:00:00.000Z',
            'complete': true,
          },
          {
            'messageId': 'a1',
            'role': 'system',
            'kind': 'executing',
            'title': 'Subagent running',
            'text': 'spawn_agent explorer · Checking app-server protocol',
            'runId': 'run-1',
            'createdAt': '2026-06-08T00:00:01.000Z',
            'complete': false,
          },
          {
            'messageId': 't1',
            'role': 'system',
            'kind': 'thinking',
            'title': 'Thinking',
            'text': 'Thinking…',
            'runId': 'run-1',
            'createdAt': '2026-06-08T00:00:01.250Z',
            'complete': false,
          },
          {
            'messageId': 'w1',
            'role': 'system',
            'kind': 'system',
            'title': 'Warning',
            'text': 'Subagent warning',
            'runId': 'run-1',
            'createdAt': '2026-06-08T00:00:01.500Z',
            'complete': true,
          },
          {
            'messageId': 'r0',
            'role': 'assistant',
            'kind': 'response',
            'title': 'Response',
            'text': 'Intermediate subagent update.',
            'runId': 'run-1',
            'createdAt': '2026-06-08T00:00:01.750Z',
            'complete': true,
          },
          {
            'messageId': 'r1',
            'role': 'assistant',
            'kind': 'response',
            'title': 'Response',
            'text': 'I am coordinating.',
            'runId': 'run-1',
            'createdAt': '2026-06-08T00:00:02.000Z',
            'complete': false,
          },
        ],
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(theme: buildCodexTheme(), home: const ChatScreen()),
      ),
    );

    expect(find.text('I am coordinating.'), findsOneWidget);
    expect(find.text('Subagent warning'), findsOneWidget);
    expect(find.text('Intermediate subagent update.'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-activity-chip')), findsOneWidget);
    expect(find.text('1 subagent running'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent-activity-chip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));

    expect(find.text('Subagents'), findsWidgets);
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('explorer'), findsOneWidget);
    expect(find.text('Checking app-server protocol'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
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

  testWidgets('connected tunnel details stay out of the chat chrome', (
    tester,
  ) async {
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
        child: MaterialApp(theme: buildCodexTheme(), home: const ChatScreen()),
      ),
    );

    expect(find.byKey(const ValueKey('bottom-connection-chip')), findsNothing);
    expect(find.textContaining('cloudflared'), findsNothing);
    expect(find.text('repo / default model'), findsOneWidget);
  });

  testWidgets('offline top card reconnect affordance stays visible', (
    tester,
  ) async {
    final controller = AppController()
      ..phase = ConnectionPhase.offline
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Offline',
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

    expect(find.text('Disconnected - tap to reconnect'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bottom-connection-chip')),
      findsOneWidget,
    );
  });

  testWidgets('attach menu opens the workspace browser entry point', (
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
            'title': 'Files',
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

    await tester.tap(find.byKey(const ValueKey('floating-attach-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Browse workspace'), findsOneWidget);
    expect(find.text('Open files, preview code, or upload'), findsOneWidget);
    expect(find.text('Upload image'), findsOneWidget);
    expect(find.text('Upload file'), findsOneWidget);
  });

  testWidgets(
    'composer chat settings expose permission text model and effort choices',
    (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final socket = FakeBridgeSocketClient();
      final controller = AppController(socket: socket)
        ..phase = ConnectionPhase.connected
        ..handleBridgeMessageForTest({
          'type': 'host.info',
          'version': 11,
          'connectionMode': 'lan',
          'localUrl': 'ws://127.0.0.1:8787',
          'hostLabel': 'Codex Link',
          'yoloAllowed': true,
        })
        ..handleBridgeMessageForTest({
          'type': 'session.list',
          'activeSessionId': 's1',
          'sessions': [
            {
              'sessionId': 's1',
              'title': 'Controls',
              'updatedAt': '2026-06-08T00:00:00.000Z',
              'workspaceId': 'default',
              'workdir': '/tmp/repo',
              'lastStatus': 'idle',
              'mode': 'safe',
              'sandbox': 'workspace-write',
              'model': 'gpt-test',
              'reasoningEffort': 'high',
              'serviceTier': 'priority',
            },
          ],
        })
        ..handleBridgeMessageForTest({
          'type': 'app.model.list',
          'models': [
            {
              'id': 'gpt-test',
              'model': 'gpt-test',
              'displayName': 'GPT Test',
              'hidden': false,
              'supportedReasoningEfforts': ['low', 'high', 'xhigh'],
              'inputModalities': ['text'],
              'supportsPersonality': false,
              'serviceTiers': [
                {
                  'id': 'priority',
                  'name': 'Priority',
                  'description': 'Faster responses for more credits',
                },
              ],
              'defaultServiceTier': null,
              'isDefault': false,
            },
            {
              'id': 'gpt-other',
              'model': 'gpt-other',
              'displayName': 'GPT Other',
              'hidden': false,
              'supportedReasoningEfforts': ['low', 'high'],
              'inputModalities': ['text'],
              'supportsPersonality': false,
              'serviceTiers': [],
              'defaultServiceTier': null,
              'isDefault': false,
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

      await tester.tap(find.byKey(const ValueKey('composer-settings-button')));
      await tester.pumpAndSettle();

      expect(find.text('Chat settings'), findsOneWidget);
      expect(find.text('Permission mode'), findsOneWidget);
      expect(find.text('Text size'), findsOneWidget);
      expect(find.text('Models'), findsOneWidget);
      expect(find.text('Effort'), findsOneWidget);
      expect(find.text('GPT Other'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-mode-yolo')));
      await tester.pumpAndSettle();

      expect(socket.sentMessages.last, {
        'type': 'session.mode.set',
        'sessionId': 's1',
        'mode': 'yolo',
      });

      await tester.tap(find.byKey(const ValueKey('composer-settings-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-model-gpt-other')));
      await tester.pumpAndSettle();

      expect(socket.sentMessages.last, {
        'type': 'session.config.set',
        'sessionId': 's1',
        'model': 'gpt-other',
        'reasoningEffort': 'high',
        'serviceTier': null,
      });
    },
  );

  testWidgets('composer chat settings expose text size choices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Text controls',
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

    await tester.tap(find.byKey(const ValueKey('composer-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-text-size-xl')));
    await tester.pump();

    expect(controller.chatTextSize, 'xl');
    expect(controller.chatTextScale, greaterThan(1.15));
  });

  testWidgets(
    'usage limit line is visible above chat chrome and opens details',
    (tester) async {
      final controller = AppController()
        ..phase = ConnectionPhase.connected
        ..handleBridgeMessageForTest({
          'type': 'session.list',
          'activeSessionId': 's1',
          'sessions': [
            {
              'sessionId': 's1',
              'title': 'Usage',
              'updatedAt': '2026-06-08T00:00:00.000Z',
              'workspaceId': 'default',
              'workdir': '/tmp/repo',
              'lastStatus': 'idle',
              'mode': 'safe',
              'sandbox': 'workspace-write',
            },
          ],
        })
        ..handleBridgeMessageForTest({
          'type': 'app.account.rateLimits',
          'limits': [
            {
              'limitId': 'codex',
              'planType': 'Plus',
              'usedPercent': 64,
              'remainingPercent': 36,
              'windowDurationMins': 300,
              'resetsAt': 1781110800,
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

      expect(find.byKey(const ValueKey('usage-limit-line')), findsOneWidget);
      expect(find.byKey(const ValueKey('usage-limit-ring')), findsNothing);

      await tester.tap(find.byTooltip('Usage limits'));
      await tester.pumpAndSettle();

      expect(find.text('Usage limits'), findsOneWidget);
      expect(find.text('codex'), findsOneWidget);
      expect(find.textContaining('64% used'), findsOneWidget);
    },
  );

  testWidgets('terminal screen sends shell commands for the active workspace', (
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
            'title': 'Shell',
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

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('action-shell')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('shell-command-input')),
      'pwd',
    );
    await tester.tap(find.byTooltip('Run command'));
    await tester.pump();

    expect(socket.sentMessages.last, {
      'type': 'shell.command.run',
      'sessionId': 's1',
      'command': 'pwd',
    });
  });

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

  testWidgets('in-app notice counts down and auto-dismisses', (tester) async {
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..setInAppNoticeDurationSeconds(2)
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Notice',
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

    controller.handleBridgeMessageForTest({
      'type': 'run.completed',
      'sessionId': 's1',
      'runId': 'run-1',
      'exitCode': 0,
    });
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-notice-banner')), findsOneWidget);
    expect(find.text('2s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-notice-banner')), findsNothing);
  });

  testWidgets('top action menu opens app-server actions', (tester) async {
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Actions',
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

    expect(find.byTooltip('Session controls'), findsNothing);
    expect(find.byTooltip('Shell'), findsNothing);
    expect(find.byTooltip('App server actions'), findsNothing);
    expect(find.byTooltip('Actions'), findsOneWidget);

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Command center'), findsOneWidget);
    expect(find.text('Workspace shell'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('action-command-center')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsNothing);
    expect(find.text('App Server Actions'), findsWidgets);
    expect(find.text('Plugins'), findsOneWidget);
  });

  testWidgets('empty composer shows mic and inserts transcribed text', (
    tester,
  ) async {
    final controller =
        AppController(
            voiceTranscriptionService: FakeVoiceTranscriptionService(
              'summarize the diff',
            ),
          )
          ..phase = ConnectionPhase.connected
          ..handleBridgeMessageForTest({
            'type': 'session.list',
            'activeSessionId': 's1',
            'sessions': [
              {
                'sessionId': 's1',
                'title': 'Voice',
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

    expect(find.byTooltip('Voice input'), findsOneWidget);
    expect(find.byTooltip('Send'), findsNothing);

    await tester.tap(find.byTooltip('Voice input'));
    await tester.pumpAndSettle();

    expect(find.text('summarize the diff'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
  });

  testWidgets(
    'attachment-only composer sends attachments instead of voice input',
    (tester) async {
      const channel = MethodChannel(
        'miguelruivo.flutter.plugins.filepicker',
        StandardMethodCodec(),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'any');
            return [
              {
                'name': 'notes.txt',
                'size': 5,
                'bytes': Uint8List.fromList('hello'.codeUnits),
              },
            ];
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final socket = FakeBridgeSocketClient();
      final controller = AppController(socket: socket)
        ..phase = ConnectionPhase.connected
        ..handleBridgeMessageForTest({
          'type': 'session.list',
          'activeSessionId': 's1',
          'sessions': [
            {
              'sessionId': 's1',
              'title': 'Attachment',
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

      await tester.tap(find.byKey(const ValueKey('floating-attach-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload file'));
      await tester.pumpAndSettle();

      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.byTooltip('Send'), findsOneWidget);
      expect(find.byTooltip('Voice input'), findsNothing);

      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      expect(socket.sentMessages.last, {
        'type': 'prompt.send',
        'sessionId': 's1',
        'prompt': 'Please inspect the uploaded attachments.',
        'attachments': [
          {
            'name': 'notes.txt',
            'mimeType': 'text/plain',
            'dataBase64': 'aGVsbG8=',
          },
        ],
      });
    },
  );

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
    await tester.pump();
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

class FakeVoiceTranscriptionService implements VoiceTranscriptionService {
  FakeVoiceTranscriptionService(this.text);

  final String text;

  @override
  Future<VoiceTranscriptionResult> transcribeOnce() async {
    return VoiceTranscriptionResult(text: text);
  }
}
