import 'dart:async';

import 'package:codex_lan_flutter/app_controller.dart';
import 'package:codex_lan_flutter/protocol/bridge_messages.dart';
import 'package:codex_lan_flutter/services/app_notifier.dart';
import 'package:codex_lan_flutter/services/bridge_socket_client.dart';
import 'package:codex_lan_flutter/services/download_saver.dart';
import 'package:codex_lan_flutter/services/pairing_parser.dart';
import 'package:codex_lan_flutter/services/secure_credentials_store.dart';
import 'package:codex_lan_flutter/services/update_service.dart';
import 'package:codex_lan_flutter/services/voice_transcription_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offline phase keeps cached chat visible without enabling sends', () {
    final controller = AppController()..phase = ConnectionPhase.offline;

    expect(controller.canShowChat, isTrue);
    expect(controller.isOffline, isTrue);
    expect(controller.isConnected, isFalse);
  });

  test('saved credentials reopen the cached chat surface as offline', () async {
    final controller = AppController(
      store: FakeSecureCredentialsStore(
        const BridgeCredentials(
          url: 'wss://unit.trycloudflare.com',
          deviceToken: 'token',
          deviceId: 'phone',
        ),
      ),
    );

    await controller.loadSavedCredentials();

    expect(controller.credentials?.url, 'wss://unit.trycloudflare.com');
    expect(controller.phase, ConnectionPhase.offline);
    expect(controller.canShowChat, isTrue);
    expect(controller.statusText, contains('Offline'));
  });

  test(
    'saved reconnect keeps the cached chat surface visible while connecting',
    () async {
      final socket = FakeBridgeSocketClient(
        connectCompleter: Completer<void>(),
      );
      final controller = AppController(
        socket: socket,
        store: FakeSecureCredentialsStore(
          const BridgeCredentials(
            url: 'https://unit.trycloudflare.com',
            deviceToken: 'token',
            deviceId: 'phone',
          ),
        ),
      );
      await controller.loadSavedCredentials();

      await controller.reconnect();
      await Future<void>.delayed(Duration.zero);

      expect(socket.connectedUrl, 'wss://unit.trycloudflare.com');
      expect(controller.phase, ConnectionPhase.connecting);
      expect(controller.canShowChat, isTrue);

      await controller.disposeController();
    },
  );

  test('saved reconnect failures keep cached chat visible for retry', () async {
    final controller = AppController(
      socket: FakeBridgeSocketClient(connectError: StateError('down')),
      store: FakeSecureCredentialsStore(
        const BridgeCredentials(
          url: 'wss://unit.trycloudflare.com',
          deviceToken: 'token',
          deviceId: 'phone',
        ),
      ),
      autoReconnectDelay: const Duration(hours: 1),
    );
    await controller.loadSavedCredentials();

    await controller.reconnect();
    await Future<void>.delayed(Duration.zero);

    expect(controller.phase, ConnectionPhase.failed);
    expect(controller.canShowChat, isTrue);
    expect(controller.statusText, contains('Bridge error'));

    await controller.disposeController();
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

  test(
    'shell command requests and results are tracked in terminal history',
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
              'title': 'Shell',
              'updatedAt': '2026-06-07T00:00:00.000Z',
              'workspaceId': 'default',
              'workdir': '/tmp/repo',
              'lastStatus': 'idle',
              'mode': 'safe',
              'sandbox': 'workspace-write',
            },
          ],
        });

      controller.runShellCommand('pwd');
      expect(socket.sentMessages.single, {
        'type': 'shell.command.run',
        'sessionId': 's1',
        'command': 'pwd',
      });
      expect(controller.shellBusy, isTrue);

      controller.handleBridgeMessageForTest({
        'type': 'shell.command.result',
        'sessionId': 's1',
        'command': 'pwd',
        'exitCode': 0,
        'stdout': '/tmp/repo\n',
        'stderr': '',
        'durationMs': 9,
        'cwd': '/tmp/repo',
      });

      expect(controller.shellBusy, isFalse);
      expect(controller.shellHistory, hasLength(1));
      expect(controller.shellHistory.single.stdout, '/tmp/repo\n');
    },
  );

  test(
    'voice transcription result updates busy state and notice text',
    () async {
      final controller = AppController(
        voiceTranscriptionService: FakeVoiceTranscriptionService(
          const VoiceTranscriptionResult(text: 'write release notes'),
        ),
      );

      final result = await controller.transcribeVoiceInput();

      expect(result?.text, 'write release notes');
      expect(controller.voiceInputBusy, isFalse);
      expect(controller.voiceInputStatusText, isNull);
      expect(controller.latestErrorText, isNull);
    },
  );

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

  test('app-level slash commands route to native bridge controls', () {
    final socket = FakeBridgeSocketClient();
    final controller = AppController(socket: socket)
      ..phase = ConnectionPhase.connected
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
            'lastStatus': 'running',
            'mode': 'safe',
            'sandbox': 'workspace-write',
            'activeRunId': 'run-1',
          },
        ],
      });

    controller.runCommand(
      const CodexCommandInfo(
        commandId: 'codex.stop',
        title: 'Stop',
        description: 'Stop the current run',
        category: 'session',
      ),
    );
    controller.runCommand(
      const CodexCommandInfo(
        commandId: 'codex.new',
        title: 'New chat',
        description: 'Start a new session',
        category: 'session',
      ),
    );

    expect(socket.sentMessages, [
      {'type': 'run.cancel', 'sessionId': 's1', 'runId': 'run-1'},
      {
        'type': 'session.create',
        'title': 'New session',
        'workspaceId': 'default',
      },
    ]);
  });

  test('goal slash prompt uses native session goal RPC', () {
    final socket = FakeBridgeSocketClient();
    final controller = AppController(socket: socket)
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Goal',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    controller.sendPrompt('/goal Polish the chat UI');

    expect(controller.activeMessages.single.text, '/goal Polish the chat UI');
    expect(socket.sentMessages.single, {
      'type': 'session.goal.set',
      'sessionId': 's1',
      'objective': 'Polish the chat UI',
      'status': 'active',
    });
  });

  test('goal slash command can inspect and clear the native goal', () {
    final socket = FakeBridgeSocketClient();
    final controller = AppController(socket: socket)
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Goal',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    controller.sendPrompt('/goal');
    controller.sendPrompt('/goal clear');

    expect(socket.sentMessages, [
      {'type': 'session.goal.get', 'sessionId': 's1'},
      {'type': 'session.goal.clear', 'sessionId': 's1'},
    ]);
    expect(controller.activeMessages.map((message) => message.text), [
      '/goal',
      '/goal clear',
    ]);
  });

  test('active goal updates stay out of the chat timeline', () {
    final controller = AppController()
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Goal',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    controller.handleBridgeMessageForTest({
      'type': 'session.goal.updated',
      'sessionId': 's1',
      'goal': {
        'threadId': 'thread-1',
        'objective': 'Finish app-server adapter',
        'status': 'active',
        'tokenBudget': 20000,
        'tokensUsed': 15,
        'timeUsedSeconds': 2,
        'createdAt': 1,
        'updatedAt': 2,
      },
    });

    expect(
      controller.activeSession?.goal?.objective,
      'Finish app-server adapter',
    );
    expect(controller.activeMessages, isEmpty);

    controller.handleBridgeMessageForTest({
      'type': 'session.goal.updated',
      'sessionId': 's1',
      'goal': {
        'threadId': 'thread-1',
        'objective': 'Finish app-server adapter',
        'status': 'active',
        'tokenBudget': 20000,
        'tokensUsed': 55,
        'timeUsedSeconds': 8,
        'createdAt': 1,
        'updatedAt': 3,
      },
    });

    expect(controller.activeMessages, isEmpty);

    controller.handleBridgeMessageForTest({
      'type': 'session.goal.updated',
      'sessionId': 's1',
      'goal': {
        'threadId': 'thread-1',
        'objective': 'Finish app-server adapter',
        'status': 'complete',
        'tokenBudget': 20000,
        'tokensUsed': 120,
        'timeUsedSeconds': 30,
        'createdAt': 1,
        'updatedAt': 4,
      },
    });

    expect(controller.activeMessages.single.title, 'Goal complete');

    controller.handleBridgeMessageForTest({
      'type': 'session.goal.cleared',
      'sessionId': 's1',
    });

    expect(controller.activeSession?.goal, isNull);
    expect(controller.activeMessages.last.title, 'Goal cleared');
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

  test('keeps active run state scoped to the selected session', () {
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
            'workdir': '/tmp/repo-a',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
          {
            'sessionId': 's2',
            'title': 'Idle',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo-b',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    controller.handleBridgeMessageForTest({
      'type': 'run.started',
      'sessionId': 's1',
      'runId': 'run-1',
    });
    expect(controller.isRunning, isTrue);

    controller.selectSession('s2');

    expect(controller.activeSessionId, 's2');
    expect(controller.activeRunId, isNull);
    expect(controller.isRunning, isFalse);

    controller.cancelRun();

    expect(
      socket.sentMessages.where((message) => message['type'] == 'run.cancel'),
      isEmpty,
    );
  });

  test('routes run messages without session id by run id after switching', () {
    final controller = AppController(socket: FakeBridgeSocketClient())
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
            'workdir': '/tmp/repo-a',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
          {
            'sessionId': 's2',
            'title': 'Idle',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo-b',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    controller.handleBridgeMessageForTest({
      'type': 'run.started',
      'sessionId': 's1',
      'runId': 'run-1',
    });
    controller.selectSession('s2');
    controller.handleBridgeMessageForTest({
      'type': 'message.started',
      'runId': 'run-1',
      'messageId': 'thinking-1',
      'kind': 'thinking',
      'role': 'system',
      'title': 'Thinking',
    });

    expect(controller.messagesBySession['s1'], hasLength(1));
    expect(controller.messagesBySession['s2'], isEmpty);
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
            'serviceTier': 'priority',
            'goal': {
              'threadId': 'thread-1',
              'objective': 'Keep polish high',
              'status': 'active',
              'tokensUsed': 0,
              'timeUsedSeconds': 0,
              'createdAt': 1,
              'updatedAt': 1,
            },
          },
        ],
      });

    expect(controller.activeSession?.model, 'gpt-5-codex');
    expect(controller.activeSession?.reasoningEffort, 'high');
    expect(controller.activeSession?.serviceTier, 'priority');
    expect(controller.activeSession?.goal?.objective, 'Keep polish high');
  });

  test('updates selected accent color for themed markdown and controls', () {
    final controller = AppController();

    controller.setAccentName('blue');

    expect(controller.accentName, 'blue');
  });

  test('manual file downloads are saved to the device', () async {
    final saver = FakeDownloadSaver('/downloads/generated.dart');
    final controller = AppController(downloadSaver: saver)
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
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      })
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
    controller.requestFileDownload(controller.fileOffers.single);

    controller.handleBridgeMessageForTest({
      'type': 'file.download',
      'fileId': 'file-1',
      'name': 'generated.dart',
      'sizeBytes': 5,
      'dataBase64': 'aGVsbG8=',
    });
    await Future<void>.delayed(Duration.zero);

    expect(controller.downloadedFiles.single.dataBase64, 'aGVsbG8=');
    expect(saver.savedFiles.single.name, 'generated.dart');
    expect(saver.savedFiles.single.dataBase64, 'aGVsbG8=');
    expect(controller.savedFilePaths['file-1'], '/downloads/generated.dart');
    expect(controller.activeMessages.last.title, 'File saved');
    expect(
      controller.activeMessages.last.text,
      contains('/downloads/generated.dart'),
    );
  });

  test(
    'slash send requests a host file offer instead of asking the agent to paste contents',
    () {
      final socket = FakeBridgeSocketClient();
      final saver = FakeDownloadSaver('/downloads/result.png');
      final controller = AppController(socket: socket, downloadSaver: saver)
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

  test('slash send only uses the first unquoted file token', () {
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

    controller.sendPrompt('/send @lib/report.txt after checking it');

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

  test('sets workspace env secrets without storing secret values', () {
    final socket = FakeBridgeSocketClient();
    final controller = AppController(socket: socket)
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Env',
            'updatedAt': '2026-06-07T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    controller.setWorkspaceEnvSecrets(
      'OPENAI_API_KEY=sk-unit\nLIST=value1,value2',
    );

    expect(controller.envSecretsBusy, isTrue);
    expect(socket.sentMessages.single, {
      'type': 'workspace.env.set',
      'sessionId': 's1',
      'content': 'OPENAI_API_KEY=sk-unit\nLIST=value1,value2',
    });

    controller.handleBridgeMessageForTest({
      'type': 'workspace.env.updated',
      'sessionId': 's1',
      'path': '.env.local',
      'variableNames': ['OPENAI_API_KEY', 'LIST'],
      'skippedLineCount': 0,
    });

    expect(controller.envSecretsBusy, isFalse);
    expect(controller.envSecretsStatusText, contains('OPENAI_API_KEY'));
    expect(controller.envSecretsStatusText, isNot(contains('sk-unit')));
  });

  test('stores native app-server capability messages and routes actions', () {
    final socket = FakeBridgeSocketClient();
    final controller = AppController(socket: socket)
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Native',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    controller.refreshAppModels();
    controller.refreshAppThreads(query: 'native', limit: 5);
    controller.refreshAppSkills(forceReload: true);
    controller.listAppDirectory('lib');
    controller.readAppFile('README.md');
    controller.writeAppFile('lib/generated.dart', 'dm9pZCBtYWluKCkge30K');
    controller.createAppDirectory('lib/widgets');
    controller.setSessionConfig(serviceTier: 'priority');
    controller.searchAppFiles('@main', limit: 8);
    controller.startReview(instructions: 'review this');

    expect(socket.sentMessages.take(10).toList(), [
      {'type': 'app.model.list', 'sessionId': 's1'},
      {
        'type': 'app.thread.list',
        'sessionId': 's1',
        'query': 'native',
        'limit': 5,
      },
      {'type': 'app.skill.list', 'sessionId': 's1', 'forceReload': true},
      {'type': 'app.fs.list', 'sessionId': 's1', 'path': 'lib'},
      {'type': 'app.fs.read', 'sessionId': 's1', 'path': 'README.md'},
      {
        'type': 'app.fs.write',
        'sessionId': 's1',
        'path': 'lib/generated.dart',
        'dataBase64': 'dm9pZCBtYWluKCkge30K',
      },
      {
        'type': 'app.fs.createDirectory',
        'sessionId': 's1',
        'path': 'lib/widgets',
      },
      {
        'type': 'session.config.set',
        'sessionId': 's1',
        'serviceTier': 'priority',
      },
      {
        'type': 'app.file.search',
        'sessionId': 's1',
        'query': '@main',
        'limit': 8,
      },
      {
        'type': 'app.review.start',
        'sessionId': 's1',
        'target': 'custom',
        'instructions': 'review this',
        'delivery': 'inline',
      },
    ]);

    controller.handleBridgeMessageForTest({
      'type': 'app.model.list',
      'models': [
        {
          'id': 'gpt-test',
          'model': 'gpt-test',
          'displayName': 'GPT Test',
          'hidden': false,
          'supportedReasoningEfforts': ['low', 'high'],
          'inputModalities': ['text', 'image'],
          'supportsPersonality': true,
          'serviceTiers': [
            {
              'id': 'priority',
              'name': 'Priority',
              'description': 'Faster responses for more credits',
            },
          ],
          'defaultServiceTier': null,
          'isDefault': true,
        },
      ],
      'capabilities': {
        'namespaceTools': true,
        'imageGeneration': true,
        'webSearch': true,
      },
    });
    controller.handleBridgeMessageForTest({
      'type': 'app.thread.list',
      'threads': [
        {
          'threadId': 'thread-1',
          'title': 'Thread',
          'preview': 'Thread',
          'createdAt': '2026-06-08T00:00:00.000Z',
          'updatedAt': '2026-06-08T00:00:00.000Z',
          'workdir': '/tmp/repo',
          'parentThreadId': 'parent-thread',
          'agentNickname': 'Explorer',
          'agentRole': 'explorer',
        },
      ],
    });
    controller.handleBridgeMessageForTest({
      'type': 'app.skill.list',
      'groups': [
        {
          'cwd': '/tmp/repo',
          'skills': [
            {
              'name': 'flutter-design-system',
              'description': 'Token discipline',
              'path': '/tmp/SKILL.md',
              'enabled': true,
            },
          ],
          'errors': [],
        },
      ],
    });
    controller.handleBridgeMessageForTest({
      'type': 'app.fs.list',
      'sessionId': 's1',
      'path': 'lib',
      'entries': [
        {
          'path': 'lib/main.dart',
          'name': 'main.dart',
          'isDirectory': false,
          'isFile': true,
        },
      ],
    });
    controller.handleBridgeMessageForTest({
      'type': 'app.fs.file',
      'sessionId': 's1',
      'file': {
        'path': 'README.md',
        'name': 'README.md',
        'sizeBytes': 7,
        'mimeType': 'text/plain',
        'text': '# Unit\n',
      },
    });
    controller.handleBridgeMessageForTest({
      'type': 'app.fs.write.result',
      'sessionId': 's1',
      'file': {
        'path': 'lib/generated.dart',
        'name': 'generated.dart',
        'sizeBytes': 13,
        'mimeType': 'text/plain',
        'text': 'void main() {}\n',
      },
    });
    controller.handleBridgeMessageForTest({
      'type': 'app.fs.directory.created',
      'sessionId': 's1',
      'path': 'lib/widgets',
    });
    controller.handleBridgeMessageForTest({
      'type': 'app.file.search.results',
      'sessionId': 's1',
      'query': 'main',
      'files': [
        {'path': 'lib/main.dart', 'name': 'main.dart'},
      ],
    });
    controller.handleBridgeMessageForTest({
      'type': 'approval.requested',
      'sessionId': 's1',
      'approvalId': 'approval-1',
      'title': 'Approve command',
      'body': 'pnpm test',
      'riskLevel': 'medium',
    });

    expect(controller.appModels.single.displayName, 'GPT Test');
    expect(controller.appModels.single.serviceTiers.single.id, 'priority');
    expect(controller.appCapabilities?.webSearch, isTrue);
    expect(controller.appThreads.single.threadId, 'thread-1');
    expect(controller.appThreads.single.parentThreadId, 'parent-thread');
    expect(controller.appThreads.single.agentNickname, 'Explorer');
    expect(controller.appThreads.single.agentRole, 'explorer');
    expect(
      controller.appSkillGroups.single.skills.single.name,
      'flutter-design-system',
    );
    expect(controller.appFileEntries.single.path, 'lib/main.dart');
    expect(controller.appPreviewFile?.text, 'void main() {}\n');
    expect(controller.appFsStatusText, 'Created lib/widgets.');
    expect(controller.appFileSearchResults.single.name, 'main.dart');
    expect(controller.activeMessages.last.kind, AgentMessageKind.approval);

    controller.decideApproval('approval-1', 'approve');
    expect(socket.sentMessages.last, {
      'type': 'approval.decision',
      'sessionId': 's1',
      'approvalId': 'approval-1',
      'decision': 'approve',
    });
  });

  test('stores structured subagent state separately from chat history', () {
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
      });

    controller.handleBridgeMessageForTest({
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
    });

    expect(controller.activeSubagents.single.threadId, 'thread-child');
    expect(controller.activeSubagents.single.agentNickname, 'Explorer');
    expect(controller.activeMessages, isEmpty);
  });

  test('Codex account auth actions route through the host bridge', () {
    final socket = FakeBridgeSocketClient();
    final controller = AppController(socket: socket)
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Account',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    controller.refreshCodexAccount(refreshToken: true);
    controller.startCodexDeviceLogin();
    controller.startCodexBrowserLogin();
    controller.loginCodexWithApiKey(' sk-unit-secret ');
    controller.cancelCodexLogin('login-device');
    controller.logoutCodexAccount();

    expect(socket.sentMessages, [
      {'type': 'app.account.read', 'refreshToken': true},
      {'type': 'app.account.login.start', 'loginType': 'chatgptDeviceCode'},
      {'type': 'app.account.login.start', 'loginType': 'chatgpt'},
      {
        'type': 'app.account.login.start',
        'loginType': 'apiKey',
        'apiKey': 'sk-unit-secret',
      },
      {'type': 'app.account.login.cancel', 'loginId': 'login-device'},
      {'type': 'app.account.logout'},
    ]);

    controller.handleBridgeMessageForTest({
      'type': 'app.account.status',
      'account': {
        'accountType': 'chatgpt',
        'email': 'unit@example.com',
        'planType': 'pro',
        'authMode': 'chatgpt',
        'requiresOpenaiAuth': false,
      },
    });
    controller.handleBridgeMessageForTest({
      'type': 'app.account.login.started',
      'flow': {
        'type': 'chatgptDeviceCode',
        'loginId': 'login-device',
        'verificationUrl': 'https://auth.openai.com/activate',
        'userCode': 'CODE-123',
      },
    });

    expect(controller.codexAccount?.email, 'unit@example.com');
    expect(controller.codexAccount?.displayLabel, contains('unit@example.com'));
    expect(controller.activeCodexLogin?.type, 'chatgptDeviceCode');
    expect(controller.activeCodexLogin?.userCode, 'CODE-123');

    controller.handleBridgeMessageForTest({
      'type': 'app.account.login.completed',
      'loginId': 'login-device',
      'success': true,
      'error': null,
    });

    expect(controller.activeCodexLogin, isNull);
    expect(controller.latestNotice?.title, 'Codex login complete');
  });

  test('interactive app-server actions route and store bridge results', () {
    final socket = FakeBridgeSocketClient();
    final controller = AppController(socket: socket)
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Actions',
            'updatedAt': '2026-06-09T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    controller.refreshAppServerActions();
    controller.readAppPlugin('github', marketplacePath: '/tmp/marketplace');
    controller.installAppPlugin('github', marketplacePath: '/tmp/marketplace');
    controller.uninstallAppPlugin('github');
    controller.startAppMcpOauthLogin('github');
    controller.startRemotePairing(manualPairingCode: '123456');
    controller.runHostUpdate();

    expect(socket.sentMessages, [
      {'type': 'app.plugin.list', 'sessionId': 's1'},
      {
        'type': 'app.mcp.status.list',
        'sessionId': 's1',
        'detail': 'toolsAndAuthOnly',
      },
      {'type': 'app.remote.status.read'},
      {'type': 'app.account.rateLimits.read'},
      {'type': 'host.update.check'},
      {
        'type': 'app.plugin.read',
        'pluginName': 'github',
        'marketplacePath': '/tmp/marketplace',
      },
      {
        'type': 'app.plugin.install',
        'pluginName': 'github',
        'marketplacePath': '/tmp/marketplace',
      },
      {'type': 'app.plugin.uninstall', 'pluginName': 'github'},
      {'type': 'app.mcp.oauth.login', 'serverName': 'github'},
      {'type': 'app.remote.pairing.start', 'manualPairingCode': '123456'},
      {'type': 'host.update.run'},
    ]);

    controller.handleBridgeMessageForTest({
      'type': 'app.plugin.list',
      'marketplaces': [
        {
          'name': 'openai-curated',
          'displayName': 'OpenAI curated',
          'path': '/tmp/marketplace',
          'plugins': [
            {
              'name': 'github',
              'displayName': 'GitHub',
              'description': 'Work with GitHub issues.',
              'installed': false,
              'enabled': true,
            },
          ],
        },
      ],
    });
    controller.handleBridgeMessageForTest({
      'type': 'app.plugin.detail',
      'plugin': {
        'name': 'github',
        'displayName': 'GitHub',
        'description': 'Work with GitHub issues.',
        'skills': [
          {'name': 'github-prs', 'description': 'Review pull requests.'},
        ],
        'apps': [
          {
            'name': 'github',
            'authStatus': 'unauthenticated',
            'installUrl': 'https://github.com/apps/codex',
          },
        ],
        'mcpServers': [
          {'name': 'github', 'authStatus': 'unauthenticated', 'toolCount': 8},
        ],
      },
    });
    controller.handleBridgeMessageForTest({
      'type': 'app.plugin.install.result',
      'pluginName': 'github',
      'installed': true,
      'appsNeedingAuth': [
        {'name': 'github', 'installUrl': 'https://github.com/apps/codex'},
      ],
    });
    controller.handleBridgeMessageForTest({
      'type': 'app.mcp.status.list',
      'servers': [
        {
          'name': 'github',
          'status': 'enabled',
          'authStatus': 'unauthenticated',
          'toolCount': 2,
          'tools': ['search_issues', 'create_issue'],
          'resourceCount': 1,
        },
      ],
    });
    controller.handleBridgeMessageForTest({
      'type': 'app.mcp.oauth.login.started',
      'serverName': 'github',
      'loginUrl': 'https://github.com/login/oauth/authorize',
    });
    controller.handleBridgeMessageForTest({
      'type': 'app.remote.status',
      'status': {
        'enabled': true,
        'connectionStatus': 'connected',
        'serverName': 'unit-host',
        'environmentId': 'env-1',
      },
    });
    controller.handleBridgeMessageForTest({
      'type': 'app.remote.pairing.started',
      'pairing': {
        'pairingCode': 'PAIR-123',
        'manualPairingCode': '123456',
        'environmentId': 'env-1',
      },
    });
    controller.handleBridgeMessageForTest({
      'type': 'app.account.rateLimits',
      'limits': [
        {
          'limitId': 'codex',
          'planType': 'pro',
          'usedPercent': 5,
          'remainingPercent': 95,
          'windowDurationMins': 43200,
        },
      ],
    });
    controller.handleBridgeMessageForTest({
      'type': 'host.update.status',
      'packageName': 'codex-link-host',
      'currentVersion': '0.1.1',
      'latestVersion': '0.1.2',
      'updateAvailable': true,
      'updateRunning': false,
    });
    controller.handleBridgeMessageForTest({
      'type': 'host.update.progress',
      'packageName': 'codex-link-host',
      'phase': 'installing',
      'line': 'installing codex-link-host@latest',
    });
    controller.handleBridgeMessageForTest({
      'type': 'host.update.result',
      'packageName': 'codex-link-host',
      'previousVersion': '0.1.1',
      'latestVersion': '0.1.2',
      'updated': true,
      'exitCode': 0,
      'stdout': 'updated',
      'stderr': '',
      'restartRequired': true,
      'message': 'Restart host to use the new version.',
    });

    expect(
      controller.appPluginMarketplaces.single.plugins.single.name,
      'github',
    );
    expect(controller.appSelectedPlugin?.skills.single.name, 'github-prs');
    expect(controller.appPluginInstallResult?.installed, isTrue);
    expect(controller.appMcpServers.single.tools, contains('create_issue'));
    expect(controller.appMcpOauthLogin?.loginUrl, contains('github.com'));
    expect(controller.appRemoteStatus?.serverName, 'unit-host');
    expect(controller.appRemoteStatus?.connectionStatus, 'connected');
    expect(controller.appRemotePairing?.manualPairingCode, '123456');
    expect(controller.appRateLimits.single.remainingPercent, 95);
    expect(controller.hostUpdateStatus?.updateAvailable, isTrue);
    expect(controller.hostUpdateProgress.single.phase, 'installing');
    expect(controller.hostUpdateResult?.updated, isTrue);
    expect(controller.hostUpdateBusy, isFalse);
    expect(controller.latestNotice?.title, 'Host update finished');
  });

  test(
    'file offer replaces the pending request row and image offers auto-download',
    () {
      final socket = FakeBridgeSocketClient();
      final saver = FakeDownloadSaver('/downloads/result.png');
      final controller = AppController(socket: socket, downloadSaver: saver)
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
      expect(controller.activeMessages.single.title, 'File activity');
      expect(socket.sentMessages.last, {
        'type': 'file.request',
        'fileId': 'image-1',
      });
      expect(saver.savedFiles, isEmpty);
    },
  );

  test('generated file offers merge into the existing file activity item', () {
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Generated files',
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

    controller.handleBridgeMessageForTest({
      'type': 'diff.available',
      'sessionId': 's1',
      'files': [
        {
          'path': 'lib/generated.dart',
          'status': 'added',
          'patch': '+class Generated {}',
        },
      ],
    });
    controller.handleBridgeMessageForTest({
      'type': 'file.offer',
      'fileId': 'file-1',
      'sessionId': 's1',
      'path': 'lib/generated.dart',
      'name': 'generated.dart',
      'sizeBytes': 12,
      'reason': 'generated',
    });

    expect(controller.activeMessages, hasLength(1));
    expect(controller.activeMessages.single.kind, AgentMessageKind.files);
    expect(controller.activeMessages.single.title, 'File activity');
    expect(controller.activeMessages.single.text, contains('fileId file-1'));
  });

  test('bridge errors update compact error state instead of chat history', () {
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Errors',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/repo',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
        ],
      });

    controller.handleBridgeMessageForTest({
      'type': 'error',
      'code': 'bridge.error',
      'message': 'Very long host error\nwith stack trace',
    });

    expect(controller.activeMessages, isEmpty);
    expect(controller.latestErrorText, contains('Very long host error'));
  });

  test('remaining mobile commands route to native app controls', () {
    final socket = FakeBridgeSocketClient();
    final controller = AppController(socket: socket)
      ..phase = ConnectionPhase.connected
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

    controller.runCommand(
      const CodexCommandInfo(
        commandId: 'codex.review',
        title: 'review',
        description: 'unit',
        category: 'agent',
      ),
    );

    expect(socket.sentMessages, [
      {
        'type': 'app.review.start',
        'sessionId': 's1',
        'target': 'uncommittedChanges',
        'delivery': 'inline',
      },
    ]);
  });

  test(
    'plan updates create compact ui notices without foreground notifications',
    () {
      final notifier = FakeAppNotifier();
      final controller = AppController(notifier: notifier)
        ..phase = ConnectionPhase.connected
        ..handleBridgeMessageForTest({
          'type': 'session.list',
          'activeSessionId': 's1',
          'sessions': [
            {
              'sessionId': 's1',
              'title': 'Plan notifications',
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

      controller.handleBridgeMessageForTest({
        'type': 'session.plan.updated',
        'sessionId': 's1',
        'runId': 'run-1',
        'title': 'Plan',
        'text': 'Refining the UI\n- in_progress: Move command panels',
      });

      expect(controller.latestNotice?.title, 'Plan updated');
      expect(controller.latestNotice?.body, 'Refining the UI');
      expect(notifier.notifications, isEmpty);
    },
  );

  test('notification category toggles suppress matching notices', () {
    final notifier = FakeAppNotifier();
    final controller = AppController(notifier: notifier)
      ..phase = ConnectionPhase.connected
      ..setNotificationCategoryEnabled(AppNotificationCategory.plan, false)
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Plan notifications',
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

    controller.handleBridgeMessageForTest({
      'type': 'session.plan.updated',
      'sessionId': 's1',
      'runId': 'run-1',
      'title': 'Plan',
      'text': 'Refining the UI\n- in_progress: Move command panels',
    });

    expect(controller.latestNotice, isNull);
    expect(notifier.notifications, isEmpty);
  });

  test('task notification toggle suppresses background completion alerts', () {
    final notifier = FakeAppNotifier();
    final controller = AppController(notifier: notifier)
      ..phase = ConnectionPhase.connected
      ..setAppForeground(false)
      ..setNotificationCategoryEnabled(AppNotificationCategory.task, false)
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Completion',
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

    controller.handleBridgeMessageForTest({
      'type': 'run.completed',
      'sessionId': 's1',
      'runId': 'run-1',
      'exitCode': 0,
    });

    expect(controller.latestNotice, isNull);
    expect(notifier.notifications, isEmpty);
  });

  test(
    'completed runs notify the phone only while the app is backgrounded',
    () {
      final notifier = FakeAppNotifier();
      final controller = AppController(notifier: notifier)
        ..phase = ConnectionPhase.connected
        ..setAppForeground(false)
        ..handleBridgeMessageForTest({
          'type': 'session.list',
          'activeSessionId': 's1',
          'sessions': [
            {
              'sessionId': 's1',
              'title': 'Completion',
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
              'text': 'Done with app-server actions\nTests are next',
              'createdAt': '2026-06-08T00:00:01.000Z',
              'complete': true,
            },
          ],
        });

      controller.handleBridgeMessageForTest({
        'type': 'run.completed',
        'sessionId': 's1',
        'runId': 'run-1',
        'exitCode': 0,
      });

      expect(controller.latestNotice?.title, 'Task finished');
      expect(
        controller.latestNotice?.body,
        contains('Done with app-server actions'),
      );
      expect(notifier.notifications.single.title, 'Task finished');
    },
  );

  test('disconnect churn does not send phone notifications', () async {
    final socket = FakeBridgeSocketClient();
    final notifier = FakeAppNotifier();
    final controller = AppController(
      socket: socket,
      notifier: notifier,
      store: FakeSecureCredentialsStore(
        const BridgeCredentials(
          url: 'wss://unit.trycloudflare.com',
          deviceToken: 'token',
          deviceId: 'phone',
        ),
      ),
      autoReconnectDelay: const Duration(hours: 1),
    );
    controller.setAppForeground(false);
    await controller.loadSavedCredentials();

    await controller.reconnect();
    await Future<void>.delayed(Duration.zero);
    socket.emitMessage({
      'type': 'auth.accepted',
      'deviceToken': 'token',
      'deviceId': 'phone',
    });

    expect(controller.phase, ConnectionPhase.connected);

    socket.closeFromServer();

    expect(controller.phase, ConnectionPhase.offline);
    expect(controller.latestNotice?.payload, isNot('connection:offline'));
    expect(notifier.notifications, isEmpty);
  });

  test('older host workspace lists still expose playground', () {
    final controller = AppController()
      ..handleBridgeMessageForTest({
        'type': 'workspace.list',
        'workspaces': [
          {
            'workspaceId': 'default',
            'label': 'repo',
            'path': '/tmp/repo',
            'active': true,
          },
        ],
      });

    expect(
      controller.workspaces.map((workspace) => workspace.workspaceId),
      contains('playground'),
    );
    expect(
      controller.workspaces
          .firstWhere((workspace) => workspace.workspaceId == 'playground')
          .displayName,
      'Playground',
    );
  });

  test('update checks expose available release and in-app notice', () async {
    final update = AppUpdateInfo(
      currentVersion: '1.0.0',
      latestVersion: '1.0.1',
      title: 'Codex Link v1.0.1',
      releaseUrl: Uri.parse(
        'https://github.com/makise-ui/codex-link/releases/tag/v1.0.1',
      ),
      apkUrl: Uri.parse('https://example.com/codex-link.apk'),
      hasUpdate: true,
    );
    final controller = AppController(updateService: FakeUpdateService(update));

    await controller.checkForUpdates();

    expect(controller.updateStatus, UpdateCheckStatus.available);
    expect(controller.availableUpdate, update);
    expect(controller.latestNotice?.title, 'Update available');
    expect(controller.latestNotice?.body, contains('1.0.1'));
  });

  test('private GitHub release failures use actionable update text', () async {
    final controller = AppController(
      updateService: ThrowingUpdateService(
        const GitHubReleaseUnavailableException(
          owner: 'makise-ui',
          repo: 'codex-link',
          statusCode: 404,
        ),
      ),
    );

    await controller.checkForUpdates();

    expect(controller.updateStatus, UpdateCheckStatus.failed);
    expect(controller.updateErrorText, contains('private'));
    expect(controller.latestNotice?.title, 'Update check failed');
    expect(controller.latestNotice?.body, contains('private'));
  });
}

class FakeAppNotifier implements AppNotifier {
  final notifications = <AppNotification>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({
    required String title,
    required String body,
    String? payload,
  }) async {
    notifications.add(
      AppNotification(title: title, body: body, payload: payload),
    );
  }
}

class AppNotification {
  const AppNotification({
    required this.title,
    required this.body,
    this.payload,
  });

  final String title;
  final String body;
  final String? payload;
}

class FakeBridgeSocketClient extends BridgeSocketClient {
  FakeBridgeSocketClient({this.connectCompleter, this.connectError});

  final Completer<void>? connectCompleter;
  final Object? connectError;
  final sentMessages = <Map<String, dynamic>>[];
  String? connectedUrl;
  void Function(Map<String, dynamic> message)? onMessageCallback;
  void Function(Object error)? onErrorCallback;
  void Function()? onDoneCallback;

  @override
  Future<void> connect({
    required String url,
    required void Function(Map<String, dynamic> message) onMessage,
    required void Function(Object error) onError,
    required void Function() onDone,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    connectedUrl = normalizeBridgeWebSocketUrl(url);
    onMessageCallback = onMessage;
    onErrorCallback = onError;
    onDoneCallback = onDone;
    final error = connectError;
    if (error != null) throw error;
    await (connectCompleter?.future ?? Future<void>.value());
  }

  @override
  void send(Map<String, dynamic> message) {
    sentMessages.add(Map<String, dynamic>.from(message));
  }

  @override
  Future<void> close() async {}

  void emitMessage(Map<String, dynamic> message) {
    onMessageCallback?.call(message);
  }

  void emitError(Object error) {
    onErrorCallback?.call(error);
  }

  void closeFromServer() {
    onDoneCallback?.call();
  }
}

class FakeDownloadSaver implements FileDownloadSaver {
  FakeDownloadSaver(this.path);

  final String? path;
  final savedFiles = <DownloadedFileInfo>[];

  @override
  Future<String?> save(DownloadedFileInfo file) async {
    savedFiles.add(file);
    return path;
  }
}

class FakeUpdateService implements AppUpdateService {
  FakeUpdateService(this.update);

  final AppUpdateInfo update;
  AppUpdateInfo? opened;

  @override
  Future<AppUpdateInfo> checkForUpdate() async => update;

  @override
  Future<bool> openUpdate(AppUpdateInfo update) async {
    opened = update;
    return true;
  }

  @override
  Future<bool> openProjectPage() async => true;
}

class ThrowingUpdateService implements AppUpdateService {
  const ThrowingUpdateService(this.error);

  final Object error;

  @override
  Future<AppUpdateInfo> checkForUpdate() async => throw error;

  @override
  Future<bool> openUpdate(AppUpdateInfo update) async => true;

  @override
  Future<bool> openProjectPage() async => true;
}

class FakeVoiceTranscriptionService implements VoiceTranscriptionService {
  const FakeVoiceTranscriptionService(this.result);

  final VoiceTranscriptionResult result;

  @override
  Future<VoiceTranscriptionResult> transcribeOnce() async => result;
}

class FakeSecureCredentialsStore extends SecureCredentialsStore {
  FakeSecureCredentialsStore(this.saved);

  BridgeCredentials? saved;

  @override
  Future<BridgeCredentials?> load() async => saved;

  @override
  Future<void> save(BridgeCredentials credentials) async {
    saved = credentials;
  }

  @override
  Future<void> clear() async {
    saved = null;
  }
}
