import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

enum UpdateCheckStatus { idle, checking, current, available, failed }

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.title,
    required this.releaseUrl,
    required this.hasUpdate,
    this.apkUrl,
    this.publishedAt,
    this.body,
  });

  final String currentVersion;
  final String latestVersion;
  final String title;
  final Uri releaseUrl;
  final Uri? apkUrl;
  final DateTime? publishedAt;
  final String? body;
  final bool hasUpdate;
}

abstract class AppUpdateService {
  Future<AppUpdateInfo> checkForUpdate();

  Future<bool> openUpdate(AppUpdateInfo update);
}

class GitHubAppUpdateService implements AppUpdateService {
  GitHubAppUpdateService({
    this.owner = 'makise-ui',
    this.repo = 'codex-link',
    HttpClient Function()? httpClientFactory,
    Future<PackageInfo> Function()? packageInfoLoader,
    Future<bool> Function(Uri uri)? launchUri,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _launchUri = launchUri ?? _launchExternal;

  final String owner;
  final String repo;
  final HttpClient Function() _httpClientFactory;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final Future<bool> Function(Uri uri) _launchUri;

  @override
  Future<AppUpdateInfo> checkForUpdate() async {
    final packageInfo = await _packageInfoLoader();
    final uri = Uri.https(
      'api.github.com',
      '/repos/$owner/$repo/releases/latest',
    );
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Codex Link mobile updater',
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'GitHub release check failed with HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'GitHub release response is not an object.',
        );
      }
      return parseLatestRelease(
        currentVersion: packageInfo.version,
        release: decoded,
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<bool> openUpdate(AppUpdateInfo update) {
    return _launchUri(update.apkUrl ?? update.releaseUrl);
  }

  static AppUpdateInfo parseLatestRelease({
    required String currentVersion,
    required Map<String, dynamic> release,
  }) {
    final rawTag = (release['tag_name'] as String? ?? '').trim();
    final latestVersion = _cleanVersion(rawTag.isEmpty ? '0.0.0' : rawTag);
    final releaseUrl = Uri.parse(
      release['html_url'] as String? ??
          'https://github.com/makise-ui/codex-link/releases',
    );
    final apkUrl = _apkAssetUrl(release['assets']);
    final publishedAtText = release['published_at'] as String?;
    return AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      title: (release['name'] as String?)?.trim().isNotEmpty == true
          ? (release['name'] as String).trim()
          : 'Codex Link $latestVersion',
      releaseUrl: releaseUrl,
      apkUrl: apkUrl,
      publishedAt: publishedAtText == null
          ? null
          : DateTime.tryParse(publishedAtText),
      body: release['body'] as String?,
      hasUpdate: compareAppVersions(latestVersion, currentVersion) > 0,
    );
  }

  static Uri? _apkAssetUrl(Object? assets) {
    if (assets is! List) return null;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'] as String?;
      final url = asset['browser_download_url'] as String?;
      if (name == null || url == null) continue;
      if (name.toLowerCase().endsWith('.apk')) return Uri.parse(url);
    }
    return null;
  }

  static Future<bool> _launchExternal(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

int compareAppVersions(String left, String right) {
  final leftParts = _versionParts(left);
  final rightParts = _versionParts(right);
  final maxLength = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < maxLength; index += 1) {
    final leftValue = index < leftParts.length ? leftParts[index] : 0;
    final rightValue = index < rightParts.length ? rightParts[index] : 0;
    if (leftValue != rightValue) return leftValue.compareTo(rightValue);
  }
  return 0;
}

List<int> _versionParts(String version) {
  return _cleanVersion(version)
      .split('.')
      .map(
        (part) => int.tryParse(RegExp(r'^\d+').stringMatch(part) ?? '0') ?? 0,
      )
      .toList(growable: false);
}

String _cleanVersion(String version) {
  final trimmed = version.trim().replaceFirst(RegExp(r'^[vV]'), '');
  return trimmed.split('+').first.split('-').first;
}
