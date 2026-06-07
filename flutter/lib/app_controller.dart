import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'protocol/bridge_messages.dart';
import 'services/bridge_socket_client.dart';
import 'services/pairing_parser.dart';
import 'services/secure_credentials_store.dart';

class AppController extends ChangeNotifier {
  AppController({BridgeSocketClient? socket, SecureCredentialsStore? store})
      : _socket = socket ?? BridgeSocketClient(),
        _store = store ?? SecureCredentialsStore();

  final BridgeSocketClient _socket;
  final SecureCredentialsStore _store;
  final _uuid = const Uuid();

  ConnectionPhase phase = ConnectionPhase.idle;
  String statusText = 'Scan the host QR to pair on your LAN.';
  BridgeCredentials? credentials;
  String? activeSessionId;
  String? activeRunId;
  String? _pendingUrl;
  int _connectGeneration = 0;

  final List<CodexSessionInfo> sessions = [];
  final List<WorkspaceInfo> workspaces = [];
  final List<CodexCommandInfo> commands = [];
  final Map<String, List<ChatMessage>> messagesBySession = {};

  CodexSessionInfo? get activeSession {
    final id = activeSessionId;
    if (id == null) return sessions.isEmpty ? null : sessions.first;
    return sessions.where((session) => session.sessionId == id).firstOrNull;
  }

  List<ChatMessage> get activeMessages {
    final id = activeSession?.sessionId;
    if (id == null) return const [];
    return messagesBySession[id] ?? const [];
  }

  bool get isConnected => phase == ConnectionPhase.connected;
  bool get isRunning => activeSession?.isRunning == true || activeRunId != null;

  Future<void> loadSavedCredentials() async {
    credentials = await _store.load();
    if (credentials != null) {
      statusText = 'Saved bridge found. Tap reconnect or scan a fresh QR.';
      notifyListeners();
    }
  }

  Future<void> pair(String rawPayload, String deviceName) async {
    try {
      final payload = parsePairingPayload(rawPayload);
      if (payload.url.isEmpty || payload.pairingToken.isEmpty) {
        throw const FormatException('Pairing QR is missing url or token.');
      }
      _pendingUrl = payload.url;
      _connect(payload.url, {'type': 'pairing.claim', 'pairingToken': payload.pairingToken, 'deviceName': deviceName.trim().isEmpty ? 'Flutter Codex Controller' : deviceName.trim()});
    } catch (error) {
      phase = ConnectionPhase.failed;
      statusText = 'Pairing payload error: $error';
      notifyListeners();
    }
  }

  Future<void> reconnect() async {
    final saved = credentials ?? await _store.load();
    if (saved == null) {
      statusText = 'No saved bridge credentials.';
      notifyListeners();
      return;
    }
    credentials = saved;
    _pendingUrl = saved.url;
    _connect(saved.url, {'type': 'auth.resume', 'deviceToken': saved.deviceToken});
  }

  Future<void> forgetSaved() async {
    await _store.clear();
    credentials = null;
    phase = ConnectionPhase.idle;
    statusText = 'Saved bridge removed.';
    await _socket.close();
    notifyListeners();
  }

  Future<void> cancelConnection() async {
    _connectGeneration++;
    await _socket.close();
    phase = ConnectionPhase.idle;
    statusText = 'Connection cancelled.';
    notifyListeners();
  }

  void createSession() {
    _send({'type': 'session.create', 'title': 'New session', 'workspaceId': activeSession?.workspaceId ?? 'default'});
  }

  void selectSession(String sessionId) {
    activeSessionId = sessionId;
    _send({'type': 'session.start', 'sessionId': sessionId});
    _send({'type': 'workspace.list'});
    notifyListeners();
  }

  void renameSession(String sessionId, String title) {
    if (title.trim().isEmpty) return;
    _send({'type': 'session.rename', 'sessionId': sessionId, 'title': title.trim()});
  }

  void deleteSession(String sessionId) {
    _send({'type': 'session.delete', 'sessionId': sessionId});
  }

  void switchWorkspace(String workspaceId) {
    final sessionId = activeSession?.sessionId;
    if (sessionId == null) return;
    _send({'type': 'workspace.switch', 'sessionId': sessionId, 'workspaceId': workspaceId});
  }

  void setYolo(bool enabled) {
    final sessionId = activeSession?.sessionId;
    if (sessionId == null) return;
    _send({'type': 'session.mode.set', 'sessionId': sessionId, 'mode': enabled ? 'yolo' : 'safe'});
  }

  void runCommand(CodexCommandInfo command) {
    final sessionId = activeSession?.sessionId;
    final message = <String, dynamic>{'type': 'command.run', 'commandId': command.commandId};
    if (sessionId != null) {
      message['sessionId'] = sessionId;
    }
    _send(message);
  }

