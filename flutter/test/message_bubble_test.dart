import 'package:codex_lan_flutter/app_controller.dart';
import 'package:codex_lan_flutter/chat/message_bubble.dart';
import 'package:codex_lan_flutter/protocol/bridge_messages.dart';
import 'package:codex_lan_flutter/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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

    expect(find.byKey(const ValueKey('thinking-inline-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('thinking-wave-text')), findsOneWidget);
    expect(find.byKey(const ValueKey('thinking-wave-dot-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('thinking-wave-dot-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('thinking-wave-dot-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-card')), findsNothing);
  });

  testWidgets('renders reasoning summaries as translucent thought cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'reasoning-1',
              role: ChatRole.system,
              kind: AgentMessageKind.reasoning,
              text: 'Checked repository shape.',
              createdAt: DateTime(2026),
              title: 'Thinking summary',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Checked repository shape.'), findsOneWidget);
    expect(find.byIcon(Icons.psychology_alt_rounded), findsOneWidget);
  });

  testWidgets('streams active reasoning summary text in chat', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'reasoning-active',
              role: ChatRole.system,
              kind: AgentMessageKind.reasoning,
              text: 'Reading the app-server event stream.',
              createdAt: DateTime(2026),
              title: 'Thinking summary',
              complete: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Reading the app-server event stream.'), findsOneWidget);
    expect(find.textContaining('Thought for'), findsNothing);
  });

  testWidgets('collapses completed reasoning summary to thought duration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'reasoning-complete',
              role: ChatRole.system,
              kind: AgentMessageKind.reasoning,
              text: 'Checked repository shape.',
              createdAt: DateTime(2026),
              completedAt: DateTime(2026).add(const Duration(seconds: 5)),
              title: 'Thinking summary',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Thought for 5s'), findsOneWidget);
    expect(find.text('Checked repository shape.'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('thought-summary-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Checked repository shape.'), findsOneWidget);
  });

  testWidgets('approval cards expose approve and reject actions', (
    tester,
  ) async {
    final controller = AppController()
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
          home: Scaffold(
            body: MessageBubble(
              message: ChatMessage(
                id: 'approval-1',
                role: ChatRole.system,
                kind: AgentMessageKind.approval,
                text: 'approvalId approval-1\nrisk medium\npnpm test',
                createdAt: DateTime(2026),
                title: 'Approve command',
                complete: false,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Approve command'), findsOneWidget);
    expect(find.text('pnpm test'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
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

    expect(find.text('Ran 2 commands'), findsOneWidget);
    expect(find.text('pnpm test'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('activity-stack-toggle')));
    await tester.pumpAndSettle();

    expect(find.textContaining('pnpm test'), findsOneWidget);
    expect(find.textContaining('flutter analyze'), findsOneWidget);
  });

  testWidgets('single running command names the command in the summary', (
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
                text: 'flutter pub get\nResolving dependencies...',
                createdAt: DateTime(2026),
                title: 'Running command',
                complete: false,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Running: flutter pub get...'), findsOneWidget);
  });

  testWidgets('multiple running commands collapse to command count', (
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
                text: 'flutter pub get',
                createdAt: DateTime(2026),
                title: 'Running command',
                complete: false,
              ),
              ChatMessage(
                id: 'cmd-2',
                role: ChatRole.system,
                kind: AgentMessageKind.executing,
                text: 'flutter analyze',
                createdAt: DateTime(2026),
                title: 'Running command',
                complete: false,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Running 2 commands...'), findsOneWidget);
  });

  testWidgets('shows read filename in collapsed activity summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: ActivityStackBubble(
            messages: [
              ChatMessage(
                id: 'read-1',
                role: ChatRole.system,
                kind: AgentMessageKind.executing,
                text: 'Reading file: lib/main.dart\nLines: 1-20',
                createdAt: DateTime(2026),
                title: 'Reading file',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Read main.dart'), findsOneWidget);
  });

  testWidgets('renders file change events as compact expandable cards', (
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
              text:
                  'added lib/new_file.dart\n+class NewFile {}\nmodified lib/chat.dart\n-old\n+new',
              createdAt: DateTime(2026),
              title: 'Files changed',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Edited 2 files'), findsOneWidget);
    expect(find.text('Edit:lib/new_file.dart'), findsNothing);
    expect(find.text('Edit:lib/chat.dart'), findsNothing);
    expect(find.text('+class NewFile {}'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('file-activity-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Edit:lib/new_file.dart'), findsOneWidget);
    expect(find.text('Edit:lib/chat.dart'), findsOneWidget);
    expect(find.text('lib/new_file.dart'), findsOneWidget);
    expect(find.text('lib/chat.dart'), findsOneWidget);
    expect(find.text('added'), findsOneWidget);
    expect(find.text('modified'), findsOneWidget);
    expect(find.text('+class NewFile {}'), findsOneWidget);
    expect(find.text('-old'), findsOneWidget);
    expect(find.text('+new'), findsOneWidget);
  });

  testWidgets('single file edit shows the edited path directly', (
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
              text: 'modified lib/chat.dart\n-old\n+new',
              createdAt: DateTime(2026),
              title: 'Files changed',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Edit:lib/chat.dart'), findsOneWidget);
    expect(find.text('Edited 1 file'), findsNothing);
  });

  testWidgets('multiple generated files show as agent attachments', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'file-offers',
              role: ChatRole.system,
              kind: AgentMessageKind.files,
              text:
                  'generated build/app-release.apk\nsize 12\nfileId file-1\ngenerated screenshots/home.png\nsize 68\nfileId file-2',
              createdAt: DateTime(2026),
              title: 'File available',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Agent attached 2 files'), findsOneWidget);
    expect(find.text('File:build/app-release.apk'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('file-activity-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('File:build/app-release.apk'), findsOneWidget);
    expect(find.text('File:screenshots/home.png'), findsOneWidget);
  });

  testWidgets('assistant response does not show a visible copy button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'response-1',
              role: ChatRole.assistant,
              kind: AgentMessageKind.response,
              text: 'copy me',
              createdAt: DateTime(2026),
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Copy message'), findsNothing);
  });

  testWidgets('file offer cards expose download action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'file-offer-1',
              role: ChatRole.system,
              kind: AgentMessageKind.files,
              text: 'generated lib/generated.dart\nsize 12\nfileId file-1',
              createdAt: DateTime(2026),
              title: 'File available',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Download'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('file-activity-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsOneWidget);
    expect(find.byTooltip('Copy file path'), findsOneWidget);
  });

  testWidgets('edited file rows expose open in workspace action', (
    tester,
  ) async {
    String? openedPath;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'edited-file',
              role: ChatRole.system,
              kind: AgentMessageKind.files,
              text: 'modified lib/chat.dart\n-old\n+new',
              createdAt: DateTime(2026),
              title: 'Files changed',
            ),
            onOpenWorkspaceFile: (path) => openedPath = path,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('file-activity-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open in workspace'));

    expect(openedPath, 'lib/chat.dart');
  });

  testWidgets('generated file rows do not expose workspace open action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'generated-file',
              role: ChatRole.system,
              kind: AgentMessageKind.files,
              text: 'generated build/app-release.apk\nsize 12\nfileId file-1',
              createdAt: DateTime(2026),
              title: 'Files changed',
            ),
            onOpenWorkspaceFile: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('file-activity-toggle')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Open in workspace'), findsNothing);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('message text scale increases user and assistant body text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: Column(
            children: [
              MessageBubble(
                message: ChatMessage(
                  id: 'user-large',
                  role: ChatRole.user,
                  kind: AgentMessageKind.response,
                  text: 'larger user text',
                  createdAt: DateTime(2026),
                ),
                textScale: 1.18,
              ),
              MessageBubble(
                message: ChatMessage(
                  id: 'assistant-large',
                  role: ChatRole.assistant,
                  kind: AgentMessageKind.response,
                  text: 'larger assistant text',
                  createdAt: DateTime(2026),
                ),
                textScale: 1.18,
              ),
            ],
          ),
        ),
      ),
    );

    final userText = tester.widget<Text>(find.text('larger user text'));
    final assistantStyle = tester
        .widget<DefaultTextStyle>(
          find
              .ancestor(
                of: find.text('larger assistant text'),
                matching: find.byType(DefaultTextStyle),
              )
              .first,
        )
        .style;

    expect(userText.style?.fontSize, greaterThan(14));
    expect(assistantStyle.fontSize, greaterThan(14));
  });

  testWidgets('message text scale increases markdown paragraph text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'assistant-markdown-large',
              role: ChatRole.assistant,
              kind: AgentMessageKind.response,
              text: 'A markdown paragraph with **bold** text.',
              createdAt: DateTime(2026),
            ),
            textScale: 1.22,
          ),
        ),
      ),
    );

    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(markdown.styleSheet?.p?.fontSize, greaterThan(15));
  });

  testWidgets('requested file offers render as downloadable cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'file-offer-requested',
              role: ChatRole.system,
              kind: AgentMessageKind.files,
              text: 'requested lib/report.txt\nsize 12\nfileId file-1',
              createdAt: DateTime(2026),
              title: 'File available',
            ),
          ),
        ),
      ),
    );

    expect(find.text('lib/report.txt'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('file-activity-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('lib/report.txt'), findsOneWidget);
    expect(find.text('requested'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('downloaded image offers render inline image previews', (
    tester,
  ) async {
    const imageBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';
    final controller = AppController()
      ..fileOffers.add(
        const FileOfferInfo(
          fileId: 'image-1',
          path: 'assets/result.png',
          name: 'result.png',
          mimeType: 'image/png',
          sizeBytes: 68,
          reason: 'requested',
        ),
      )
      ..downloadedFiles.add(
        const DownloadedFileInfo(
          fileId: 'image-1',
          name: 'result.png',
          mimeType: 'image/png',
          sizeBytes: 68,
          dataBase64: imageBase64,
        ),
      );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          theme: buildCodexTheme(),
          home: Scaffold(
            body: MessageBubble(
              message: ChatMessage(
                id: 'file-offer-image',
                role: ChatRole.system,
                kind: AgentMessageKind.files,
                text: 'requested assets/result.png\nsize 68\nfileId image-1',
                createdAt: DateTime(2026),
                title: 'File available',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('image-preview-image-1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('file-activity-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image-preview-image-1')), findsOneWidget);
    final boundedPreview = tester
        .widgetList<ConstrainedBox>(find.byType(ConstrainedBox))
        .where(
          (widget) =>
              widget.constraints.maxWidth == 520 &&
              widget.constraints.maxHeight == 280,
        );
    expect(boundedPreview, hasLength(1));
  });

  testWidgets('error details are collapsed behind a compact row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'error-1',
              role: ChatRole.system,
              kind: AgentMessageKind.error,
              text: 'Very long bridge error\nstack line 1\nstack line 2',
              createdAt: DateTime(2026),
              title: 'Error',
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('error-compact-row')), findsOneWidget);
    expect(find.textContaining('stack line 1'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('error-compact-row')));
    await tester.pumpAndSettle();

    expect(find.textContaining('stack line 1'), findsOneWidget);
  });
}
