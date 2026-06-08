import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'protocol/bridge_messages.dart';
import 'services/bridge_socket_client.dart';
import 'services/download_saver.dart';
import 'services/pairing_parser.dart';
import 'services/secure_credentials_store.dart';

class AppController extends ChangeNotifier {
  AppController({
    BridgeSocketClient? socket,
    SecureCredentialsStore? store,
    FileDownloadSaver? downloadSaver,
    Duration autoReconnectDelay = const Duration(seconds: 3),
  }) : _socket = socket ?? BridgeSocketClient(),
       _store = store ?? SecureCredentialsStore(),
       _downloadSaver = downloadSaver ?? const PickerFileDownloadSaver(),
       _autoReconnectDelay = autoReconnectDelay;

  final BridgeSocketClient _socket;
  final SecureCredentialsStore _store;
  final FileDownloadSaver _downloadSaver;
  final Duration _autoReconnectDelay;
  final _uuid = const Uuid();

  ConnectionPhase phase = ConnectionPhase.idle;
  String statusText = 'Scan the host QR or login with a local/tunnel URL.';
  BridgeCredentials? credentials;
  HostInfo? hostInfo;
  String? activeSessionId;
  String? activeRunId;
  String? _pendingUrl;
  int _connectGeneration = 0;
  Timer? _reconnectTimer;
  final Map<String, String> _activeRunIdsBySession = {};
  final Set<String> _downloadsRequestedForSave = {};
  final Map<String, String> _lastGoalEventBySession = {};

  final List<CodexSessionInfo> sessions = [];
  final List<WorkspaceInfo> workspaces = [];
  final List<CodexCommandInfo> commands = [];
  final List<ExternalSessionInfo> externalSessions = [];
  final List<AppModelInfo> appModels = [];
  AppProviderCapabilitiesInfo? appCapabilities;
  final List<AppThreadInfo> appThreads = [];
  final List<AppSkillGroupInfo> appSkillGroups = [];
  final List<AppFsEntryInfo> appFileEntries = [];
  final List<WorkspaceFileInfo> appFileSearchResults = [];
  final List<FileOfferInfo> fileOffers = [];
  final List<DownloadedFileInfo> downloadedFiles = [];
  final Map<String, String> savedFilePaths = {};
  final List<WorkspaceFileInfo> fileSuggestions = [];
  final Map<String, List<ChatMessage>> messagesBySession = {};
  String fileSuggestionQuery = '';
  String appFilePath = '';
  AppFsFileInfo? appPreviewFile;
  String accentName = 'neutral';

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
  bool get isOffline => phase == ConnectionPhase.offline;
  bool get canShowChat =>
      phase == ConnectionPhase.connected ||
      phase == ConnectionPhase.offline ||
      (credentials != null &&
          (phase == ConnectionPhase.connecting ||
              phase == ConnectionPhase.failed));
  bool get isRunning {
    final session = activeSession;
    if (!isConnected || session == null) return false;
    return session.isRunning ||
        _activeRunIdForSession(session.sessionId) != null;
  }

  Future<void> loadSavedCredentials() async {
    credentials = await _store.load();
    if (credentials != null) {
      phase = ConnectionPhase.offline;
      statusText = 'Offline. Saved bridge found; reconnecting is available.';
      notifyListeners();
    }
  }

  Future<void> pair(String rawPayload, String deviceName) async {
    try {
      final payload = parsePairingPayload(rawPayload);
      if (payload.url.isEmpty || payload.pairingToken.isEmpty) {
        throw const FormatException('Pairing QR is missing url or token.');
      }
      final normalizedUrl = normalizeBridgeWebSocketUrl(payload.url);
      _pendingUrl = normalizedUrl;
      _connect(normalizedUrl, {
        'type': 'pairing.claim',
        'pairingToken': payload.pairingToken,
        'deviceName': deviceName.trim().isEmpty
            ? 'Codex Link Mobile'
            : deviceName.trim(),
      });
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
    final normalizedUrl = normalizeBridgeWebSocketUrl(saved.url);
    _pendingUrl = normalizedUrl;
    _connect(normalizedUrl, {
      'type': 'auth.resume',
      'deviceToken': saved.deviceToken,
    });
  }

  Future<void> loginWithPassword(
    String url,
    String password,
    String deviceName,
  ) async {
    final trimmedUrl = url.trim();
    final trimmedPassword = password.trim();
    if (trimmedUrl.isEmpty || trimmedPassword.isEmpty) {
      phase = ConnectionPhase.failed;
      statusText = 'Host URL and password are required.';
      notifyListeners();
      return;
    }
    final normalizedUrl = normalizeBridgeWebSocketUrl(trimmedUrl);
    _pendingUrl = normalizedUrl;
    _connect(normalizedUrl, {
      'type': 'auth.password',
      'password': trimmedPassword,
      'deviceName': deviceName.trim().isEmpty
          ? 'Codex Link Mobile'
          : deviceName.trim(),
    });
  }

  Future<void> forgetSaved() async {
    _reconnectTimer?.cancel();
    await _store.clear();
    credentials = null;
    phase = ConnectionPhase.idle;
    statusText = 'Saved bridge removed.';
    await _socket.close();
    notifyListeners();
  }

  Future<void> cancelConnection() async {
    _reconnectTimer?.cancel();
    _connectGeneration++;
    await _socket.close();
    phase = ConnectionPhase.idle;
    statusText = 'Connection cancelled.';
    notifyListeners();
  }

  void createSession() {
    _send({
      'type': 'session.create',
      'title': 'New session',
      'workspaceId': activeSession?.workspaceId ?? 'default',
    });
  }

  void selectSession(String sessionId) {
    activeSessionId = sessionId;
    _syncActiveRunId();
    clearFileSuggestions();
    _send({'type': 'session.start', 'sessionId': sessionId});
    _send({'type': 'workspace.list'});
    notifyListeners();
  }

  void renameSession(String sessionId, String title) {
    if (title.trim().isEmpty) return;
    _send({
      'type': 'session.rename',
      'sessionId': sessionId,
      'title': title.trim(),
    });
  }

  void deleteSession(String sessionId) {
    _send({'type': 'session.delete', 'sessionId': sessionId});
  }

  void switchWorkspace(String workspaceId) {
    final sessionId = activeSession?.sessionId;
    if (sessionId == null) return;
    clearFileSuggestions();
    final workspace = workspaces
        .where((item) => item.workspaceId == workspaceId)
        .firstOrNull;
    if (workspace != null) {
      final index = sessions.indexWhere((item) => item.sessionId == sessionId);
      if (index >= 0) {
        sessions[index] = sessions[index].copyWith(
          workspaceId: workspace.workspaceId,
          workdir: workspace.path,
        );
      }
      for (var i = 0; i < workspaces.length; i++) {
        workspaces[i] = workspaces[i].copyWith(
          active: workspaces[i].workspaceId == workspaceId,
        );
      }
      notifyListeners();
    }
    _send({
      'type': 'workspace.switch',
      'sessionId': sessionId,
      'workspaceId': workspaceId,
    });
  }

  void addWorkspacePath(String path, {bool create = false}) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    _send({
      'type': 'workspace.add',
      'path': trimmed,
      if (create) 'create': true,
      if (activeSession?.sessionId != null)
        'sessionId': activeSession!.sessionId,
    });
  }

