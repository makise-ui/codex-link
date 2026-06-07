import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_controller.dart';
import 'chat/chat_screen.dart';
import 'pairing/pairing_screen.dart';
import 'protocol/bridge_messages.dart';
import 'theme/app_theme.dart';

class CodexLanApp extends StatefulWidget {
  const CodexLanApp({super.key});

  @override
  State<CodexLanApp> createState() => _CodexLanAppState();
}

class _CodexLanAppState extends State<CodexLanApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    _controller.loadSavedCredentials();
  }

  @override
  void dispose() {
    _controller.disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: MaterialApp(
        title: 'Codex LAN',
        debugShowCheckedModeBanner: false,
        theme: buildCodexTheme(),
        home: Consumer<AppController>(
          builder: (context, controller, _) {
            if (controller.phase == ConnectionPhase.connected) {
              return const ChatScreen();
            }
            return const PairingScreen();
          },
        ),
      ),
    );
  }
}
