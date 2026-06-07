import 'dart:convert';

Map<String, dynamic> decodeBridgeMessage(dynamic raw) {
  final decoded = jsonDecode(raw as String);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Bridge message must be a JSON object');
  }
  return decoded;
}

String encodeBridgeMessage(Map<String, dynamic> message) => jsonEncode(message);
