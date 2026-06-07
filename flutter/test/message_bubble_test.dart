import 'package:codex_lan_flutter/chat/message_bubble.dart';
import 'package:codex_lan_flutter/protocol/bridge_messages.dart';
import 'package:codex_lan_flutter/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders active thinking as an inline translucent row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'thinking-1',
              role: ChatRole.system,
              kind: AgentMessageKind.thinking,
              text: 'Thinking...',
              createdAt: DateTime(2026),
              title: 'Thinking',
              complete: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Thinking'), findsOneWidget);
    expect(find.byKey(const ValueKey('thinking-inline-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-card')), findsNothing);
  });

  testWidgets('renders multiple executing messages as one expandable stack', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: ActivityStackBubble(
            messages: [
              ChatMessage(
                id: 'cmd-1',
                role: ChatRole.system,
                kind: AgentMessageKind.executing,
                text: 'pnpm test\n2 tests passed',
                createdAt: DateTime(2026),
                title: 'Running command',
              ),
              ChatMessage(
                id: 'cmd-2',
                role: ChatRole.system,
                kind: AgentMessageKind.executing,
                text: 'flutter analyze\nNo issues found',
                createdAt: DateTime(2026),
                title: 'Running command',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Ran command'), findsOneWidget);
    expect(find.text('pnpm test'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('activity-stack-toggle')));
    await tester.pumpAndSettle();

    expect(find.textContaining('pnpm test'), findsOneWidget);
    expect(find.textContaining('flutter analyze'), findsOneWidget);
  });

  testWidgets('renders file change events as visible timeline cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'files-1',
              role: ChatRole.system,
              kind: AgentMessageKind.files,
              text: 'added lib/new_file.dart\nmodified lib/chat.dart',
              createdAt: DateTime(2026),
              title: 'Files changed',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Files changed'), findsOneWidget);
    expect(find.text('lib/new_file.dart'), findsOneWidget);
    expect(find.text('lib/chat.dart'), findsOneWidget);
    expect(find.text('added'), findsOneWidget);
    expect(find.text('modified'), findsOneWidget);
  });
}
