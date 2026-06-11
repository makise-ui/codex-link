import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'protocol/bridge_messages.dart';
import 'services/app_notifier.dart';
import 'services/bridge_socket_client.dart';
import 'services/download_saver.dart';
import 'services/pairing_parser.dart';
import 'services/secure_credentials_store.dart';
import 'services/update_service.dart';
import 'services/voice_transcription_service.dart';

class AppNotice {
  const AppNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.payload,
  });

  final String id;
  final String title;
  final String body;
  final String? payload;
  final DateTime createdAt;
}

enum AppNotificationCategory { plan, task, goal, update, remote, error, other }

class AppController extends ChangeNotifier {
  AppController({
    BridgeSocketClient? socket,
    SecureCredentialsStore? store,
    FileDownloadSaver? downloadSaver,
    AppNotifier? notifier,
    AppUpdateService? updateService,
    VoiceTranscriptionService? voiceTranscriptionService,
    Duration autoReconnectDelay = const Duration(seconds: 3),
  }) : _socket = socket ?? BridgeSocketClient(),
       _store = store ?? SecureCredentialsStore(),
       _downloadSaver = downloadSaver ?? const PickerFileDownloadSaver(),
       _notifier = notifier ?? LocalAppNotifier(),
       _updateService = updateService ?? GitHubAppUpdateService(),
       _voiceTranscriptionService =
           voiceTranscriptionService ?? SpeechToTextVoiceTranscriptionService(),
       _autoReconnectDelay = autoReconnectDelay;

  final BridgeSocketClient _socket;
  final SecureCredentialsStore _store;
  final FileDownloadSaver _downloadSaver;
  final AppNotifier _notifier;
  final AppUpdateService _updateService;
  final VoiceTranscriptionService _voiceTranscriptionService;
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
  final Map<String, CodexPlanInfo> _plansBySession = {};
  final Map<String, List<AppSubagentInfo>> _subagentsBySession = {};
  final Set<String> _runNoticeSignatures = {};
  bool _isAppForeground = true;
  String? latestErrorText;
  AppNotice? latestNotice;
  int inAppNoticeDurationSeconds = 6;
  final Set<AppNotificationCategory> _enabledNotificationCategories = {
    AppNotificationCategory.plan,
    AppNotificationCategory.task,
    AppNotificationCategory.goal,
    AppNotificationCategory.update,
    AppNotificationCategory.remote,
    AppNotificationCategory.error,
    AppNotificationCategory.other,
  };
  UpdateCheckStatus updateStatus = UpdateCheckStatus.idle;
  AppUpdateInfo? availableUpdate;
  String? updateErrorText;

  final List<CodexSessionInfo> sessions = [];
  final List<WorkspaceInfo> workspaces = [];
  final List<CodexCommandInfo> commands = [];
  final List<ExternalSessionInfo> externalSessions = [];
  final List<AppModelInfo> appModels = [];
  AppProviderCapabilitiesInfo? appCapabilities;
  CodexAccountInfo? codexAccount;
  CodexAccountLoginFlow? activeCodexLogin;
  bool codexAccountBusy = false;
  String? codexAccountErrorText;
  bool appServerActionsBusy = false;
  String? appServerActionsErrorText;
  bool envSecretsBusy = false;
  String? envSecretsStatusText;
  final List<AppThreadInfo> appThreads = [];
  final List<AppSkillGroupInfo> appSkillGroups = [];
  final List<AppFsEntryInfo> appFileEntries = [];
  final List<WorkspaceFileInfo> appFileSearchResults = [];
  final List<AppPluginMarketplaceInfo> appPluginMarketplaces = [];
  AppPluginDetailInfo? appSelectedPlugin;
  AppPluginInstallResultInfo? appPluginInstallResult;
  final List<AppMcpServerInfo> appMcpServers = [];
  AppMcpOauthLoginInfo? appMcpOauthLogin;
  AppRemoteStatusInfo? appRemoteStatus;
  AppRemotePairingInfo? appRemotePairing;
  HostUpdateStatusInfo? hostUpdateStatus;
  HostUpdateResultInfo? hostUpdateResult;
  final List<HostUpdateProgressInfo> hostUpdateProgress = [];
  bool hostUpdateBusy = false;
  String? hostUpdateErrorText;
  final List<AppRateLimitInfo> appRateLimits = [];
  final List<ShellCommandResultInfo> shellHistory = [];
  bool appFsBusy = false;
  String? appFsStatusText;
  bool shellBusy = false;
  String? shellStatusText;
  bool voiceInputBusy = false;
  String? voiceInputStatusText;
  final List<FileOfferInfo> fileOffers = [];
  final List<DownloadedFileInfo> downloadedFiles = [];
  final Map<String, String> savedFilePaths = {};
  final List<WorkspaceFileInfo> fileSuggestions = [];
  final Map<String, List<ChatMessage>> messagesBySession = {};
  String fileSuggestionQuery = '';
  String appFilePath = '';
  AppFsFileInfo? appPreviewFile;
  String accentName = 'neutral';
  String themeName = 'dark';
  String chatTextSize = 'large';

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