  void refreshExternalSessions() {
    _send({'type': 'external.session.list'});
  }

  void refreshAppModels({bool includeHidden = false}) {
    _send({
      'type': 'app.model.list',
      if (activeSession?.sessionId != null)
        'sessionId': activeSession!.sessionId,
      if (includeHidden) 'includeHidden': true,
    });
  }

  void refreshAppThreads({String query = '', int limit = 40}) {
    _send({
      'type': 'app.thread.list',
      if (activeSession?.sessionId != null)
        'sessionId': activeSession!.sessionId,
      if (query.trim().isNotEmpty) 'query': query.trim(),
      'limit': limit,
    });
  }

  void importAppThread(AppThreadInfo thread) {
    if (thread.threadId.isEmpty) return;
    _send({'type': 'app.thread.import', 'threadId': thread.threadId});
  }

  void refreshAppSkills({bool forceReload = false}) {
    _send({
      'type': 'app.skill.list',
      if (activeSession?.sessionId != null)
        'sessionId': activeSession!.sessionId,
      if (forceReload) 'forceReload': true,
    });
  }

  void listAppDirectory([String path = '']) {
    final sessionId = activeSession?.sessionId;
    if (sessionId == null) return;
    _send({'type': 'app.fs.list', 'sessionId': sessionId, 'path': path});
  }

  void readAppFile(String path) {
    final sessionId = activeSession?.sessionId;
    if (sessionId == null || path.trim().isEmpty) return;
    _send({'type': 'app.fs.read', 'sessionId': sessionId, 'path': path});
  }

  void searchAppFiles(String query, {int limit = 40}) {
    final sessionId = activeSession?.sessionId;
    if (sessionId == null || query.trim().isEmpty) return;
    _send({
      'type': 'app.file.search',
      'sessionId': sessionId,
      'query': query.trim(),
      'limit': limit,
    });
  }

  void startReview({String? instructions}) {
    final sessionId = activeSession?.sessionId;
    if (sessionId == null) return;
    final trimmed = instructions?.trim();
    _send({
      'type': 'app.review.start',
      'sessionId': sessionId,
      'target': trimmed == null || trimmed.isEmpty
          ? 'uncommittedChanges'
          : 'custom',
      if (trimmed != null && trimmed.isNotEmpty) 'instructions': trimmed,
      'delivery': 'inline',
    });
  }

  void refreshWorkspaces() {
    _send({'type': 'workspace.list'});
  }

  void searchWorkspaceFiles(String query, {int limit = 40}) {
    final sessionId = activeSession?.sessionId;
    if (!isConnected || sessionId == null) return;
    final normalized = query.trim().replaceFirst(RegExp(r'^@+'), '');
    if (fileSuggestionQuery != normalized || fileSuggestions.isNotEmpty) {
      fileSuggestionQuery = normalized;
      fileSuggestions.clear();
      notifyListeners();
    }
    _send({
      'type': 'workspace.file.search',
      'sessionId': sessionId,
      'query': normalized,
      'limit': limit,
    });
  }

  void clearFileSuggestions() {
    if (fileSuggestionQuery.isEmpty && fileSuggestions.isEmpty) return;
    fileSuggestionQuery = '';
    fileSuggestions.clear();
    notifyListeners();
  }

  void importExternalSession(ExternalSessionInfo session) {
    if (session.externalSessionId.isEmpty) return;
    _send({
      'type': 'external.session.import',
      'externalSessionId': session.externalSessionId,
    });
  }

