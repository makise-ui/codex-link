import 'package:codex_lan_flutter/app_controller.dart';
import 'package:codex_lan_flutter/chat/chat_screen.dart';
import 'package:codex_lan_flutter/protocol/bridge_messages.dart';
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
}
