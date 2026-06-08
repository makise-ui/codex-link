import 'package:codex_lan_flutter/app_controller.dart';
import 'package:codex_lan_flutter/protocol/bridge_messages.dart';
import 'package:codex_lan_flutter/sessions/session_sidebar.dart';
import 'package:codex_lan_flutter/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('renders ChatGPT-style themed surface', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCodexTheme(),
        home: const Scaffold(body: Text('Codex Link')),
      ),
    );

    expect(find.text('Codex Link'), findsOneWidget);
  });

  testWidgets('sidebar shows tunnel provider connection detail', (
    WidgetTester tester,
  ) async {
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..statusText = 'Connected to Codex Link.'
      ..hostInfo = const HostInfo(
        version: 5,
        connectionMode: 'tunnel',
        tunnelProvider: 'cloudflared',
        publicUrl: 'wss://unit.trycloudflare.com',
        localUrl: 'ws://127.0.0.1:8787',
        hostLabel: 'Codex Link',
        yoloAllowed: false,
      );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          theme: buildCodexTheme(),
          home: const Scaffold(body: SessionSidebar()),
        ),
      ),
    );

    expect(find.text('Tunnel via cloudflared'), findsOneWidget);
  });

  testWidgets('sidebar filters sessions from the search field', (
    WidgetTester tester,
  ) async {
    final controller = AppController()
      ..phase = ConnectionPhase.connected
      ..handleBridgeMessageForTest({
        'type': 'session.list',
        'activeSessionId': 's1',
        'sessions': [
          {
            'sessionId': 's1',
            'title': 'API cleanup',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/api',
            'lastStatus': 'idle',
            'mode': 'safe',
            'sandbox': 'workspace-write',
          },
          {
            'sessionId': 's2',
            'title': 'Mobile polish',
            'updatedAt': '2026-06-08T00:00:00.000Z',
            'workspaceId': 'default',
            'workdir': '/tmp/mobile',
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
          home: const Scaffold(body: SessionSidebar()),
        ),
      ),
    );

    expect(find.text('API cleanup'), findsOneWidget);
    expect(find.text('Mobile polish'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('sidebar-search')), 'api');
    await tester.pump();

    expect(find.text('API cleanup'), findsOneWidget);
    expect(find.text('Mobile polish'), findsNothing);
  });
}
