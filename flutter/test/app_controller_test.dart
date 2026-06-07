import 'package:codex_lan_flutter/app_controller.dart';
import 'package:codex_lan_flutter/protocol/bridge_messages.dart';
import 'package:codex_lan_flutter/services/bridge_socket_client.dart';
import 'package:codex_lan_flutter/services/pairing_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offline phase keeps cached chat visible without enabling sends', () {
    final controller = AppController()..phase = ConnectionPhase.offline;

    expect(controller.canShowChat, isTrue);
    expect(controller.isOffline, isTrue);
    expect(controller.isConnected, isFalse);
  });

  test('replaces session messages from host history replay', () {
    final controller = AppController()
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'History',
            'updatedAt': '2026-06-07T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    controller.handleBridgeMessageForTest({
      'type': 'message.history',
      'sessionId': 's1',
      'messages': [
        {
          'messageId': 'u1',
          'role': 'user',
          'kind': 'response',
          'text': 'hello',
          'createdAt': '2026-06-07T00:00:00.000Z',
          'complete': true,
        },
        {
          'messageId': 'cmd1',
          'role': 'system',
          'kind': 'executing',
          'title': 'Running command',
          'text': 'pnpm test\n2 tests passed\n',
          'createdAt': '2026-06-07T00:00:01.000Z',
          'complete': true,
        },
      ],
    });

    expect(controller.activeMessages, hasLength(2));
    expect(controller.activeMessages.last.text, contains('2 tests passed'));
  });

  test('filters replayed thinking noise from session history', () {
    final controller = AppController()
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'History',
            'updatedAt': '2026-06-07T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    controller.handleBridgeMessageForTest({
      'type': 'message.history',
      'sessionId': 's1',
      'messages': [
        {
          'messageId': 'thinking-old',
          'role': 'system',
          'kind': 'system',
          'text': 'Thinking…',
          'createdAt': '2026-06-07T00:00:00.000Z',
          'complete': false,
        },
        {
          'messageId': 'r1',
          'role': 'assistant',
          'kind': 'response',
          'title': 'Response',
          'text': 'hello',
          'createdAt': '2026-06-07T00:00:01.000Z',
          'complete': true,
        },
      ],
    });

    expect(controller.activeMessages, hasLength(1));
    expect(controller.activeMessages.single.text, 'hello');
  });

  test('stores host info from bridge bootstrap', () {
    final controller = AppController()
      ..handleBridgeMessageForTest({
        'type': 'host.info',
        'version': 3,
        'connectionMode': 'tunnel',
        'tunnelProvider': 'cloudflared',
        'publicUrl': 'wss://unit.trycloudflare.com',
        'localUrl': 'ws://127.0.0.1:8787',
        'hostLabel': 'Codex Link',
        'yoloAllowed': false,
      });

    expect(controller.hostInfo?.connectionMode, 'tunnel');
    expect(controller.hostInfo?.tunnelProvider, 'cloudflared');
    expect(controller.hostInfo?.publicUrl, 'wss://unit.trycloudflare.com');
  });

  test('parses v3 pairing payload tunnel metadata', () {
    final payload = parsePairingPayload(
      '{"version":3,"url":"wss://unit.trycloudflare.com","localUrl":"ws://127.0.0.1:8787","pairingToken":"abc","hostId":"host","connectionMode":"tunnel","tunnelProvider":"cloudflared","insecureDevMode":false}',
    );

    expect(payload.connectionMode, 'tunnel');
    expect(payload.tunnelProvider, 'cloudflared');
    expect(payload.localUrl, 'ws://127.0.0.1:8787');
  });

  test('applies large assistant deltas without artificial typewriter delay', () {
    final controller = AppController()
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Streaming',
            'updatedAt': '2026-06-07T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'running',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });
    const text =
        'This response should appear progressively instead of landing as one complete block in the chat UI.';

    controller.handleBridgeMessageForTest({
      'type': 'message.started',
      'sessionId': 's1',
      'runId': 'run-1',
      'messageId': 'r1',
      'kind': 'response',
      'role': 'assistant',
      'title': 'Response',
    });
    controller.handleBridgeMessageForTest({
      'type': 'message.delta',
      'sessionId': 's1',
      'runId': 'run-1',
      'messageId': 'r1',
      'text': text,
    });

    expect(controller.activeMessages.single.text, text);
  });

  test('parses external Codex sessions', () {
    final controller = AppController()
      ..handleBridgeMessageForTest({
        'type': 'external.session.list',
        'sessions': [
          {
            'externalSessionId': 'thread-1',
            'title': 'Old task',
            'createdAt': '2026-06-07T00:00:00.000Z',
            'updatedAt': '2026-06-07T00:00:01.000Z',
            'workdir': '/tmp/old',
            'codexThreadId': 'thread-1',
            'path': '/home/kurisu/.codex/sessions/session.jsonl',
          },
        ],
      });

    expect(controller.externalSessions, hasLength(1));
    expect(controller.externalSessions.single.workdir, '/tmp/old');
  });

  test('parses session model config from host records', () {
    final controller = AppController()
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Configured',
            'updatedAt': '2026-06-07T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
            'model': 'gpt-5-codex',
            'reasoningEffort': 'high',
          },
        ],
      });

    expect(controller.activeSession?.model, 'gpt-5-codex');
    expect(controller.activeSession?.reasoningEffort, 'high');
  });

  test('stores file offers and downloads from host', () {
    final controller = AppController()
      ..handleBridgeMessageForTest({
        'type': 'file.offer',
        'fileId': 'file-1',
        'sessionId': 's1',
        'path': 'lib/generated.dart',
        'name': 'generated.dart',
        'sizeBytes': 12,
        'reason': 'generated',
      });

    expect(controller.fileOffers.single.name, 'generated.dart');

    controller.handleBridgeMessageForTest({
      'type': 'file.download',
      'fileId': 'file-1',
      'name': 'generated.dart',
      'sizeBytes': 5,
      'dataBase64': 'aGVsbG8=',
    });

    expect(controller.downloadedFiles.single.dataBase64, 'aGVsbG8=');
  });

  test(
    'slash send requests a host file offer instead of asking the agent to paste contents',
    () {
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
              'updatedAt': '2026-06-07T00:00:00.000Z',
              'workspaceId': 'default',
              'workdir': '/tmp/repo',
              'lastStatus': 'idle',
              'mode': 'safe',
              'sandbox': 'workspace-write',
            },
          ],
        });

      controller.sendPrompt('/send lib/report.txt');

      expect(socket.sentMessages.single, {
        'type': 'file.offer.request',
        'sessionId': 's1',
        'path': 'lib/report.txt',
      });
      expect(controller.activeMessages.single.kind, AgentMessageKind.executing);
      expect(controller.activeMessages.single.title, 'Requesting file');
      expect(controller.activeMessages.single.text, contains('lib/report.txt'));
    },
  );

  test('slash send accepts @ file mention paths', () {
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
            'updatedAt': '2026-06-07T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    controller.sendPrompt('/send @lib/report.txt');

    expect(socket.sentMessages.single, {
      'type': 'file.offer.request',
      'sessionId': 's1',
      'path': 'lib/report.txt',
    });
  });

  test('searches and stores workspace file suggestions', () {
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
            'updatedAt': '2026-06-07T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    controller.searchWorkspaceFiles('@main', limit: 12);

    expect(socket.sentMessages.single, {
      'type': 'workspace.file.search',
      'sessionId': 's1',
      'query': 'main',
      'limit': 12,
    });

    controller.handleBridgeMessageForTest({
      'type': 'workspace.file.search.results',
      'sessionId': 's1',
      'query': 'main',
      'files': [
        {
          'path': 'lib/main.dart',
          'name': 'main.dart',
          'sizeBytes': 14,
          'mimeType': 'text/plain',
        },
      ],
    });

    expect(controller.fileSuggestionQuery, 'main');
    expect(controller.fileSuggestions.single.path, 'lib/main.dart');
  });

  test(
    'file offer replaces the pending request row and image offers auto-download',
    () {
      final socket = FakeBridgeSocketClient();
      final controller = AppController(socket: socket)
        ..phase = ConnectionPhase.connected
        ..handleBridgeMessageForTest({
          'type': 'session.list',
          'activeSessionId': 's1',
          'sessions': [
            {
              'sessionId': 's1',
              'title': 'Images',
              'updatedAt': '2026-06-07T00:00:00.000Z',
              'workspaceId': 'default',
              'workdir': '/tmp/repo',
              'lastStatus': 'idle',
              'mode': 'safe',
              'sandbox': 'workspace-write',
            },
          ],
        });

      controller.sendPrompt('/send assets/result.png');
      controller.handleBridgeMessageForTest({
        'type': 'file.offer',
        'fileId': 'image-1',
        'sessionId': 's1',
        'path': 'assets/result.png',
        'name': 'result.png',
        'mimeType': 'image/png',
        'sizeBytes': 68,
        'reason': 'requested',
      });

      expect(controller.activeMessages, hasLength(1));
      expect(controller.activeMessages.single.title, 'File available');
      expect(socket.sentMessages.last, {
        'type': 'file.request',
        'fileId': 'image-1',
      });
    },
  );
}

class FakeBridgeSocketClient extends BridgeSocketClient {
  final sentMessages = <Map<String, dynamic>>[];

  @override
  void send(Map<String, dynamic> message) {
    sentMessages.add(Map<String, dynamic>.from(message));
  }
}