  CodexPlanInfo? get activePlan {
    final id = activeSession?.sessionId;
    if (id == null) return null;
    final plan = _plansBySession[id];
    if (plan == null || plan.text.trim().isEmpty) return null;
    return plan;
  }

  List<AppSubagentInfo> get activeSubagents {
    final id = activeSession?.sessionId;
    if (id == null) return const [];
    return _subagentsBySession[id] ?? const [];
  }

  List<ChatMessage> get pendingApprovals => activeMessages
      .where(
        (message) =>
            message.kind == AgentMessageKind.approval && !message.complete,
      )
      .toList(growable: false);

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

  double get chatTextScale {
    return switch (chatTextSize) {
      'compact' => 1.0,
      'xl' => 1.22,
      'large' => 1.12,
      _ => 1.08,
    };
  }

  String latestAssistantPreview({int maxLines = 3, int maxChars = 220}) {
    final message = _latestAssistantMessageForSession(activeSession?.sessionId);
    if (message == null) return '';
    return _compactPreview(
      message.text,
      maxLines: maxLines,
      maxChars: maxChars,
    );
  }

  Future<void> initializeNotifications() => _notifier.initialize();

  Future<void> checkForUpdates({bool silent = false}) async {
    if (updateStatus == UpdateCheckStatus.checking) return;
    updateStatus = UpdateCheckStatus.checking;
    updateErrorText = null;
    notifyListeners();

    try {
      final update = await _updateService.checkForUpdate();
      availableUpdate = update;
      updateStatus = update.hasUpdate
          ? UpdateCheckStatus.available
          : UpdateCheckStatus.current;
      if (update.hasUpdate) {
        _showNotice(
          'Update available',
          '${update.title} is ready to download.',
          payload: 'update:${update.latestVersion}',
          category: AppNotificationCategory.update,
        );
      } else if (!silent) {
        _showNotice(
          'App is current',
          'Codex Link ${update.currentVersion} is up to date.',
          payload: 'update:current',
          category: AppNotificationCategory.update,
        );
      }
    } catch (error) {
      updateStatus = UpdateCheckStatus.failed;
      updateErrorText = error.toString();
      if (!silent) {
        _showNotice(
          'Update check failed',
          _compactPreview(error.toString(), maxLines: 2, maxChars: 160),
          payload: 'update:error',
          category: AppNotificationCategory.error,
        );
      }
    }
    notifyListeners();
  }

  Future<void> openAvailableUpdate() async {
    final update = availableUpdate;
    if (update == null) return;
    try {
      final opened = await _updateService.openUpdate(update);
      if (!opened) {
        _showNotice(
          'Could not open update',
          'Open the GitHub release from Settings.',
          payload: 'update:open-failed',
          category: AppNotificationCategory.error,
        );
      }
    } catch (error) {
      updateErrorText = error.toString();
      _showNotice(
        'Could not open update',
        _compactPreview(error.toString(), maxLines: 2, maxChars: 160),
        payload: 'update:open-error',
        category: AppNotificationCategory.error,
      );
    }
    notifyListeners();
  }

  Future<void> openProjectOnGitHub() async {
    try {
      final opened = await _updateService.openProjectPage();
      if (!opened) {
        _showNotice(
          'Could not open GitHub',
          'Open github.com/makise-ui/codex-link in your browser.',
          payload: 'github:open-failed',
          category: AppNotificationCategory.error,
        );
      }
    } catch (error) {
      _showNotice(
        'Could not open GitHub',
        _compactPreview(error.toString(), maxLines: 2, maxChars: 160),
        payload: 'github:open-error',
        category: AppNotificationCategory.error,
      );
    }
    notifyListeners();
  }

  void setAppForeground(bool isForeground) {
    _isAppForeground = isForeground;
  }

  void clearLatestNotice() {
    if (latestNotice == null) return;
    latestNotice = null;
    notifyListeners();
  }

  bool notificationCategoryEnabled(AppNotificationCategory category) {
    return _enabledNotificationCategories.contains(category);
  }

  void setNotificationCategoryEnabled(
    AppNotificationCategory category,
    bool enabled,
  ) {
    final changed = enabled
        ? _enabledNotificationCategories.add(category)
        : _enabledNotificationCategories.remove(category);
    if (!changed) return;
    notifyListeners();
  }