  void sendPrompt(String prompt) {
    final trimmed = prompt.trim();
    final sessionId = activeSession?.sessionId;
    if (trimmed.isEmpty || sessionId == null) return;
    final message = ChatMessage(id: _uuid.v4(), role: ChatRole.user, kind: AgentMessageKind.response, text: trimmed, createdAt: DateTime.now());
    messagesBySession.putIfAbsent(sessionId, () => []).add(message);
    notifyListeners();
    _send({'type': 'prompt.send', 'sessionId': sessionId, 'prompt': trimmed});
  }

  void cancelRun() {
    final sessionId = activeSession?.sessionId;
    final runId = activeSession?.activeRunId ?? activeRunId;
    if (sessionId == null || runId == null) return;
    _send({'type': 'run.cancel', 'sessionId': sessionId, 'runId': runId});
  }

  Future<void> disposeController() async {
    await _socket.close();
  }

  void _connect(String url, Map<String, dynamic> firstMessage) {
    final generation = ++_connectGeneration;
    phase = ConnectionPhase.connecting;
    statusText = 'Connecting to $url…';
    notifyListeners();

    unawaited(() async {
      try {
        await _socket.connect(
          url: url,
          onMessage: _handleMessage,
          onError: (error) {
            if (generation != _connectGeneration) return;
            phase = ConnectionPhase.failed;
            statusText = _friendlyBridgeError(error, url);
            _appendError(statusText);
            notifyListeners();
          },
          onDone: () {
            if (generation != _connectGeneration) return;
            if (phase == ConnectionPhase.connected) {
              phase = ConnectionPhase.idle;
              statusText = 'Bridge disconnected.';
              notifyListeners();
            }
          },
        );
        if (generation != _connectGeneration) return;
        statusText = 'Connected. Claiming pairing token…';
        notifyListeners();
        _socket.send(firstMessage);
      } catch (error) {
        if (generation != _connectGeneration) return;
        phase = ConnectionPhase.failed;
        statusText = _friendlyBridgeError(error, url);
        _appendError(statusText);
        notifyListeners();
      }
    }());
  }

  void _send(Map<String, dynamic> message) {
    try {
      _socket.send(message);
    } catch (error) {
      statusText = 'Not connected: $error';
      _appendError(statusText);
      notifyListeners();
    }
  }

  void _handleMessage(Map<String, dynamic> message) {
    switch (message['type'] as String?) {
      case 'status':
        statusText = message['detail'] as String? ?? message['status'] as String? ?? statusText;
        break;
      case 'pairing.accepted':
        _acceptPairing(message);
        break;
      case 'auth.accepted':
        phase = ConnectionPhase.connected;
        statusText = 'Connected to Codex LAN.';
        break;
      case 'session.list':
        _replaceSessions(message);
        break;
      case 'session.updated':
        _upsertSession(CodexSessionInfo.fromJson(Map<String, dynamic>.from(message['session'] as Map)));
        break;
      case 'session.deleted':
        _deleteLocalSession(message['sessionId'] as String? ?? '');
        break;
      case 'workspace.list':
        workspaces
          ..clear()
          ..addAll(((message['workspaces'] as List<dynamic>? ?? const [])).map((item) => WorkspaceInfo.fromJson(Map<String, dynamic>.from(item as Map))));
        break;
      case 'command.list':
        commands
          ..clear()
          ..addAll(((message['commands'] as List<dynamic>? ?? const [])).map((item) => CodexCommandInfo.fromJson(Map<String, dynamic>.from(item as Map))));
        break;
      case 'run.started':
        activeRunId = message['runId'] as String?;
        break;
      case 'run.completed':
        activeRunId = null;
        break;
      case 'message.started':
        _startAgentMessage(message);
        break;
      case 'message.delta':
        _appendAgentDelta(message);
        break;
      case 'message.completed':
        _completeAgentMessage(message);
        break;
      case 'output.delta':
        _handleLegacyOutput(message);
        break;
      case 'error':
        _appendError(message['message'] as String? ?? 'Unknown bridge error');
        statusText = message['message'] as String? ?? statusText;
        break;
    }
    notifyListeners();
  }

  Future<void> _acceptPairing(Map<String, dynamic> message) async {
    final url = _pendingUrl;
    final token = message['deviceToken'] as String?;
    final deviceId = message['deviceId'] as String?;
    phase = ConnectionPhase.connected;
    statusText = 'Paired and connected to Codex LAN.';
    if (url != null && token != null && deviceId != null) {
      credentials = BridgeCredentials(url: url, deviceToken: token, deviceId: deviceId);
      await _store.save(credentials!);
    }
  }

