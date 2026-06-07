import 'package:codex_lan_flutter/app_controller.dart';
import 'package:codex_lan_flutter/protocol/bridge_messages.dart';
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

  test('streams large assistant deltas into the visible message', () async {
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

    expect(controller.activeMessages.single.text, isNot(text));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(controller.activeMessages.single.text, isNotEmpty);
    expect(text.startsWith(controller.activeMessages.single.text), isTrue);
    await controller.disposeController();
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
}