  void setYolo(bool enabled) {
    final sessionId = activeSession?.sessionId;
    if (sessionId == null) return;
    _send({
      'type': 'session.mode.set',
      'sessionId': sessionId,
      'mode': enabled ? 'yolo' : 'safe',
    });
  }

  void setSessionConfig({String? model, String? reasoningEffort}) {
    final sessionId = activeSession?.sessionId;
    if (sessionId == null) return;
    final trimmedModel = model?.trim();
    final message = <String, dynamic>{
      'type': 'session.config.set',
      'sessionId': sessionId,
    };
    if (trimmedModel != null) {
      message['model'] = trimmedModel;
    }
    if (reasoningEffort != null && reasoningEffort.isNotEmpty) {
      message['reasoningEffort'] = reasoningEffort;
    }
    _send(message);
  }

  void setGoal(String objective, {String status = 'active', int? tokenBudget}) {
    final sessionId = activeSession?.sessionId;
    final trimmed = objective.trim();
    if (sessionId == null || trimmed.isEmpty) return;
    final message = <String, dynamic>{
      'type': 'session.goal.set',
      'sessionId': sessionId,
      'objective': trimmed,
      'status': status,
    };
    if (tokenBudget != null) {
      message['tokenBudget'] = tokenBudget;
    }
    _send(message);
  }

  void getGoal() {
    final sessionId = activeSession?.sessionId;
    if (sessionId == null) return;
    _send({'type': 'session.goal.get', 'sessionId': sessionId});
  }

  void clearGoal() {
    final sessionId = activeSession?.sessionId;
    if (sessionId == null) return;
    _send({'type': 'session.goal.clear', 'sessionId': sessionId});
  }

  void setAccentName(String name) {
    const allowed = {'neutral', 'blue', 'green', 'violet', 'amber'};
    final normalized = allowed.contains(name) ? name : 'neutral';
    if (accentName == normalized) return;
    accentName = normalized;
    notifyListeners();
  }

  void runCommand(CodexCommandInfo command) {
    switch (command.commandId) {
      case 'codex.stop':
        cancelRun();
        return;
      case 'codex.new':
        createSession();
        return;
      case 'codex.sessions':
      case 'codex.model':
        statusText = 'Open ${command.title} from the chat controls.';
        notifyListeners();
        return;
    }
    final sessionId = activeSession?.sessionId;
    final message = <String, dynamic>{
      'type': 'command.run',
      'commandId': command.commandId,
    };
    if (sessionId != null) {
      message['sessionId'] = sessionId;
    }
    _send(message);
  }

  void sendPrompt(
    String prompt, {
    List<PromptAttachmentInfo> attachments = const [],
  }) {
    final trimmed = prompt.trim();
    final sessionId = activeSession?.sessionId;
    if ((trimmed.isEmpty && attachments.isEmpty) || sessionId == null) return;
    final requestedFilePath = attachments.isEmpty
        ? _requestedFilePathFromPrompt(trimmed)
        : null;
    if (requestedFilePath != null) {
      clearFileSuggestions();
      messagesBySession
          .putIfAbsent(sessionId, () => [])
          .add(
            ChatMessage(
              id: _uuid.v4(),
              role: ChatRole.system,
              kind: AgentMessageKind.executing,
              title: 'Requesting file',
              text: requestedFilePath,
              createdAt: DateTime.now(),
              complete: false,
            ),
          );
      notifyListeners();
      _send({
        'type': 'file.offer.request',
        'sessionId': sessionId,
        'path': requestedFilePath,
      });
      return;
    }
    if (attachments.isEmpty && _handleInlineSlashCommand(trimmed, sessionId)) {
      return;
    }
    final displayText = trimmed.isEmpty ? 'Uploaded attachments' : trimmed;
    clearFileSuggestions();
    final message = ChatMessage(
      id: _uuid.v4(),
      role: ChatRole.user,
      kind: AgentMessageKind.response,
      text: displayText,
      createdAt: DateTime.now(),
    );
    messagesBySession.putIfAbsent(sessionId, () => []).add(message);
    if (attachments.isNotEmpty) {
      messagesBySession
          .putIfAbsent(sessionId, () => [])
          .add(
            ChatMessage(
              id: _uuid.v4(),
              role: ChatRole.system,
              kind: AgentMessageKind.files,
              title: 'Attachments queued',
              text: attachments
                  .map((attachment) => 'added ${attachment.name}')
                  .join('\n'),
              createdAt: DateTime.now(),
            ),
          );
    }
    notifyListeners();
    _send({
      'type': 'prompt.send',
      'sessionId': sessionId,
      'prompt': displayText,
      if (attachments.isNotEmpty)
        'attachments': attachments
            .map((attachment) => attachment.toJson())
            .toList(growable: false),
    });
  }

  void cancelRun() {
    final sessionId = activeSession?.sessionId;
    final runId = _activeRunIdForSession(sessionId);
    if (sessionId == null || runId == null) return;
    _send({'type': 'run.cancel', 'sessionId': sessionId, 'runId': runId});
  }

  void requestFileDownload(FileOfferInfo offer, {bool saveToDevice = true}) {
    if (offer.fileId.isEmpty) return;
    if (saveToDevice) {
      _downloadsRequestedForSave.add(offer.fileId);
    }
    _send({'type': 'file.request', 'fileId': offer.fileId});
  }

  void decideApproval(String approvalId, String decision) {
    final sessionId = activeSession?.sessionId;
    if (sessionId == null || approvalId.isEmpty) return;
    _send({
      'type': 'approval.decision',
      'sessionId': sessionId,
      'approvalId': approvalId,
      'decision': decision,
    });
  }