  void setInAppNoticeDurationSeconds(int seconds) {
    const allowed = {2, 3, 5, 6, 8, 12};
    final normalized = allowed.contains(seconds) ? seconds : 6;
    if (inAppNoticeDurationSeconds == normalized) return;
    inAppNoticeDurationSeconds = normalized;
    notifyListeners();
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

  void refreshAppServerActions() {
    refreshAppPlugins();
    refreshAppMcpServers();
    refreshRemoteControlStatus();
    refreshAppRateLimits();
    refreshHostUpdateStatus();
  }

  void refreshAppPlugins() {
    appServerActionsBusy = true;
    appServerActionsErrorText = null;
    notifyListeners();
    _send({
      'type': 'app.plugin.list',
      if (activeSession?.sessionId != null)
        'sessionId': activeSession!.sessionId,
    });
  }

  void readAppPlugin(
    String pluginName, {
    String? marketplacePath,
    String? remoteMarketplaceName,
  }) {
    final trimmed = pluginName.trim();
    if (trimmed.isEmpty) return;
    appServerActionsBusy = true;
    appServerActionsErrorText = null;
    notifyListeners();
    _send({
      'type': 'app.plugin.read',
      'pluginName': trimmed,
      if (marketplacePath?.trim().isNotEmpty == true)
        'marketplacePath': marketplacePath!.trim(),
      if (remoteMarketplaceName?.trim().isNotEmpty == true)
        'remoteMarketplaceName': remoteMarketplaceName!.trim(),
    });
  }

  void installAppPlugin(
    String pluginName, {
    String? marketplacePath,
    String? remoteMarketplaceName,
  }) {
    final trimmed = pluginName.trim();
    if (trimmed.isEmpty) return;
    appServerActionsBusy = true;
    appServerActionsErrorText = null;
    notifyListeners();
    _send({
      'type': 'app.plugin.install',
      'pluginName': trimmed,
      if (marketplacePath?.trim().isNotEmpty == true)
        'marketplacePath': marketplacePath!.trim(),
      if (remoteMarketplaceName?.trim().isNotEmpty == true)
        'remoteMarketplaceName': remoteMarketplaceName!.trim(),
    });
  }

  void uninstallAppPlugin(String pluginName) {
    final trimmed = pluginName.trim();
    if (trimmed.isEmpty) return;
    appServerActionsBusy = true;
    appServerActionsErrorText = null;
    notifyListeners();
    _send({'type': 'app.plugin.uninstall', 'pluginName': trimmed});
  }

  void refreshAppMcpServers({String detail = 'toolsAndAuthOnly'}) {
    appServerActionsBusy = true;
    appServerActionsErrorText = null;
    notifyListeners();
    _send({
      'type': 'app.mcp.status.list',
      if (activeSession?.sessionId != null)
        'sessionId': activeSession!.sessionId,
      'detail': detail,
    });
  }

  void startAppMcpOauthLogin(String serverName) {
    final trimmed = serverName.trim();
    if (trimmed.isEmpty) return;
    appServerActionsBusy = true;
    appServerActionsErrorText = null;
    notifyListeners();
    _send({'type': 'app.mcp.oauth.login', 'serverName': trimmed});
  }

  void refreshRemoteControlStatus() {
    appServerActionsBusy = true;
    appServerActionsErrorText = null;
    notifyListeners();
    _send({'type': 'app.remote.status.read'});
  }

  void startRemotePairing({String? manualPairingCode}) {
    appServerActionsBusy = true;
    appServerActionsErrorText = null;
    notifyListeners();
    _send({
      'type': 'app.remote.pairing.start',
      if (manualPairingCode?.trim().isNotEmpty == true)
        'manualPairingCode': manualPairingCode!.trim(),
    });
  }

  void refreshAppRateLimits() {
    appServerActionsBusy = true;
    appServerActionsErrorText = null;
    notifyListeners();
    _send({'type': 'app.account.rateLimits.read'});
  }

  void refreshHostUpdateStatus() {
    hostUpdateBusy = true;
    hostUpdateErrorText = null;
    notifyListeners();
    _send({'type': 'host.update.check'});
  }

  void runHostUpdate() {
    hostUpdateBusy = true;
    hostUpdateErrorText = null;
    hostUpdateResult = null;
    hostUpdateProgress.clear();
    notifyListeners();
    _send({'type': 'host.update.run'});
  }

  void refreshCodexAccount({bool refreshToken = false}) {
    codexAccountBusy = true;
    codexAccountErrorText = null;
    notifyListeners();
    _send({'type': 'app.account.read', if (refreshToken) 'refreshToken': true});
  }

  void startCodexDeviceLogin() {
    codexAccountBusy = true;
    codexAccountErrorText = null;
    notifyListeners();
    _send({
      'type': 'app.account.login.start',
      'loginType': 'chatgptDeviceCode',
    });
  }

  void startCodexBrowserLogin() {
    codexAccountBusy = true;
    codexAccountErrorText = null;
    notifyListeners();
    _send({'type': 'app.account.login.start', 'loginType': 'chatgpt'});
  }

  void loginCodexWithApiKey(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      codexAccountErrorText = 'API key is required.';
      notifyListeners();
      return;
    }
    codexAccountBusy = true;
    codexAccountErrorText = null;
    notifyListeners();
    _send({
      'type': 'app.account.login.start',
      'loginType': 'apiKey',
      'apiKey': trimmed,
    });
  }

