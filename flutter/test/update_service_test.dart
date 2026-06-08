import 'package:codex_lan_flutter/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses latest GitHub release and picks the APK asset', () {
    final update = GitHubAppUpdateService.parseLatestRelease(
      currentVersion: '1.0.0',
      release: {
        'tag_name': 'v1.0.1',
        'name': 'Codex Link v1.0.1',
        'html_url':
            'https://github.com/makise-ui/codex-link/releases/tag/v1.0.1',
        'published_at': '2026-06-08T06:30:00Z',
        'assets': [
          {
            'name': 'checksums.txt',
            'browser_download_url': 'https://example.com/checksums.txt',
          },
          {
            'name': 'codex-link-v1.0.1.apk',
            'browser_download_url': 'https://example.com/codex-link.apk',
          },
        ],
      },
    );

    expect(update.hasUpdate, isTrue);
    expect(update.currentVersion, '1.0.0');
    expect(update.latestVersion, '1.0.1');
    expect(update.title, 'Codex Link v1.0.1');
    expect(update.apkUrl, Uri.parse('https://example.com/codex-link.apk'));
  });

  test('treats matching or older GitHub release as current', () {
    final update = GitHubAppUpdateService.parseLatestRelease(
      currentVersion: '1.0.1',
      release: {
        'tag_name': 'v1.0.1',
        'name': 'Codex Link v1.0.1',
        'html_url':
            'https://github.com/makise-ui/codex-link/releases/tag/v1.0.1',
        'assets': const <Map<String, String>>[],
      },
    );

    expect(update.hasUpdate, isFalse);
    expect(update.latestVersion, '1.0.1');
  });

  test('compares multi-part versions numerically', () {
    expect(compareAppVersions('1.0.10', '1.0.2'), greaterThan(0));
    expect(compareAppVersions('v2.0.0', '1.9.9'), greaterThan(0));
    expect(compareAppVersions('1.0.0+4', '1.0.0+3'), 0);
  });
}