  Future<void> disposeController() async {
    _reconnectTimer?.cancel();
    await _socket.close();
  }

  @visibleForTesting
  void handleBridgeMessageForTest(Map<String, dynamic> message) {
    _handleMessage(message);
  }

  void _connect(String url, Map<String, dynamic> firstMessage) {
    final generation = ++_connectGeneration;
    _reconnectTimer?.cancel();
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
            if (phase == ConnectionPhase.connected) {
              _markOfflineAndScheduleReconnect(generation);
              return;
            }
            phase = ConnectionPhase.failed;
            statusText = _friendlyBridgeError(error, url);
            _appendError(statusText);
            _scheduleReconnect();
            notifyListeners();
          },
          onDone: () {
            if (generation != _connectGeneration) return;
            if (phase == ConnectionPhase.connected) {
              _markOfflineAndScheduleReconnect(generation);
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
        _scheduleReconnect();
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
        statusText =
            message['detail'] as String? ??
            message['status'] as String? ??
            statusText;
        _applyStatusMessage(message);
        break;
      case 'host.info':
        hostInfo = HostInfo.fromJson(message);
        break;
      case 'pairing.accepted':
        _acceptPairing(message);
        break;
      case 'auth.accepted':
        _acceptAuth(message);
        break;
      case 'session.list':
        _replaceSessions(message);
        break;
      case 'session.updated':
        _upsertSession(
          CodexSessionInfo.fromJson(
            Map<String, dynamic>.from(message['session'] as Map),
          ),
        );
        break;
      case 'session.goal.updated':
        _applyGoalUpdated(message);
        break;
      case 'session.goal.cleared':
        _applyGoalCleared(message);
        break;
      case 'session.deleted':
        _deleteLocalSession(message['sessionId'] as String? ?? '');
        break;
      case 'workspace.list':
        workspaces
          ..clear()
          ..addAll(
            ((message['workspaces'] as List<dynamic>? ?? const [])).map(
              (item) => WorkspaceInfo.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            ),
          );
        break;
      case 'workspace.file.search.results':
        _replaceFileSuggestions(message);
        break;
      case 'command.list':
        commands
          ..clear()
          ..addAll(
            ((message['commands'] as List<dynamic>? ?? const [])).map(
              (item) => CodexCommandInfo.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            ),
          );
        break;
      case 'external.session.list':
        externalSessions
          ..clear()
          ..addAll(
            ((message['sessions'] as List<dynamic>? ?? const [])).map(
              (item) => ExternalSessionInfo.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            ),
          );
        break;
      case 'app.model.list':
        appModels
          ..clear()
          ..addAll(
            ((message['models'] as List<dynamic>? ?? const [])).map(
              (item) =>
                  AppModelInfo.fromJson(Map<String, dynamic>.from(item as Map)),
            ),
          );
        if (message['capabilities'] is Map) {
          appCapabilities = AppProviderCapabilitiesInfo.fromJson(
            Map<String, dynamic>.from(message['capabilities'] as Map),
          );
        }
        break;
      case 'app.thread.list':
        appThreads
          ..clear()
          ..addAll(
            ((message['threads'] as List<dynamic>? ?? const [])).map(
              (item) => AppThreadInfo.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            ),
          );
        break;
      case 'app.skill.list':
        appSkillGroups
          ..clear()
          ..addAll(
            ((message['groups'] as List<dynamic>? ?? const [])).map(
              (item) => AppSkillGroupInfo.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            ),
          );
        break;
      case 'app.fs.list':
        appFilePath = message['path'] as String? ?? '';
        appFileEntries
          ..clear()
          ..addAll(
            ((message['entries'] as List<dynamic>? ?? const [])).map(
              (item) => AppFsEntryInfo.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            ),
          );
        break;
      case 'app.fs.file':
        if (message['file'] is Map) {
          appPreviewFile = AppFsFileInfo.fromJson(
            Map<String, dynamic>.from(message['file'] as Map),
          );
        }
        break;
      case 'app.file.search.results':
        appFileSearchResults
          ..clear()
          ..addAll(
            ((message['files'] as List<dynamic>? ?? const [])).map(
              (item) => WorkspaceFileInfo.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            ),
          );
        break;
      case 'app.review.started':
        _appendReviewStarted(message);
        break;
      case 'run.started':
        _markRunStarted(message);
        break;
      case 'run.completed':
        _markRunCompleted(message);
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
      case 'message.history':
        _replaceMessageHistory(message);
        break;
      case 'output.delta':
        _handleLegacyOutput(message);
        break;
      case 'diff.available':
        _appendFileChangeEvent(message);
        break;
      case 'approval.requested':
        _appendApprovalRequest(message);
        break;
      case 'file.offer':
        _appendFileOfferEvent(message);
        break;
      case 'file.download':
        _appendFileDownloadEvent(message);
        break;
      case 'error':
        _appendError(message['message'] as String? ?? 'Unknown bridge error');
        statusText = message['message'] as String? ?? statusText;
        break;
    }
    notifyListeners();
  }

  Future<void> _acceptPairing(Map<String, dynamic> message) async {
    _reconnectTimer?.cancel();
    final url = _pendingUrl;
    final token = message['deviceToken'] as String?;
    final deviceId = message['deviceId'] as String?;
    phase = ConnectionPhase.connected;
    statusText = 'Paired and connected to Codex Link.';
    if (url != null && token != null && deviceId != null) {
      credentials = BridgeCredentials(
        url: url,
        deviceToken: token,
        deviceId: deviceId,
      );
      await _store.save(credentials!);
    }
  }

