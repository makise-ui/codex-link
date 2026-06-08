import 'package:codex_lan_flutter/app_controller.dart';
import 'package:codex_lan_flutter/commands/command_center_screen.dart';
import 'package:codex_lan_flutter/protocol/bridge_messages.dart';
import 'package:codex_lan_flutter/services/bridge_socket_client.dart';
import 'package:codex_lan_flutter/services/app_notifier.dart';
import 'package:codex_lan_flutter/services/update_service.dart';
import 'package:codex_lan_flutter/settings/settings_screen.dart';
import 'package:codex_lan_flutter/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('settings exposes yolo mode when host allows it', (tester) async {
    final socket = FakeBridgeSocketClient();
    final controller = AppController(socket: socket)
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'host.info',
        'version': 7,
        'connectionMode': 'lan',
        'localUrl': 'ws://127.0.0.1:8787',
        'hostLabel': 'Codex Link',
        'yoloAllowed': true,
      })
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Mode',
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
          home: const SettingsScreen(),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('run-mode-yolo-switch')),
      420,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('run-mode-yolo-switch')));
    await tester.pump();

    expect(socket.sentMessages.last, {
      'type': 'session.mode.set',
      'sessionId': 's1',
      'mode': 'yolo',
    });
  });

  testWidgets('settings keeps operational command panels out', (tester) async {
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'Settings',
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
          home: const SettingsScreen(),
        ),
      ),
    );

    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Mode'), findsOneWidget);
    expect(find.text('Model'), findsWidgets);
    expect(find.text('Workspace'), findsNothing);
    expect(find.text('Skills'), findsNothing);
    expect(find.text('Files'), findsNothing);
    expect(find.text('Review'), findsNothing);
    expect(find.text('External Codex sessions'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Appearance'),
      420,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Appearance'), findsOneWidget);
  });

  testWidgets('settings can switch between dark and light modes', (
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
            'title': 'Appearance',
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
          home: const SettingsScreen(),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('theme-mode-light')),
      420,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('theme-mode-light')));
    await tester.pump();

    expect(controller.themeName, 'light');
    expect(find.byKey(const ValueKey('theme-mode-dark')), findsOneWidget);
  });

  testWidgets('command center owns workspace files history and commands', (
    tester,
  ) async {
    final socket = FakeBridgeSocketClient();
    final controller =
        AppController(socket: socket, notifier: FakeAppNotifier())
          ..phase = ConnectionPhase.connected
          ..commands.addAll([
            const CodexCommandInfo(
              commandId: 'codex.goal',
              title: 'goal',
              description: 'Set the goal',
              category: 'agent',
            ),
            const CodexCommandInfo(
              commandId: 'codex.doctor',
              title: 'doctor',
              description: 'Inspect local Codex health',
              category: 'session',
            ),
          ])
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
          })
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

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          theme: buildCodexTheme(),
          home: const CommandCenterScreen(),
        ),
      ),
    );

    expect(find.text('Commands'), findsWidgets);
    expect(find.text('/goal'), findsOneWidget);
    expect(find.text('/doctor'), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('App-server sessions'),
      360,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('App-server sessions'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('External Codex sessions'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('Files'), findsOneWidget);
  });

  testWidgets('settings shows available app update', (tester) async {
    final controller =
        AppController(
            updateService: FakeUpdateService(
              AppUpdateInfo(
                currentVersion: '1.0.0',
                latestVersion: '1.0.1',
                title: 'Codex Link v1.0.1',
                releaseUrl: Uri.parse(
                  'https://github.com/makise-ui/codex-link/releases/tag/v1.0.1',
                ),
                apkUrl: Uri.parse('https://example.com/codex-link.apk'),
                hasUpdate: true,
              ),
            ),
          )
          ..phase = ConnectionPhase.connected
          ..handleBridgeMessageForTest({
            'type': 'session.list',
            'activeSessionId': 's1',
            'sessions': [
              {
                'sessionId': 's1',
                'title': 'Settings',
                'updatedAt': '2026-06-08T00:00:00.000Z',
                'workspaceId': 'default',
                'workdir': '/tmp/repo',
                'lastStatus': 'idle',
                'mode': 'safe',
                'sandbox': 'workspace-write',
              },
            ],
          });

    await controller.checkForUpdates();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          theme: buildCodexTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Updates'),
      520,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('Codex Link v1.0.1'), findsOneWidget);
    expect(find.text('Download APK'), findsOneWidget);
  });
}

class FakeAppNotifier implements AppNotifier {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({
    required String title,
    required String body,
    String? payload,
  }) async {}
}

class FakeUpdateService implements AppUpdateService {
  FakeUpdateService(this.update);

  final AppUpdateInfo update;

  @override
  Future<AppUpdateInfo> checkForUpdate() async => update;

  @override
  Future<bool> openUpdate(AppUpdateInfo update) async => true;

  @override
  Future<bool> openProjectPage() async => true;
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
