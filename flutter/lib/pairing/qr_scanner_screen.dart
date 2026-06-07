import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key, required this.onScanned});

  final ValueChanged<String> onScanned;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _emitted = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedChatGptBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            MobileScanner(
              onDetect: (capture) {
                if (_emitted) return;
                final value = capture.barcodes.firstOrNull?.rawValue;
                if (value == null || value.isEmpty) return;
                _emitted = true;
                widget.onScanned(value);
              },
            ),
            Container(color: Colors.black.withValues(alpha: 0.22)),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    GlassCard(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.qr_code_scanner_rounded,
                            color: CodexColors.greenSoft,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Scan the Codex Link QR',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(36),
                        border: Border.all(
                          color: CodexColors.greenSoft,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: CodexColors.green.withValues(alpha: 0.25),
                            blurRadius: 32,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const GlassCard(
                      child: Text(
                        'Keep the one-time pairing QR inside the frame. The app pairs automatically when detected.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: CodexColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