  void _replaceSessions(Map<String, dynamic> message) {
    sessions
      ..clear()
      ..addAll(((message['sessions'] as List<dynamic>? ?? const [])).map((item) => CodexSessionInfo.fromJson(Map<String, dynamic>.from(item as Map))));
    activeSessionId = message['activeSessionId'] as String? ?? activeSessionId ?? (sessions.isEmpty ? null : sessions.first.sessionId);
    for (final session in sessions) {
      messagesBySession.putIfAbsent(session.sessionId, () => []);
    }
  }

  void _upsertSession(CodexSessionInfo session) {
    final index = sessions.indexWhere((item) => item.sessionId == session.sessionId);
    if (index >= 0) {
      sessions[index] = session;
    } else {
      sessions.insert(0, session);
    }
    activeSessionId ??= session.sessionId;
    messagesBySession.putIfAbsent(session.sessionId, () => []);
  }

  void _deleteLocalSession(String sessionId) {
    sessions.removeWhere((session) => session.sessionId == sessionId);
    messagesBySession.remove(sessionId);
    if (activeSessionId == sessionId) {
      activeSessionId = sessions.isEmpty ? null : sessions.first.sessionId;
    }
  }

  void _startAgentMessage(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String? ?? activeSession?.sessionId;
    if (sessionId == null) return;
    final kind = kindFromWire(message['kind'] as String?);
    final id = message['messageId'] as String? ?? _uuid.v4();
    final text = kind == AgentMessageKind.thinking ? 'Thinking…' : '';
    messagesBySession.putIfAbsent(sessionId, () => []).add(
          ChatMessage(
            id: id,
            role: kind == AgentMessageKind.response ? ChatRole.assistant : ChatRole.system,
            kind: kind,
            text: text,
            title: message['title'] as String?,
            runId: message['runId'] as String?,
            createdAt: DateTime.now(),
            complete: false,
          ),
        );
  }

  void _appendAgentDelta(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String? ?? activeSession?.sessionId;
    if (sessionId == null) return;
    final messageId = message['messageId'] as String?;
    final text = message['text'] as String? ?? '';
    final list = messagesBySession.putIfAbsent(sessionId, () => []);
    final index = list.indexWhere((item) => item.id == messageId);
    if (index >= 0) {
      final current = list[index];
      final nextText = current.kind == AgentMessageKind.thinking && current.text == 'Thinking…' ? text : current.text + text;
      list[index] = current.copyWith(text: nextText);
    } else {
      list.add(ChatMessage(id: messageId ?? _uuid.v4(), role: ChatRole.system, kind: AgentMessageKind.system, text: text, createdAt: DateTime.now(), complete: false));
    }
  }

  void _completeAgentMessage(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String? ?? activeSession?.sessionId;
    if (sessionId == null) return;
    final messageId = message['messageId'] as String?;
    final list = messagesBySession[sessionId];
    if (list == null) return;
    final index = list.indexWhere((item) => item.id == messageId);
    if (index >= 0) {
      list[index] = list[index].copyWith(complete: true);
    }
  }

  void _handleLegacyOutput(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String? ?? activeSession?.sessionId;
    if (sessionId == null) return;
    final stream = message['stream'] as String? ?? 'system';
    if (stream == 'assistant') return;
    final text = message['text'] as String? ?? '';
    if (text.trim().isEmpty) return;
    messagesBySession.putIfAbsent(sessionId, () => []).add(ChatMessage(id: _uuid.v4(), role: ChatRole.system, kind: AgentMessageKind.system, title: stream, text: text, createdAt: DateTime.now()));
  }

  String _friendlyBridgeError(Object error, String url) {
    if (error is TimeoutException) {
      return 'Could not reach $url. Make sure the host bridge is still running, your phone is on the same Wi‑Fi/LAN, the QR is fresh, and port ${Uri.tryParse(url)?.port ?? ''} is not blocked by a firewall.';
    }
    final text = error.toString();
    if (text.contains('Connection refused') || text.contains('OS Error')) {
      return 'The host refused the connection at $url. Restart the bridge with --pair --insecure-ws-dev and scan the new QR.';
    }
    return 'Bridge error: $text';
  }

  void _appendError(String text) {
    final sessionId = activeSession?.sessionId;
    if (sessionId == null) return;
    messagesBySession.putIfAbsent(sessionId, () => []).add(ChatMessage(id: _uuid.v4(), role: ChatRole.system, kind: AgentMessageKind.error, title: 'Error', text: text, createdAt: DateTime.now()));
  }
}