  Future<void> _acceptAuth(Map<String, dynamic> message) async {
    _reconnectTimer?.cancel();
    final url = _pendingUrl ?? credentials?.url;
    final token = message['deviceToken'] as String?;
    final deviceId = message['deviceId'] as String?;
    phase = ConnectionPhase.connected;
    statusText = 'Connected to Codex Link.';
    if (url != null && token != null && deviceId != null) {
      credentials = BridgeCredentials(
        url: url,
        deviceToken: token,
        deviceId: deviceId,
      );
      await _store.save(credentials!);
    }
  }

  void _replaceSessions(Map<String, dynamic> message) {
    sessions
      ..clear()
      ..addAll(
        ((message['sessions'] as List<dynamic>? ?? const [])).map(
          (item) =>
              CodexSessionInfo.fromJson(Map<String, dynamic>.from(item as Map)),
        ),
      );
    activeSessionId =
        message['activeSessionId'] as String? ??
        activeSessionId ??
        (sessions.isEmpty ? null : sessions.first.sessionId);
    for (final session in sessions) {
      messagesBySession.putIfAbsent(session.sessionId, () => []);
      if (session.activeRunId case final runId?) {
        _activeRunIdsBySession[session.sessionId] = runId;
      } else if (!session.isRunning) {
        _activeRunIdsBySession.remove(session.sessionId);
      }
    }
    _activeRunIdsBySession.removeWhere(
      (sessionId, _) =>
          !sessions.any((session) => session.sessionId == sessionId),
    );
    _syncActiveRunId();
  }

