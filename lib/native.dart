import 'dart:io' show FileSystemException;

import 'package:flutter/services.dart';

/// Thin wrapper over the single platform channel. Every method degrades to a
/// no-op / null when the channel is absent (unit tests, non-macOS hosts) so
/// callers never need to know whether they are running on a real app.
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
  static void setHandlers({
    required Future<void> Function(String path) onOpenFile,
    required Future<bool> Function() onConfirmClose,
    required Future<void> Function() onActivated,
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
      }
      return null;
    });
  }
}
