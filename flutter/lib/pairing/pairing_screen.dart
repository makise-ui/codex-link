import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../protocol/bridge_messages.dart';
import '../theme/app_theme.dart';
import 'qr_scanner_screen.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _payloadController = TextEditingController();
  final _deviceController = TextEditingController(text: 'Codex Link Mobile');
  final _urlController = TextEditingController(text: 'ws://127.0.0.1:8787');
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _payloadController.dispose();
    _deviceController.dispose();
    _urlController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final connecting = controller.phase == ConnectionPhase.connecting;
    return AnimatedChatGptBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'Codex Link',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const Spacer(),
                    ChatGptActionPill(
                      children: [
                        IconButton(
                          tooltip: 'Open GitHub',
                          onPressed: controller.openProjectOnGitHub,
                          icon: const Icon(Icons.code_rounded),
                        ),
                        IconButton(
                          tooltip: 'Scan QR code',
                          onPressed: connecting
                              ? null
                              : () => _openScanner(context),
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                        ),
                        IconButton(
                          tooltip: 'Reconnect saved host',
                          onPressed:
                              controller.credentials == null || connecting
                              ? null
                              : controller.reconnect,
                          icon: const Icon(Icons.history_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 48),
                const SoftPill(
                  label: 'LOCAL OR TUNNEL',
                  color: CodexColors.greenSoft,
                  icon: Icons.lock_outline_rounded,
                ),
                const SizedBox(height: 28),
                Text(
                  'Connect to Codex',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Scan the QR from the host bridge, paste pairing JSON, or login with a local ws:// URL or secure tunnel wss:// URL from cloudflared, ngrok, or another tunnel.',
                  style: TextStyle(
                    color: CodexColors.muted,
                    fontSize: 18,
                    height: 1.42,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: connecting ? null : () => _openScanner(context),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('Scan QR code'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(58),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (connecting)
                  OutlinedButton.icon(
                    onPressed: controller.cancelConnection,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel connection'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                const SizedBox(height: 36),
                Text(
                  'Manual pairing',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _deviceController,
                  decoration: const InputDecoration(labelText: 'Device name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _payloadController,
                  minLines: 5,
                  maxLines: 8,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
                  decoration: const InputDecoration(
                    labelText: 'Pairing JSON from host QR',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: connecting
                      ? null
                      : () => controller.pair(
                          _payloadController.text,
                          _deviceController.text,
                        ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text('Pair with host bridge'),
                ),
                const SizedBox(height: 28),
                Text(
                  'Password login',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Host or tunnel WebSocket URL',
                    hintText:
                        'ws://127.0.0.1:8787 or wss://name.trycloudflare.com',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Host password'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: connecting
                      ? null
                      : () => controller.loginWithPassword(
                          _urlController.text,
                          _passwordController.text,
                          _deviceController.text,
                        ),
                  icon: const Icon(Icons.password_rounded),
                  label: const Text('Login with password'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                if (controller.credentials != null) ...[
                  const SizedBox(height: 32),
                  Text(
                    'Saved host',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    controller.credentials!.url,
                    style: const TextStyle(
                      color: CodexColors.muted,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: connecting ? null : controller.reconnect,
                          child: const Text('Reconnect'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: controller.forgetSaved,
                          child: const Text('Forget'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 28),
                _StatusLine(
                  connecting: connecting,
                  statusText: controller.statusText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openScanner(BuildContext context) async {
    final controller = context.read<AppController>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QrScannerScreen(
          onScanned: (payload) {
            Navigator.of(context).pop();
            _payloadController.text = payload;
            controller.pair(payload, _deviceController.text);
          },
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.connecting, required this.statusText});

  final bool connecting;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: CodexColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CodexColors.borderSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (connecting)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: CodexColors.text,
              ),
            )
          else
            const Icon(
              Icons.info_outline_rounded,
              color: CodexColors.muted,
              size: 20,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              statusText,
              style: const TextStyle(color: CodexColors.muted, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
