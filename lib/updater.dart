import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'native.dart';
import 'update_checker.dart';

enum UpdateStage { downloading, extracting, verifying, installing }

class UpdateProgress {
  const UpdateProgress(this.stage, {this.fraction});
  final UpdateStage stage;

  /// 0..1 during [UpdateStage.downloading] when the server sent a
  /// Content-Length; null otherwise (indeterminate).
  final double? fraction;
}

/// Thrown for every failure mode the About page needs to explain to the
/// user. Anything else (a bug) is left to surface as an uncaught exception.
class UpdateFailure implements Exception {
  const UpdateFailure(this.message);
  final String message;
}

/// Downloads, verifies, and installs a release.
///
/// Typen ships outside the Mac App Store (Developer ID + notarization), so
/// it does not run under App Sandbox and needs no user grant to write
/// `/Applications` — the whole install is silent.
class Updater {
  const Updater();

  Future<void> run(
    GitHubRelease release, {
    required void Function(UpdateProgress) onProgress,
  }) async {
    final asset = release.zipAsset;
    if (asset == null) {
      throw const UpdateFailure('这个版本没有可下载的安装包。');
    }

    final work = await Directory.systemTemp.createTemp('typen_update');
    try {
      final zipPath = '${work.path}/${asset.name}';
      onProgress(const UpdateProgress(UpdateStage.downloading, fraction: 0));
      await _download(asset.downloadUrl, zipPath, onProgress);

      onProgress(const UpdateProgress(UpdateStage.extracting));
      final extractDir = '${work.path}/extracted';
      await Directory(extractDir).create();
      await _extract(zipPath, extractDir);

      final bundle = await _findAppBundle(extractDir);
      if (bundle == null) {
        throw const UpdateFailure('安装包内容不完整，未找到 Typen.app。');
      }

      onProgress(const UpdateProgress(UpdateStage.verifying));
      if (!await Native.verifySignature(bundle.path)) {
        throw const UpdateFailure('安装包签名校验失败，已取消安装。');
      }

      onProgress(const UpdateProgress(UpdateStage.installing));
      final installedPath = await _install(bundle.path);

      // Never returns if the relaunch actually happens — the process quits
      // from inside this call. If it does return, the user cancelled the
      // unsaved-work prompt during quit; the new copy is already installed
      // and picked up next launch.
      await Native.relaunchAfterQuit(installedPath);
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {
        // Best-effort — container temp is OS-reclaimed regardless.
      }
    }
  }

  Future<void> _download(
    String url,
    String destPath,
    void Function(UpdateProgress) onProgress,
  ) async {
    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(minutes: 3));
      if (response.statusCode != 200) {
        throw UpdateFailure('下载失败（HTTP ${response.statusCode}）。');
      }
      final total = response.contentLength;
      var received = 0;
      final sink = File(destPath).openWrite();
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(minutes: 3),
        )) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(
            UpdateProgress(
              UpdateStage.downloading,
              fraction: (total != null && total > 0)
                  ? received / total
                  : null,
            ),
          );
        }
      } finally {
        await sink.close();
      }
    } on TimeoutException {
      throw const UpdateFailure('下载超时，请检查网络后重试。');
    } finally {
      client.close();
    }
  }

  Future<void> _extract(String zipPath, String destDir) async {
    // ditto, not the `archive` package: Typen.app's frameworks contain
    // Versions/Current symlinks and exact permission bits that a pure-Dart
    // unzip does not reliably restore, which would break the bundle's
    // signature — exactly what the next step checks for.
    final result =
        await Process.run('/usr/bin/ditto', ['-x', '-k', zipPath, destDir]);
    if (result.exitCode != 0) {
      throw UpdateFailure('解压失败：${result.stderr}');
    }
  }

  Future<Directory?> _findAppBundle(String dir) async {
    await for (final entity in Directory(dir).list()) {
      if (entity is Directory && entity.path.endsWith('.app')) return entity;
    }
    return null;
  }

  /// Replaces any existing `/Applications/Typen.app` with the verified
  /// bundle. Returns the installed path.
  Future<String> _install(String bundlePath) async {
    final name = bundlePath.split('/').last;
    final dest = '/Applications/$name';

    if (await Directory(dest).exists()) {
      await Directory(dest).delete(recursive: true);
    } else if (await File(dest).exists()) {
      await File(dest).delete();
    }

    try {
      await Directory(bundlePath).rename(dest);
    } on FileSystemException {
      // Cross-device (e.g. dest on a different volume than the container
      // temp dir) — rename() can't do that atomically, so copy then clean
      // up the source ourselves.
      final copyResult =
          await Process.run('/usr/bin/ditto', [bundlePath, dest]);
      if (copyResult.exitCode != 0) {
        throw UpdateFailure('安装失败：${copyResult.stderr}');
      }
      await Directory(bundlePath).delete(recursive: true);
    }

    // The temp dir this bundle was extracted into is quarantined (it came
    // from a download), and that flag survives both rename() and ditto.
    // A quarantined app at a "real" path makes macOS App Translocation
    // launch it from a throwaway read-only copy instead, which fails to
    // spawn — so the app would install fine and then refuse to open. Strip
    // it before handing back the path.
    await Process.run('/usr/bin/xattr', ['-dr', 'com.apple.quarantine', dest]);

    return dest;
  }
}
