import 'package:codex_lan_flutter/app_controller.dart';
import 'package:codex_lan_flutter/chat/file_browser_screen.dart';
import 'package:codex_lan_flutter/protocol/bridge_messages.dart';
import 'package:codex_lan_flutter/services/bridge_socket_client.dart';
import 'package:codex_lan_flutter/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'file browser lists workspace files and returns a selected path',
    (tester) async {
      final socket = FakeBridgeSocketClient();
      final controller = AppController(socket: socket)
        ..phase = ConnectionPhase.connected
        ..handleBridgeMessageForTest({
          'type': 'session.list',
          'activeSessionId': 's1',
          'sessions': [
            {
              'sessionId': 's1',
              'title': 'Files',
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
          'type': 'app.fs.list',
          'sessionId': 's1',
          'path': 'lib',
          'entries': [
            {
              'path': 'lib/main.dart',
              'name': 'main.dart',
              'isDirectory': false,
              'isFile': true,
              'sizeBytes': 24,
              'mimeType': 'text/plain',
            },
          ],
        });
      String? selectedPath;

      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: controller,
          child: MaterialApp(
            theme: buildCodexTheme(),
            home: Builder(
              builder: (context) {
                return FilledButton(
                  onPressed: () async {
                    selectedPath = await Navigator.of(context).push<String>(
                      MaterialPageRoute(
                        builder: (_) => const FileBrowserScreen(),
                      ),
                    );
                  },
                  child: const Text('Open files'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(find.text('Workspace explorer'), findsOneWidget);
      expect(find.text('main.dart'), findsOneWidget);
      expect(socket.sentMessages.last, {
        'type': 'app.fs.list',
        'sessionId': 's1',
        'path': '',
      });

      await tester.tap(find.byTooltip('Use in chat'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(selectedPath, 'lib/main.dart');
    },
  );

  testWidgets('file browser edits and saves text files', (tester) async {
    final socket = FakeBridgeSocketClient();
    final controller = AppController(socket: socket)
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Files',
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
        'type': 'app.fs.list',
        'sessionId': 's1',
        'path': '',
        'entries': [
          {
            'path': 'lib/main.dart',
            'name': 'main.dart',
            'isDirectory': false,
            'isFile': true,
            'sizeBytes': 14,
            'mimeType': 'text/plain',
          },
        ],
      })
      ..handleBridgeMessageForTest({
        'type': 'app.fs.file',
        'sessionId': 's1',
        'file': {
          'path': 'lib/main.dart',
          'name': 'main.dart',
          'sizeBytes': 14,
          'mimeType': 'text/plain',
          'text': 'void main() {}\n',
        },
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          theme: buildCodexTheme(),
          home: const FileBrowserScreen(),
        ),
      ),
    );
    await tester.pump();
    controller.handleBridgeMessageForTest({
      'type': 'app.fs.list',
      'sessionId': 's1',
      'path': '',
      'entries': [
        {
          'path': 'lib/main.dart',
          'name': 'main.dart',
          'isDirectory': false,
          'isFile': true,
          'sizeBytes': 14,
          'mimeType': 'text/plain',
        },
      ],
    });
    await tester.pump();

    await tester.tap(find.byTooltip('Edit file'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('file-editor-input')),
      'void main() {\n  print("hi");\n}\n',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Save file'));
    await tester.pump();

    expect(socket.sentMessages.last, {
      'type': 'app.fs.write',
      'sessionId': 's1',
      'path': 'lib/main.dart',
      'dataBase64': 'dm9pZCBtYWluKCkgewogIHByaW50KCJoaSIpOwp9Cg==',
    });
  });

  testWidgets('plain text preview does not invoke syntax highlighter', (
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
        'type': 'app.fs.file',
        'sessionId': 's1',
        'file': {
          'path': 'example.txt',
          'name': 'example.txt',
          'sizeBytes': 18,
          'mimeType': 'text/plain',
          'text': 'plain text preview',
        },
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          theme: buildCodexTheme(),
          home: const FileBrowserScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('plain text preview'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
