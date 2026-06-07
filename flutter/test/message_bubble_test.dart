import 'package:codex_lan_flutter/chat/message_bubble.dart';
import 'package:codex_lan_flutter/protocol/bridge_messages.dart';
import 'package:codex_lan_flutter/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
