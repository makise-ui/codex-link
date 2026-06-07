import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../protocol/bridge_messages.dart';

class SecureCredentialsStore {
  SecureCredentialsStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _urlKey = 'bridge.url';
  static const _tokenKey = 'bridge.deviceToken';
  static const _deviceKey = 'bridge.deviceId';

  Future<BridgeCredentials?> load() async {
    final values = await Future.wait([_storage.read(key: _urlKey), _storage.read(key: _tokenKey), _storage.read(key: _deviceKey)]);
    final url = values[0];
    final token = values[1];
    final deviceId = values[2];
    if (url == null || token == null || deviceId == null) return null;
    return BridgeCredentials(url: url, deviceToken: token, deviceId: deviceId);
  }

  Future<void> save(BridgeCredentials credentials) async {
    await Future.wait([
      _storage.write(key: _urlKey, value: credentials.url),
      _storage.write(key: _tokenKey, value: credentials.deviceToken),
      _storage.write(key: _deviceKey, value: credentials.deviceId),
    ]);
  }

  Future<void> clear() async {
    await Future.wait([_storage.delete(key: _urlKey), _storage.delete(key: _tokenKey), _storage.delete(key: _deviceKey)]);
  }
}
