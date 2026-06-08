import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_controller.dart';
import 'chat/chat_screen.dart';
import 'pairing/pairing_screen.dart';
import 'theme/app_theme.dart';

class CodexLanApp extends StatefulWidget {
  const CodexLanApp({super.key});

  @override
  State<CodexLanApp> createState() => _CodexLanAppState();
}

class _CodexLanAppState extends State<CodexLanApp> with WidgetsBindingObserver {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AppController();
    _controller.loadSavedCredentials();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.disposeController();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_controller.credentials != null &&
        _controller.canShowChat &&
        !_controller.isConnected) {
      _controller.reconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<AppController>(
        builder: (context, controller, _) {
          return MaterialApp(
            title: 'Codex Link',
            debugShowCheckedModeBanner: false,
            theme: buildCodexTheme(
              accentColor: accentColorForName(controller.accentName),
            ),
            home: Builder(
              builder: (context) {
                if (controller.canShowChat) {
                  return const ChatScreen();
                }
                return const PairingScreen();
              },
            ),
          );
        },
      ),
    );
  }
}
