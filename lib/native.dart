import 'dart:io' show FileSystemException;

import 'package:flutter/services.dart';

/// One open Window, as the native side reports it. The window list itself
/// lives natively — this is only what the Window menu needs to draw it.
class WindowInfo {
  const WindowInfo({
    required this.id,
    required this.title,
    required this.isKey,
  });

  final int id;
  final String title;
  final bool isKey;

  static WindowInfo fromMap(Map<Object?, Object?> map) => WindowInfo(
        id: map['id'] as int,
        title: map['title'] as String,
        isKey: map['isKey'] as bool,
      );
}

/// Thin wrapper over this Window's platform channel — every Window runs its
/// own engine and therefore its own channel instance, so every call below is
/// scoped to the Window that makes it. Methods degrade to a no-op / null when
/// the channel is absent (unit tests, non-macOS hosts) so callers never need to
/// know whether they are running on a real app.
class Native {
  static const _channel = MethodChannel('typen/native');

  /// Files macOS queued via Launch Services before Dart was ready.
  static Future<List<String>> consumePendingOpens() async {
    final raw = await _call<List<Object?>>('consumePendingOpens');
    return raw == null ? const [] : raw.cast<String>();
  }

  /// Drives the real NSWindow chrome: proxy icon, title, and the dot in the
  /// close button that macOS users read as "unsaved".
  static Future<void> setDocument({String? path, required bool edited}) =>
      _call<void>('setDocument', {'path': path, 'edited': edited})
          .then((_) {});

  /// Opens an additional Window with a blank Untitled Document. Always a fresh
  /// Window — never reuses an Empty one.
  static Future<void> newWindow() => _call<void>('newWindow').then((_) {});

  /// Hands a chosen path to the native open policy, which decides whether to
  /// front the Window already showing it, reuse an Empty one, or open a new
  /// Window. Never loads the path into this Window directly.
  static Future<void> openPath(String path) =>
      _call<void>('openPath', {'path': path}).then((_) {});

  /// Brings the Window with this id to the front.
  static Future<void> focusWindow(int id) =>
      _call<void>('focusWindow', {'id': id}).then((_) {});

  /// True when another Window already holds this path. Save As must check
  /// this before writing — the open/openPath dedup never runs for a path a
  /// window arrives at by saving, not opening.
  static Future<bool> pathOpenElsewhere(String path) async =>
      await _call<bool>('pathOpenElsewhere', {'path': path}) ?? false;

  /// Foundation's atomic replace. Sandbox-aware, preserves the original
  /// file's attributes.
  ///
  /// Returns false only when the channel itself is unavailable, so the caller
  /// can fall back. A genuine write failure (permissions, full disk) throws —
  /// silently swallowing it would be the difference between "saved" and
  /// "you think it saved".
  static Future<bool> writeAtomically(String path, Uint8List bytes) async {
    try {
      return await _channel.invokeMethod<bool>('writeAtomically', {
            'path': path,
            'bytes': bytes,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      throw FileSystemException(e.message ?? '写入失败', path);
    }
  }

  /// Security-scoped bookmark, base64. Without this, sandboxed builds lose
  /// access to a file the moment the app quits.
  static Future<String?> bookmarkCreate(String path) =>
      _call<String>('bookmarkCreate', {'path': path});

  /// Resolves a bookmark and *starts* security-scoped access to it.
  static Future<String?> bookmarkResolve(String data) =>
      _call<String>('bookmarkResolve', {'data': data});

  static Future<void> bookmarkRelease(String path) =>
      _call<void>('bookmarkRelease', {'path': path}).then((_) {});

  static Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Registers handlers for calls the native side initiates.
  ///
  /// [onOpenFile] — Finder / Launch Services asked us to open a path.
  /// [onConfirmClose] — the app is about to quit or the window is about to
  /// close; return true to allow it. macOS blocks termination until this
  /// future completes.
  /// [onActivated] — the app came to the foreground; a good moment to check
  /// whether the file changed underneath us.
  /// [onWindowsChanged] — the set of open Windows changed. Must be registered
  /// before [consumePendingOpens], which is what makes the native side start
  /// pushing to this Window.
  static void setHandlers({
    required Future<void> Function(String path) onOpenFile,
    required Future<bool> Function() onConfirmClose,
    required Future<void> Function() onActivated,
    required void Function(List<WindowInfo> windows) onWindowsChanged,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'openFile':
          await onOpenFile(call.arguments as String);
          return null;
        case 'confirmClose':
          return await onConfirmClose();
        case 'activated':
          await onActivated();
          return null;
        case 'windowsChanged':
          onWindowsChanged([
            for (final entry in call.arguments as List<Object?>)
              WindowInfo.fromMap(entry as Map<Object?, Object?>),
          ]);
          return null;
      }
      return null;
    });
  }
}