  void _replaceMessageHistory(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String?;
    if (sessionId == null || sessionId.isEmpty) return;
    messagesBySession[sessionId] =
        ((message['messages'] as List<dynamic>? ?? const []))
            .map(
              (item) => ChatMessage.fromHistory(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .where(
              (item) => item.id.isNotEmpty && !_isReplayThinkingNoise(item),
            )
            .toList();
  }

  void _replaceFileSuggestions(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String?;
    if (sessionId == null || sessionId != activeSession?.sessionId) return;
    fileSuggestionQuery = message['query'] as String? ?? fileSuggestionQuery;
    fileSuggestions
      ..clear()
      ..addAll(
        ((message['files'] as List<dynamic>? ?? const [])).map(
          (item) => WorkspaceFileInfo.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        ),
      );
  }

  void _upsertSession(CodexSessionInfo session) {
    final index = sessions.indexWhere(
      (item) => item.sessionId == session.sessionId,
    );
    if (index >= 0) {
      sessions[index] = session;
    } else {
      sessions.insert(0, session);
    }
    if (session.activeRunId case final runId?) {
      _activeRunIdsBySession[session.sessionId] = runId;
    } else if (!session.isRunning) {
      _activeRunIdsBySession.remove(session.sessionId);
    }
    activeSessionId ??= session.sessionId;
    _syncActiveRunId();
    messagesBySession.putIfAbsent(session.sessionId, () => []);
  }

  void _applyGoalUpdated(Map<String, dynamic> message) {
    final sessionId = _sessionIdForMessage(message);
    if (sessionId == null) return;
    final goalMap = message['goal'];
    if (goalMap is! Map) return;
    final goal = CodexGoalInfo.fromJson(Map<String, dynamic>.from(goalMap));
    final index = sessions.indexWhere((item) => item.sessionId == sessionId);
    if (index >= 0) {
      sessions[index] = sessions[index].copyWith(goal: goal);
    }
    if (!_shouldAnnounceGoalStatus(goal.status)) return;
    final signature =
        'updated:${goal.status}:${goal.objective}:${goal.tokenBudget}';
    if (_lastGoalEventBySession[sessionId] == signature) return;
    _lastGoalEventBySession[sessionId] = signature;
    final title = goal.status == 'complete'
        ? 'Goal complete'
        : goal.status == 'blocked'
        ? 'Goal blocked'
        : 'Goal ${goal.status}';
    final details = [
      goal.objective.trim().isEmpty ? 'No objective set.' : goal.objective,
      if (goal.tokenBudget != null) 'budget ${goal.tokenBudget}',
      if (goal.tokensUsed > 0) 'used ${goal.tokensUsed}',
    ].join('\n');
    messagesBySession
        .putIfAbsent(sessionId, () => [])
        .add(
          ChatMessage(
            id: _uuid.v4(),
            role: ChatRole.system,
            kind: AgentMessageKind.system,
            title: title,
            text: details,
            createdAt: DateTime.now(),
          ),
        );
  }

  void _applyGoalCleared(Map<String, dynamic> message) {
    final sessionId = _sessionIdForMessage(message);
    if (sessionId == null) return;
    final index = sessions.indexWhere((item) => item.sessionId == sessionId);
    if (index >= 0) {
      sessions[index] = sessions[index].copyWith(clearGoal: true);
    }
    const signature = 'cleared';
    if (_lastGoalEventBySession[sessionId] == signature) return;
    _lastGoalEventBySession[sessionId] = signature;
    messagesBySession
        .putIfAbsent(sessionId, () => [])
        .add(
          ChatMessage(
            id: _uuid.v4(),
            role: ChatRole.system,
            kind: AgentMessageKind.system,
            title: 'Goal cleared',
            text: 'No active goal for this session.',
            createdAt: DateTime.now(),
          ),
        );
  }

  void _deleteLocalSession(String sessionId) {
    sessions.removeWhere((session) => session.sessionId == sessionId);
    messagesBySession.remove(sessionId);
    _activeRunIdsBySession.remove(sessionId);
    _lastGoalEventBySession.remove(sessionId);
    if (activeSessionId == sessionId) {
      activeSessionId = sessions.isEmpty ? null : sessions.first.sessionId;
    }
    _syncActiveRunId();
  }

  void _startAgentMessage(Map<String, dynamic> message) {
    final sessionId = _sessionIdForMessage(message);
    if (sessionId == null) return;
    final kind = kindFromWire(message['kind'] as String?);
    final id = message['messageId'] as String? ?? _uuid.v4();
    final text = kind == AgentMessageKind.thinking ? 'Thinking…' : '';
    messagesBySession
        .putIfAbsent(sessionId, () => [])
        .add(
          ChatMessage(
            id: id,
            role: kind == AgentMessageKind.response
                ? ChatRole.assistant
                : ChatRole.system,
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
    final sessionId = _sessionIdForMessage(message);
    if (sessionId == null) return;
    final messageId = message['messageId'] as String?;
    final text = message['text'] as String? ?? '';
    final list = messagesBySession.putIfAbsent(sessionId, () => []);
    final index = list.indexWhere((item) => item.id == messageId);
    if (index >= 0) {
      final current = list[index];
      final nextText =
          current.kind == AgentMessageKind.thinking &&
              current.text == 'Thinking…'
          ? text
          : current.text + text;
      list[index] = current.copyWith(text: nextText);
    } else {
      list.add(
        ChatMessage(
          id: messageId ?? _uuid.v4(),
          role: ChatRole.system,
          kind: AgentMessageKind.system,
          text: text,
          createdAt: DateTime.now(),
          complete: false,
        ),
      );
    }
  }

  void _completeAgentMessage(Map<String, dynamic> message) {
    final sessionId = _sessionIdForMessage(message);
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
    final sessionId = _sessionIdForMessage(message);
    if (sessionId == null) return;
    final stream = message['stream'] as String? ?? 'system';
    if (stream == 'assistant') return;
    final text = message['text'] as String? ?? '';
    if (text.trim().isEmpty) return;
    messagesBySession
        .putIfAbsent(sessionId, () => [])
        .add(
          ChatMessage(
            id: _uuid.v4(),
            role: ChatRole.system,
            kind: AgentMessageKind.system,
            title: stream,
            text: text,
            createdAt: DateTime.now(),
          ),
        );
  }

  void _appendReviewStarted(Map<String, dynamic> message) {
    final sessionId = _sessionIdForMessage(message);
    if (sessionId == null) return;
    messagesBySession
        .putIfAbsent(sessionId, () => [])
        .add(
          ChatMessage(
            id: 'review-${message['runId'] ?? _uuid.v4()}',
            role: ChatRole.system,
            kind: AgentMessageKind.system,
            title: 'Review started',
            text:
                'run ${message['runId'] ?? ''}\nthread ${message['reviewThreadId'] ?? ''}',
            createdAt: DateTime.now(),
          ),
        );
  }

  void _appendApprovalRequest(Map<String, dynamic> message) {
    final sessionId = _sessionIdForMessage(message);
    final approvalId = message['approvalId'] as String?;
    if (sessionId == null || approvalId == null || approvalId.isEmpty) return;
    messagesBySession
        .putIfAbsent(sessionId, () => [])
        .add(
          ChatMessage(
            id: 'approval-$approvalId',
            role: ChatRole.system,
            kind: AgentMessageKind.approval,
            title: message['title'] as String? ?? 'Approval needed',
            text: [
              'approvalId $approvalId',
              'risk ${message['riskLevel'] as String? ?? 'medium'}',
              message['body'] as String? ?? '',
            ].join('\n'),
            createdAt: DateTime.now(),
            complete: false,
          ),
        );
  }

  void _appendFileChangeEvent(Map<String, dynamic> message) {
    final sessionId = _sessionIdForMessage(message);
    if (sessionId == null) return;
    final files = message['files'] as List<dynamic>? ?? const [];
    final lines = files
        .whereType<Map>()
        .expand((item) {
          final status = item['status'] as String? ?? 'modified';
          final path = item['path'] as String? ?? '';
          if (path.trim().isEmpty) return const <String>[];
          final patch = item['patch'] as String?;
          return [
            '$status $path',
            if (patch != null && patch.trim().isNotEmpty) ...patch.split('\n'),
          ];
        })
        .join('\n');
    if (lines.isEmpty) return;
    messagesBySession
        .putIfAbsent(sessionId, () => [])
        .add(
          ChatMessage(
            id: _uuid.v4(),
            role: ChatRole.system,
            kind: AgentMessageKind.files,
            title: 'Files changed',
            text: lines,
            createdAt: DateTime.now(),
          ),
        );
  }

  void _appendFileOfferEvent(Map<String, dynamic> message) {
    final offer = FileOfferInfo.fromJson(message);
    if (offer.fileId.isEmpty) return;
    fileOffers.add(offer);
    final sessionId = offer.sessionId ?? activeSession?.sessionId;
    if (sessionId == null) return;
    final list = messagesBySession.putIfAbsent(sessionId, () => []);
    list.removeWhere(
      (message) =>
          message.kind == AgentMessageKind.executing &&
          message.title == 'Requesting file' &&
          message.text.trim() == offer.path,
    );
    list.add(
      ChatMessage(
        id: 'file-offer-${offer.fileId}',
        role: ChatRole.system,
        kind: AgentMessageKind.files,
        title: 'File available',
        text:
            '${offer.reason} ${offer.path}\nsize ${offer.sizeBytes}\nfileId ${offer.fileId}',
        createdAt: DateTime.now(),
      ),
    );
    if (_isImageOffer(offer)) {
      requestFileDownload(offer, saveToDevice: false);
    }
  }

  void _appendFileDownloadEvent(Map<String, dynamic> message) {
    final file = DownloadedFileInfo.fromJson(message);
    if (file.fileId.isEmpty) return;
    downloadedFiles.add(file);
    final matchingOffer = fileOffers
        .where((offer) => offer.fileId == file.fileId)
        .firstOrNull;
    if (_isImageDownload(file, matchingOffer)) {
      if (_downloadsRequestedForSave.remove(file.fileId)) {
        _saveDownloadedFile(file, matchingOffer);
      }
      notifyListeners();
      return;
    }
    final sessionId = matchingOffer?.sessionId ?? activeSession?.sessionId;
    if (sessionId == null) return;
    messagesBySession
        .putIfAbsent(sessionId, () => [])
        .add(
          ChatMessage(
            id: 'file-download-${file.fileId}',
            role: ChatRole.system,
            kind: AgentMessageKind.files,
            title: 'File downloaded',
            text:
                'downloaded ${file.name}\nsize ${file.sizeBytes}\nfileId ${file.fileId}',
            createdAt: DateTime.now(),
          ),
        );
    if (_downloadsRequestedForSave.remove(file.fileId)) {
      _saveDownloadedFile(file, matchingOffer);
    }
  }

  void _saveDownloadedFile(DownloadedFileInfo file, FileOfferInfo? offer) {
    unawaited(() async {
      try {
        final path = await _downloadSaver.save(file);
        if (path == null || path.trim().isEmpty) return;
        savedFilePaths[file.fileId] = path;
        final sessionId = offer?.sessionId ?? activeSession?.sessionId;
        if (sessionId != null) {
          messagesBySession
              .putIfAbsent(sessionId, () => [])
              .add(
                ChatMessage(
                  id: 'file-saved-${file.fileId}',
                  role: ChatRole.system,
                  kind: AgentMessageKind.files,
                  title: 'File saved',
                  text:
                      'downloaded ${file.name}\nsaved $path\nfileId ${file.fileId}',
                  createdAt: DateTime.now(),
                ),
              );
        }
        notifyListeners();
      } catch (error) {
        _appendError('Could not save ${file.name}: $error');
        notifyListeners();
      }
    }());
  }

  void _markOfflineAndScheduleReconnect(int generation) {
    if (generation != _connectGeneration) return;
    phase = ConnectionPhase.offline;
    activeRunId = null;
    statusText = 'Offline. Showing cached chat while reconnecting…';
    _scheduleReconnect();
    notifyListeners();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive == true) return;
    if (credentials == null) return;
    _reconnectTimer = Timer(_autoReconnectDelay, () {
      if (phase == ConnectionPhase.connected || credentials == null) return;
      unawaited(reconnect());
    });
  }

  String _friendlyBridgeError(Object error, String url) {
    if (error is TimeoutException) {
      return 'Could not reach $url. Make sure the host bridge is running, the LAN or tunnel URL is reachable, the QR is fresh, and the port or tunnel is not blocked.';
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
    messagesBySession
        .putIfAbsent(sessionId, () => [])
        .add(
          ChatMessage(
            id: _uuid.v4(),
            role: ChatRole.system,
            kind: AgentMessageKind.error,
            title: 'Error',
            text: text,
            createdAt: DateTime.now(),
          ),
        );
  }

  void _markRunStarted(Map<String, dynamic> message) {
    final sessionId = _sessionIdForMessage(message);
    final runId = message['runId'] as String?;
    if (sessionId == null || runId == null || runId.isEmpty) return;
    _activeRunIdsBySession[sessionId] = runId;
    _updateSessionRunState(
      sessionId,
      activeRunId: runId,
      lastStatus: 'running',
    );
    _syncActiveRunId();
  }

  void _markRunCompleted(Map<String, dynamic> message) {
    final sessionId = _sessionIdForMessage(message);
    if (sessionId == null) return;
    _clearSessionRun(sessionId, message['runId'] as String?);
  }

  void _applyStatusMessage(Map<String, dynamic> message) {
    final status = message['status'] as String?;
    if (status == null) return;
    final sessionId = _sessionIdForMessage(message);
    if (sessionId == null) return;
    final runId = message['runId'] as String?;
    if ((status == 'running' || status == 'cancelling') &&
        runId != null &&
        runId.isNotEmpty) {
      _activeRunIdsBySession[sessionId] = runId;
      _updateSessionRunState(sessionId, activeRunId: runId, lastStatus: status);
      _syncActiveRunId();
      return;
    }
    if (status == 'completed' || status == 'failed' || status == 'cancelled') {
      _clearSessionRun(sessionId, runId, lastStatus: status);
    }
  }

  void _clearSessionRun(String sessionId, String? runId, {String? lastStatus}) {
    final currentRunId = _activeRunIdsBySession[sessionId];
    if (runId == null ||
        runId.isEmpty ||
        currentRunId == null ||
        currentRunId == runId) {
      _activeRunIdsBySession.remove(sessionId);
      _updateSessionRunState(
        sessionId,
        clearActiveRunId: true,
        lastStatus: lastStatus,
      );
      _syncActiveRunId();
    }
  }

  void _updateSessionRunState(
    String sessionId, {
    String? activeRunId,
    bool clearActiveRunId = false,
    String? lastStatus,
  }) {
    final index = sessions.indexWhere(
      (session) => session.sessionId == sessionId,
    );
    if (index < 0) return;
    sessions[index] = sessions[index].copyWith(
      activeRunId: activeRunId,
      clearActiveRunId: clearActiveRunId,
      lastStatus: lastStatus,
    );
  }

  String? _sessionIdForMessage(Map<String, dynamic> message) {
    final explicitSessionId = message['sessionId'] as String?;
    if (explicitSessionId != null && explicitSessionId.isNotEmpty) {
      return explicitSessionId;
    }
    final runId = message['runId'] as String?;
    if (runId != null && runId.isNotEmpty) {
      for (final entry in _activeRunIdsBySession.entries) {
        if (entry.value == runId) return entry.key;
      }
      for (final session in sessions) {
        if (session.activeRunId == runId) return session.sessionId;
      }
    }
    return activeSession?.sessionId;
  }

  String? _activeRunIdForSession(String? sessionId) {
    if (sessionId == null) return null;
    return _activeRunIdsBySession[sessionId] ??
        sessions
            .where((session) => session.sessionId == sessionId)
            .firstOrNull
            ?.activeRunId;
  }

  void _syncActiveRunId() {
    activeRunId = _activeRunIdForSession(activeSessionId);
  }

  bool _handleInlineSlashCommand(String prompt, String sessionId) {
    final goalMatch = RegExp(
      r'^/goal(?:\s+(.+))?$',
      caseSensitive: false,
    ).firstMatch(prompt.trim());
    if (goalMatch == null) return false;

    clearFileSuggestions();
    messagesBySession
        .putIfAbsent(sessionId, () => [])
        .add(
          ChatMessage(
            id: _uuid.v4(),
            role: ChatRole.user,
            kind: AgentMessageKind.response,
            text: prompt,
            createdAt: DateTime.now(),
          ),
        );
    final value = goalMatch.group(1)?.trim() ?? '';
    if (value.isEmpty) {
      _send({'type': 'session.goal.get', 'sessionId': sessionId});
      notifyListeners();
      return true;
    }
    if (RegExp(
      r'^(clear|reset|remove|none)$',
      caseSensitive: false,
    ).hasMatch(value)) {
      _send({'type': 'session.goal.clear', 'sessionId': sessionId});
      notifyListeners();
      return true;
    }

    final status = _goalStatusFromCommandValue(value);
    if (status != null) {
      _send({
        'type': 'session.goal.set',
        'sessionId': sessionId,
        'status': status,
      });
      notifyListeners();
      return true;
    }

    _send({
      'type': 'session.goal.set',
      'sessionId': sessionId,
      'objective': value,
      'status': 'active',
    });
    notifyListeners();
    return true;
  }
}

bool _shouldAnnounceGoalStatus(String status) {
  return status == 'complete' ||
      status == 'blocked' ||
      status == 'usageLimited' ||
      status == 'budgetLimited';
}

bool _isImageOffer(FileOfferInfo offer) {
  final mimeType = offer.mimeType?.toLowerCase();
  return mimeType?.startsWith('image/') == true || _looksLikeImage(offer.path);
}

bool _isImageDownload(DownloadedFileInfo file, FileOfferInfo? offer) {
  final mimeType =
      file.mimeType?.toLowerCase() ?? offer?.mimeType?.toLowerCase();
  return mimeType?.startsWith('image/') == true ||
      _looksLikeImage(file.name) ||
      (offer != null && _looksLikeImage(offer.path));
}

bool _looksLikeImage(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.gif');
}

bool _isReplayThinkingNoise(ChatMessage message) {
  final text = message.text.trim().replaceAll('.', '').replaceAll('…', '');
  return message.role == ChatRole.system &&
      (message.kind == AgentMessageKind.system ||
          message.kind == AgentMessageKind.thinking) &&
      text.toLowerCase() == 'thinking';
}

String? _requestedFilePathFromPrompt(String prompt) {
  final match = RegExp(
    r'^(?:/send|/download|send\s+file|send\s+me\s+file)\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(prompt.trim());
  final rawPath = match?.group(1)?.trim();
  if (rawPath == null || rawPath.isEmpty) return null;
  var normalized = rawPath;
  if (normalized.startsWith('@')) {
    normalized = normalized.substring(1).trim();
  }
  if ((rawPath.startsWith('"') && rawPath.endsWith('"')) ||
      (rawPath.startsWith("'") && rawPath.endsWith("'"))) {
    normalized = rawPath.substring(1, rawPath.length - 1).trim();
  }
  if (normalized.startsWith('@')) {
    normalized = normalized.substring(1).trim();
  }
  if ((normalized.startsWith('"') && normalized.endsWith('"')) ||
      (normalized.startsWith("'") && normalized.endsWith("'"))) {
    normalized = normalized.substring(1, normalized.length - 1).trim();
  }
  return normalized;
}

String? _goalStatusFromCommandValue(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'pause' || 'paused' => 'paused',
    'resume' || 'active' || 'start' => 'active',
    'block' || 'blocked' => 'blocked',
    'complete' || 'completed' || 'done' => 'complete',
    _ => null,
  };
}
