import 'dart:convert';

import '../protocol/bridge_messages.dart';

PairingPayload parsePairingPayload(String raw) {
  final decoded = jsonDecode(raw.trim());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Pairing payload must be a JSON object');
  }
  return PairingPayload(
    version: decoded['version'] as int? ?? 1,
    url: decoded['url'] as String? ?? '',
    localUrl: decoded['localUrl'] as String?,
    pairingToken: decoded['pairingToken'] as String? ?? '',
    hostId: decoded['hostId'] as String? ?? '',
    insecureDevMode: decoded['insecureDevMode'] as bool? ?? false,
    connectionMode: decoded['connectionMode'] as String?,
    tunnelProvider: decoded['tunnelProvider'] as String?,
  );
}
