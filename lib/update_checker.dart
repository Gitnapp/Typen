import 'dart:convert';

import 'package:http/http.dart' as http;

/// A downloadable file attached to a GitHub release.
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.downloadUrl});

  final String name;
  final String downloadUrl;

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) => ReleaseAsset(
        name: json['name'] as String,
        downloadUrl: json['browser_download_url'] as String,
      );
}

/// A GitHub release, trimmed to what the update dialog needs.
class GitHubRelease {
  const GitHubRelease({
    required this.tagName,
    required this.name,
    required this.htmlUrl,
    required this.body,
    required this.assets,
  });

  final String tagName;
  final String name;
  final String htmlUrl;
  final String body;
  final List<ReleaseAsset> assets;

  /// The packaged app bundle for this release, if one was published — see
  /// `scripts/package_release.sh`, which always names it `Typen-vX.Y.Z.zip`.
  ReleaseAsset? get zipAsset {
    for (final asset in assets) {
      if (asset.name.toLowerCase().endsWith('.zip')) return asset;
    }
    return null;
  }

  factory GitHubRelease.fromJson(Map<String, dynamic> json) => GitHubRelease(
        tagName: json['tag_name'] as String,
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? json['name'] as String
            : json['tag_name'] as String,
        htmlUrl: json['html_url'] as String,
        body: json['body'] as String? ?? '',
        assets: ((json['assets'] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ReleaseAsset.fromJson)
            .toList(),
      );
}

/// Looks up the latest GitHub release for a repo. Every failure mode (offline,
/// rate-limited, malformed response) collapses to `null` — update checks are
/// best-effort and must never surface as an error the user has to deal with.
class UpdateChecker {
  const UpdateChecker({this.repo = 'Gitnapp/Typen'});

  final String repo;

  Future<GitHubRelease?> fetchLatest() async {
    final uri = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
    try {
      final response = await http.get(
        uri,
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map<String, dynamic>) return null;
      return GitHubRelease.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}

/// Compares two dotted version strings (an optional leading "v" and a
/// trailing Flutter-style "+build" are both ignored). Returns true when
/// [latest] is strictly newer than [current].
bool isNewerVersion(String latest, String current) {
  int segmentAt(List<int> parts, int i) => i < parts.length ? parts[i] : 0;
  final l = _parseVersion(latest);
  final c = _parseVersion(current);
  final len = l.length > c.length ? l.length : c.length;
  for (var i = 0; i < len; i++) {
    final lv = segmentAt(l, i);
    final cv = segmentAt(c, i);
    if (lv != cv) return lv > cv;
  }
  return false;
}

List<int> _parseVersion(String v) => v
    .trim()
    .replaceFirst(RegExp(r'^v', caseSensitive: false), '')
    .split('+')
    .first
    .split('.')
    .map((part) => int.tryParse(part) ?? 0)
    .toList();