  void cancelCodexLogin(String loginId) {
    final trimmed = loginId.trim();
    if (trimmed.isEmpty) return;
    codexAccountBusy = true;
    codexAccountErrorText = null;
    notifyListeners();
    _send({'type': 'app.account.login.cancel', 'loginId': trimmed});
  }

  void logoutCodexAccount() {
    codexAccountBusy = true;
    codexAccountErrorText = null;
    notifyListeners();
    _send({'type': 'app.account.logout'});
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
    appFsBusy = true;
    appFsStatusText = path.trim().isEmpty
        ? 'Opening workspace...'
        : 'Opening $path...';
    notifyListeners();
    _send({'type': 'app.fs.list', 'sessionId': sessionId, 'path': path});
  }

  void readAppFile(String path) {
    final sessionId = activeSession?.sessionId;
    if (sessionId == null || path.trim().isEmpty) return;
    appFsBusy = true;
    appFsStatusText = 'Reading ${path.trim()}...';
    notifyListeners();
    _send({'type': 'app.fs.read', 'sessionId': sessionId, 'path': path});
  }

  void writeAppFile(String path, String dataBase64) {
    final sessionId = activeSession?.sessionId;
    final trimmed = path.trim();
    if (sessionId == null || trimmed.isEmpty || dataBase64.isEmpty) return;
    appFsBusy = true;
    appFsStatusText = 'Uploading $trimmed...';
    notifyListeners();
    _send({
      'type': 'app.fs.write',
      'sessionId': sessionId,
      'path': trimmed,
      'dataBase64': dataBase64,
    });
  }

