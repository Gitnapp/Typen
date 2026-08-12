import 'package:flutter_test/flutter_test.dart';
import 'package:typen/update_checker.dart';

void main() {
  group('isNewerVersion', () {
    test('newer patch version', () {
      expect(isNewerVersion('v0.3.2', '0.3.1'), isTrue);
    });

    test('newer minor version', () {
      expect(isNewerVersion('v0.4.0', '0.3.9'), isTrue);
    });

    test('same version is not newer', () {
      expect(isNewerVersion('v0.3.2', '0.3.2'), isFalse);
    });

    test('older version is not newer', () {
      expect(isNewerVersion('v0.3.0', '0.3.2'), isFalse);
    });

    test('ignores the Flutter-style +build suffix on the current version', () {
      expect(isNewerVersion('v0.3.2', '0.3.2+5'), isFalse);
      expect(isNewerVersion('v0.3.3', '0.3.2+5'), isTrue);
    });

    test('missing trailing segments count as zero', () {
      expect(isNewerVersion('v1.0', '0.9.9'), isTrue);
      expect(isNewerVersion('v0.9', '0.9.0'), isFalse);
    });

    test('works without a leading v', () {
      expect(isNewerVersion('0.3.2', '0.3.1'), isTrue);
    });
  });

  group('GitHubRelease.fromJson', () {
    test('falls back to tag_name when name is blank', () {
      final release = GitHubRelease.fromJson({
        'tag_name': 'v0.3.2',
        'name': '',
        'html_url': 'https://github.com/Gitnapp/Typen/releases/tag/v0.3.2',
        'body': 'notes',
      });
      expect(release.name, 'v0.3.2');
    });

    test('missing body becomes an empty string', () {
      final release = GitHubRelease.fromJson({
        'tag_name': 'v0.3.2',
        'name': 'Typen v0.3.2',
        'html_url': 'https://github.com/Gitnapp/Typen/releases/tag/v0.3.2',
      });
      expect(release.body, '');
    });
  });
}