  void createAppDirectory(String path) {
    final sessionId = activeSession?.sessionId;
    final trimmed = path.trim();
    if (sessionId == null || trimmed.isEmpty) return;
    appFsBusy = true;
    appFsStatusText = 'Creating $trimmed...';
    notifyListeners();
    _send({
      'type': 'app.fs.createDirectory',
      'sessionId': sessionId,
      'path': trimmed,
    });
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

  void setWorkspaceEnvSecrets(String content, {String path = '.env.local'}) {
    final sessionId = activeSession?.sessionId;
    final trimmed = content.trim();
    if (!isConnected || sessionId == null || trimmed.isEmpty) return;
    envSecretsBusy = true;
    envSecretsStatusText = 'Saving env secrets...';
    notifyListeners();
    _send({
      'type': 'workspace.env.set',
      'sessionId': sessionId,
      'content': trimmed,
      if (path != '.env.local') 'path': path,
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

  void setSessionConfig({
    String? model,
    String? reasoningEffort,
    String? serviceTier,
  }) {
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
    if (serviceTier != null) {
      message['serviceTier'] = serviceTier.trim().isEmpty
          ? null
          : serviceTier.trim();
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

  void setThemeName(String name) {
    final normalized = name == 'light' ? 'light' : 'dark';
    if (themeName == normalized) return;
    themeName = normalized;
    notifyListeners();
  }

  void setChatTextSize(String size) {
    const allowed = {'compact', 'default', 'large', 'xl'};
    final normalized = allowed.contains(size) ? size : 'large';
    if (chatTextSize == normalized) return;
    chatTextSize = normalized;
    notifyListeners();
  }

  void runShellCommand(String command) {
    final sessionId = activeSession?.sessionId;
    final trimmed = command.trim();
    if (!isConnected || sessionId == null || trimmed.isEmpty || shellBusy) {
      return;
    }
    shellBusy = true;
    shellStatusText = 'Running $trimmed...';
    notifyListeners();
    _send({
      'type': 'shell.command.run',
      'sessionId': sessionId,
      'command': trimmed,
    });
  }

  Future<VoiceTranscriptionResult?> transcribeVoiceInput() async {
    if (voiceInputBusy) return null;
    voiceInputBusy = true;
    voiceInputStatusText = 'Listening...';
    latestErrorText = null;
    notifyListeners();
    try {
      final result = await _voiceTranscriptionService.transcribeOnce();
      voiceInputBusy = false;
      voiceInputStatusText = null;
      notifyListeners();
      return result.text.trim().isEmpty ? null : result;
    } catch (error) {
      voiceInputBusy = false;
      voiceInputStatusText = null;
      latestErrorText = _compactPreview(
        error.toString(),
        maxLines: 2,
        maxChars: 160,
      );
      notifyListeners();
      return null;
    }
  }

  void runCommand(CodexCommandInfo command) {
    switch (command.commandId) {
      case 'codex.stop':
        cancelRun();
        return;
      case 'codex.new':
        createSession();
        return;
      case 'codex.review':
        startReview();
        return;
      case 'codex.model':
        statusText = 'Open ${command.title} from settings.';
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
    final list = messagesBySession[sessionId];
    if (list != null) {
      for (var index = 0; index < list.length; index++) {
        final message = list[index];
        if (message.kind == AgentMessageKind.approval &&
            message.text.contains('approvalId $approvalId')) {
          list[index] = message.copyWith(complete: true);
        }
      }
      notifyListeners();
    }
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

  void _refreshAppDirectorySilently(String path) {
    final sessionId = activeSession?.sessionId;
    if (sessionId == null) return;
    _send({'type': 'app.fs.list', 'sessionId': sessionId, 'path': path});
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
      case 'session.plan.updated':
        _applyPlanUpdated(message);
        break;
      case 'session.subagents.updated':
        _applySubagentsUpdated(message);
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
        _ensurePlaygroundWorkspace();
        break;
      case 'workspace.file.search.results':
        _replaceFileSuggestions(message);
        break;
      case 'workspace.env.updated':
        _applyWorkspaceEnvUpdated(message);
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
      case 'app.account.status':
        _applyCodexAccountStatus(message);
        break;
      case 'app.account.updated':
        _applyCodexAccountUpdated(message);
        break;
      case 'app.account.login.started':
        _applyCodexLoginStarted(message);
        break;
      case 'app.account.login.cancelled':
        _applyCodexLoginCancelled(message);
        break;
      case 'app.account.login.completed':
        _applyCodexLoginCompleted(message);
        break;
      case 'app.account.rateLimits':
        appRateLimits
          ..clear()
          ..addAll(
            ((message['limits'] as List<dynamic>? ?? const [])).map(
              (item) => AppRateLimitInfo.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            ),
          );
        appServerActionsBusy = false;
        appServerActionsErrorText = null;
        break;
      case 'host.update.status':
        hostUpdateStatus = HostUpdateStatusInfo.fromJson(message);
        hostUpdateBusy = hostUpdateStatus?.updateRunning ?? false;
        hostUpdateErrorText = hostUpdateStatus?.error;
        break;
      case 'host.update.progress':
        final progress = HostUpdateProgressInfo.fromJson(message);
        hostUpdateProgress.add(progress);
        hostUpdateBusy =
            progress.phase != 'completed' && progress.phase != 'failed';
        break;
      case 'host.update.result':
        hostUpdateResult = HostUpdateResultInfo.fromJson(message);
        hostUpdateBusy = false;
        hostUpdateErrorText = hostUpdateResult?.updated == true
            ? null
            : hostUpdateResult?.message;
        _showNotice(
          hostUpdateResult?.updated == true
              ? 'Host update finished'
              : 'Host update skipped',
          hostUpdateResult?.message ?? 'Host update finished.',
          payload: 'host:update',
          category: AppNotificationCategory.update,
        );
        break;
      case 'shell.command.result':
        shellHistory.add(ShellCommandResultInfo.fromJson(message));
        shellBusy = false;
        shellStatusText = null;
        break;
      case 'app.plugin.list':
        appPluginMarketplaces
          ..clear()
          ..addAll(
            ((message['marketplaces'] as List<dynamic>? ?? const [])).map(
              (item) => AppPluginMarketplaceInfo.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            ),
          );
        appServerActionsBusy = false;
        appServerActionsErrorText = null;
        break;
      case 'app.plugin.detail':
        if (message['plugin'] is Map) {
          appSelectedPlugin = AppPluginDetailInfo.fromJson(
            Map<String, dynamic>.from(message['plugin'] as Map),
          );
        }
        appServerActionsBusy = false;
        appServerActionsErrorText = null;
        break;
      case 'app.plugin.install.result':
        appPluginInstallResult = AppPluginInstallResultInfo.fromJson(message);
        appServerActionsBusy = false;
        appServerActionsErrorText = null;
        _showNotice(
          appPluginInstallResult?.installed == true
              ? 'Plugin installed'
              : 'Plugin install updated',
          appPluginInstallResult?.pluginName ?? 'Plugin action finished.',
          payload: 'plugin:install',
          category: AppNotificationCategory.other,
        );
        break;
      case 'app.plugin.uninstall.result':
        appServerActionsBusy = false;
        appServerActionsErrorText = null;
        _showNotice(
          'Plugin removed',
          message['pluginName'] as String? ?? 'Plugin removed.',
          payload: 'plugin:uninstall',
          category: AppNotificationCategory.other,
        );
        break;
      case 'app.mcp.status.list':
        appMcpServers
          ..clear()
          ..addAll(
            ((message['servers'] as List<dynamic>? ?? const [])).map(
              (item) => AppMcpServerInfo.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            ),
          );
        appServerActionsBusy = false;
        appServerActionsErrorText = null;
        break;
      case 'app.mcp.oauth.login.started':
        appMcpOauthLogin = AppMcpOauthLoginInfo.fromJson(message);
        appServerActionsBusy = false;
        appServerActionsErrorText = null;
        _showNotice(
          'MCP login ready',
          appMcpOauthLogin?.loginUrl ?? appMcpOauthLogin?.serverName ?? '',
          payload: 'mcp:oauth',
          category: AppNotificationCategory.other,
        );
        break;
      case 'app.remote.status':
        if (message['status'] is Map) {
          appRemoteStatus = AppRemoteStatusInfo.fromJson(
            Map<String, dynamic>.from(message['status'] as Map),
          );
        }
        appServerActionsBusy = false;
        appServerActionsErrorText = null;
        break;
      case 'app.remote.pairing.started':
        if (message['pairing'] is Map) {
          appRemotePairing = AppRemotePairingInfo.fromJson(
            Map<String, dynamic>.from(message['pairing'] as Map),
          );
        }
        appServerActionsBusy = false;
        appServerActionsErrorText = null;
        _showNotice(
          'Remote pairing ready',
          appRemotePairing?.manualPairingCode ??
              appRemotePairing?.pairingCode ??
              '',
          payload: 'remote:pairing',
          category: AppNotificationCategory.remote,
        );
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
        appFsBusy = false;
        appFsStatusText = null;
        break;
      case 'app.fs.file':
        if (message['file'] is Map) {
          appPreviewFile = AppFsFileInfo.fromJson(
            Map<String, dynamic>.from(message['file'] as Map),
          );
        }
        appFsBusy = false;
        appFsStatusText = null;
        break;
      case 'app.fs.write.result':
        if (message['file'] is Map) {
          appPreviewFile = AppFsFileInfo.fromJson(
            Map<String, dynamic>.from(message['file'] as Map),
          );
          appFsStatusText = 'Uploaded ${appPreviewFile!.path}.';
        } else {
          appFsStatusText = 'File uploaded.';
        }
        appFsBusy = false;
        _refreshAppDirectorySilently(appFilePath);
        break;
      case 'app.fs.directory.created':
        appFsBusy = false;
        appFsStatusText = 'Created ${message['path'] as String? ?? 'folder'}.';
        _refreshAppDirectorySilently(appFilePath);
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
        if (appFsBusy) {
          appFsBusy = false;
          appFsStatusText =
              message['message'] as String? ?? 'File operation failed.';
        }
        if (envSecretsBusy) {
          envSecretsBusy = false;
          envSecretsStatusText =
              message['message'] as String? ?? 'Could not save env secrets.';
        }
        if (appServerActionsBusy) {
          appServerActionsBusy = false;
          appServerActionsErrorText =
              message['message'] as String? ?? 'App-server action failed.';
        }
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
    _subagentsBySession.removeWhere(
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

  void _applyWorkspaceEnvUpdated(Map<String, dynamic> message) {
    final names = (message['variableNames'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .map((name) => name.trim())
        .toList(growable: false);
    final path = message['path'] as String? ?? '.env.local';
    final skipped = message['skippedLineCount'] as int? ?? 0;
    envSecretsBusy = false;
    envSecretsStatusText = names.isEmpty
        ? 'No env secrets were saved.'
        : 'Saved ${names.length} env ${names.length == 1 ? 'secret' : 'secrets'} to $path: ${names.join(', ')}${skipped > 0 ? ' ($skipped skipped)' : ''}';
    _showNotice(
      'Env secrets saved',
      envSecretsStatusText!,
      payload: 'workspace-env:saved',
      category: AppNotificationCategory.other,
    );
  }

  void _applyCodexAccountStatus(Map<String, dynamic> message) {
    final accountMap = message['account'];
    if (accountMap is! Map) return;
    codexAccount = CodexAccountInfo.fromJson(
      Map<String, dynamic>.from(accountMap),
    );
    codexAccountBusy = false;
    codexAccountErrorText = null;
  }

  void _applyCodexAccountUpdated(Map<String, dynamic> message) {
    final accountMap = message['account'];
    if (accountMap is! Map) return;
    final next = CodexAccountInfo.fromJson(
      Map<String, dynamic>.from(accountMap),
    );
    final previous = codexAccount;
    codexAccount = CodexAccountInfo(
      accountType: next.accountType,
      email: next.isSignedIn ? next.email ?? previous?.email : next.email,
      planType: next.isSignedIn
          ? next.planType ?? previous?.planType
          : next.planType,
      authMode: next.authMode,
      requiresOpenaiAuth: next.requiresOpenaiAuth,
    );
    codexAccountBusy = false;
    codexAccountErrorText = null;
  }

  void _applyCodexLoginStarted(Map<String, dynamic> message) {
    final flowMap = message['flow'];
    if (flowMap is! Map) return;
    activeCodexLogin = CodexAccountLoginFlow.fromJson(
      Map<String, dynamic>.from(flowMap),
    );
    codexAccountBusy = false;
    codexAccountErrorText = null;
    final flow = activeCodexLogin;
    if (flow?.type == 'apiKey') {
      activeCodexLogin = null;
      _showNotice(
        'Codex API key saved',
        'The host Codex account is configured.',
        payload: 'codex-account:api-key',
        category: AppNotificationCategory.other,
      );
    } else if (flow?.isDeviceCode == true && flow?.userCode != null) {
      _showNotice(
        'Codex device code ready',
        flow!.userCode!,
        payload: 'codex-account:device-code',
        category: AppNotificationCategory.other,
      );
    }
  }

  void _applyCodexLoginCancelled(Map<String, dynamic> message) {
    final loginId = message['loginId'] as String?;
    if (loginId == null ||
        activeCodexLogin?.loginId == null ||
        activeCodexLogin?.loginId == loginId) {
      activeCodexLogin = null;
    }
    codexAccountBusy = false;
    codexAccountErrorText = null;
    final status = message['status'] as String? ?? 'canceled';
    _showNotice(
      status == 'notFound' ? 'Codex login not found' : 'Codex login cancelled',
      status == 'notFound'
          ? 'The login request was no longer active.'
          : 'The login request was cancelled.',
      payload: 'codex-account:cancelled',
      category: AppNotificationCategory.other,
    );
  }

  void _applyCodexLoginCompleted(Map<String, dynamic> message) {
    final loginId = message['loginId'] as String?;
    if (loginId == null || activeCodexLogin?.loginId == loginId) {
      activeCodexLogin = null;
    }
    codexAccountBusy = false;
    final success = message['success'] == true;
    final error = message['error'] as String?;
    codexAccountErrorText = success ? null : error ?? 'Codex login failed.';
    _showNotice(
      success ? 'Codex login complete' : 'Codex login failed',
      success
          ? 'The host Codex account is ready.'
          : _compactPreview(codexAccountErrorText ?? 'Codex login failed.'),
      payload: 'codex-account:completed',
      category: success
          ? AppNotificationCategory.other
          : AppNotificationCategory.error,
    );
    if (success) {
      refreshCodexAccount(refreshToken: true);
    }
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
    _showNotice(
      title,
      _compactPreview(details),
      payload: 'goal:$sessionId',
      category: AppNotificationCategory.goal,
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

  void _applyPlanUpdated(Map<String, dynamic> message) {
    final sessionId = _sessionIdForMessage(message);
    if (sessionId == null) return;
    final plan = CodexPlanInfo.fromJson({...message, 'sessionId': sessionId});
    if (plan.text.trim().isEmpty) {
      _plansBySession.remove(sessionId);
      return;
    }
    _plansBySession[sessionId] = plan;
    _showNotice(
      'Plan updated',
      _compactPreview(plan.text, maxLines: 1),
      payload: 'plan:$sessionId',
      category: AppNotificationCategory.plan,
    );
  }

  void _applySubagentsUpdated(Map<String, dynamic> message) {
    final sessionId = _sessionIdForMessage(message);
    if (sessionId == null) return;
    final subagents = (message['subagents'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (item) => AppSubagentInfo.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.threadId.trim().isNotEmpty)
        .toList(growable: false);
    if (subagents.isEmpty) {
      _subagentsBySession.remove(sessionId);
      return;
    }
    _subagentsBySession[sessionId] = subagents;
  }

  void _deleteLocalSession(String sessionId) {
    sessions.removeWhere((session) => session.sessionId == sessionId);
    messagesBySession.remove(sessionId);
    _activeRunIdsBySession.remove(sessionId);
    _lastGoalEventBySession.remove(sessionId);
    _plansBySession.remove(sessionId);
    _subagentsBySession.remove(sessionId);
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
      list[index] = list[index].copyWith(
        complete: true,
        completedAt: DateTime.now(),
      );
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
    _upsertFileActivity(
      sessionId,
      lines,
      title: 'File activity',
      runId: message['runId'] as String?,
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
    _upsertFileActivity(
      sessionId,
      '${offer.reason} ${offer.path}\nsize ${offer.sizeBytes}\nfileId ${offer.fileId}',
      title: 'File activity',
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

  void _ensurePlaygroundWorkspace() {
    if (workspaces.any((workspace) => workspace.workspaceId == 'playground')) {
      return;
    }
    workspaces.add(
      const WorkspaceInfo(
        workspaceId: 'playground',
        label: 'Playground',
        path: '~/.codex-link/playground',
        active: false,
      ),
    );
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
    latestErrorText = text;
  }

  void clearLatestError() {
    if (latestErrorText == null) return;
    latestErrorText = null;
    notifyListeners();
  }

  void _showNotice(
    String title,
    String body, {
    String? payload,
    AppNotificationCategory category = AppNotificationCategory.other,
  }) {
    if (!notificationCategoryEnabled(category)) return;
    final normalizedTitle = title.trim();
    final normalizedBody = body.trim();
    if (normalizedTitle.isEmpty || normalizedBody.isEmpty) return;
    latestNotice = AppNotice(
      id: _uuid.v4(),
      title: normalizedTitle,
      body: normalizedBody,
      payload: payload,
      createdAt: DateTime.now(),
    );
    if (!_isAppForeground) {
      unawaited(
        _notifier.show(
          title: normalizedTitle,
          body: normalizedBody,
          payload: payload,
        ),
      );
    }
  }

  void _upsertFileActivity(
    String sessionId,
    String text, {
    required String title,
    String? runId,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final list = messagesBySession.putIfAbsent(sessionId, () => []);
    final messageId =
        'file-activity-${runId ?? _activeRunIdForSession(sessionId) ?? sessionId}';
    final index = list.indexWhere((message) => message.id == messageId);
    if (index >= 0) {
      final current = list[index];
      final nextText = current.text.trim().isEmpty
          ? trimmed
          : '${current.text.trim()}\n$trimmed';
      list[index] = current.copyWith(text: nextText, title: title);
      return;
    }
    list.add(
      ChatMessage(
        id: messageId,
        role: ChatRole.system,
        kind: AgentMessageKind.files,
        title: title,
        text: trimmed,
        runId: runId ?? _activeRunIdForSession(sessionId),
        createdAt: DateTime.now(),
      ),
    );
  }

  void _markRunStarted(Map<String, dynamic> message) {
    final sessionId = _sessionIdForMessage(message);
    final runId = message['runId'] as String?;
    if (sessionId == null || runId == null || runId.isEmpty) return;
    _subagentsBySession.remove(sessionId);
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
    final exitCode = message['exitCode'] as int?;
    final status = exitCode == null || exitCode == 0 ? 'completed' : 'failed';
    _clearSessionRun(
      sessionId,
      message['runId'] as String?,
      lastStatus: status,
    );
    _notifyRunFinished(sessionId, message['runId'] as String?, status);
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
      _notifyRunFinished(sessionId, runId, status);
    }
  }

  void _clearSessionRun(String sessionId, String? runId, {String? lastStatus}) {
    final currentRunId = _activeRunIdsBySession[sessionId];
    if (runId == null ||
        runId.isEmpty ||
        currentRunId == null ||
        currentRunId == runId) {
      _subagentsBySession.remove(sessionId);
      _activeRunIdsBySession.remove(sessionId);
      _updateSessionRunState(
        sessionId,
        clearActiveRunId: true,
        lastStatus: lastStatus,
      );
      _syncActiveRunId();
    }
  }

  void _notifyRunFinished(String sessionId, String? runId, String status) {
    final signature = '$sessionId:${runId ?? 'unknown'}:$status';
    if (_runNoticeSignatures.contains(signature)) return;
    _runNoticeSignatures.add(signature);
    final title = switch (status) {
      'failed' => 'Task failed',
      'cancelled' => 'Task cancelled',
      _ => 'Task finished',
    };
    final preview = _latestAssistantPreviewForSession(sessionId);
    final body = preview.isEmpty
        ? switch (status) {
            'failed' => 'The run finished with an error.',
            'cancelled' => 'The run was cancelled.',
            _ => 'The run completed.',
          }
        : preview;
    _showNotice(
      title,
      body,
      payload: 'run:$sessionId:${runId ?? ''}',
      category: AppNotificationCategory.task,
    );
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

  ChatMessage? _latestAssistantMessageForSession(String? sessionId) {
    if (sessionId == null) return null;
    final messages = messagesBySession[sessionId] ?? const <ChatMessage>[];
    for (final candidate in messages.reversed) {
      if (candidate.role == ChatRole.assistant &&
          candidate.kind == AgentMessageKind.response &&
          candidate.text.trim().isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }

  String _latestAssistantPreviewForSession(String sessionId) {
    final message = _latestAssistantMessageForSession(sessionId);
    if (message == null) return '';
    return _compactPreview(message.text);
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

String _compactPreview(String text, {int maxLines = 3, int maxChars = 220}) {
  final lines = text
      .trim()
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .take(maxLines)
      .join('\n');
  if (lines.length <= maxChars) return lines;
  return '${lines.substring(0, maxChars - 1).trimRight()}…';
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
  final rawPath = _firstPathToken(match?.group(1)?.trim() ?? '');
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

String? _firstPathToken(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final first = trimmed[0];
  if (first == '"' || first == "'") {
    final end = trimmed.indexOf(first, 1);
    if (end > 0) return trimmed.substring(0, end + 1);
    return trimmed;
  }
  return trimmed.split(RegExp(r'\s+')).first;
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
