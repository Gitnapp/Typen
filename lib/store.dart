import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native.dart';
import 'shortcuts.dart';

/// All SharedPreferences-backed persistence lives here so the rest of the app
/// never touches a key string.

// ─── Recents ────────────────────────────────────────────────────────────────

class RecentFile {
  const RecentFile({required this.path, required this.openedAt, this.bookmark});

  final String path;
  final DateTime openedAt;

  /// Base64 security-scoped bookmark. A sandboxed build loses permission to a
  /// path as soon as it quits; the bookmark is the only thing that survives.
  final String? bookmark;

  Map<String, dynamic> toJson() => {
        'path': path,
        'openedAt': openedAt.toIso8601String(),
        if (bookmark != null) 'bookmark': bookmark,
      };

  static RecentFile fromJson(Map<String, dynamic> j) => RecentFile(
        path: j['path'] as String,
        openedAt: DateTime.parse(j['openedAt'] as String),
        bookmark: j['bookmark'] as String?,
      );
}

class RecentsStore {
  RecentsStore(this._prefs);

  static const _key = 'recent_files_v2';
  static const _maxEntries = 20;

  final SharedPreferences _prefs;

  List<RecentFile> load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(RecentFile.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<RecentFile>> touch(String path) async {
    final bookmark = await Native.bookmarkCreate(path);
    final rest = load().where((r) => r.path != path);
    final updated = [
      RecentFile(path: path, openedAt: DateTime.now(), bookmark: bookmark),
      ...rest,
    ].take(_maxEntries).toList();
    await _persist(updated);
    return updated;
  }

  Future<List<RecentFile>> remove(String path) async {
    final updated = load().where((r) => r.path != path).toList();
    await _persist(updated);
    return updated;
  }

  Future<void> clearAll() => _prefs.remove(_key);

  /// Regains sandbox access to a remembered file. Returns the path to actually
  /// open — which can differ from the stored one if the file was moved — or
  /// null when access could not be restored.
  Future<String?> resolve(RecentFile file) async {
    if (file.bookmark != null) {
      final resolved = await Native.bookmarkResolve(file.bookmark!);
      if (resolved != null) return resolved;
    }
    return file.path;
  }

  Future<void> _persist(List<RecentFile> list) => _prefs.setString(
        _key,
        jsonEncode(list.map((r) => r.toJson()).toList()),
      );
}

// ─── Per-document cursor / scroll memory ────────────────────────────────────

class DocumentPosition {
  const DocumentPosition(this.offset, this.scroll);
  final int offset;
  final double scroll;
}

class CursorStore {
  CursorStore(this._prefs);

  static const _key = 'doc_positions_v1';
  static const _maxEntries = 100;

  final SharedPreferences _prefs;

  Map<String, dynamic> _all() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  DocumentPosition? get(String path) {
    final v = _all()[path];
    if (v is! Map) return null;
    return DocumentPosition(
      (v['offset'] as num?)?.toInt() ?? 0,
      (v['scroll'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<void> put(String path, DocumentPosition pos) async {
    final all = _all()..[path] = {'offset': pos.offset, 'scroll': pos.scroll};
    if (all.length > _maxEntries) {
      for (final k in all.keys.take(all.length - _maxEntries).toList()) {
        all.remove(k);
      }
    }
    await _prefs.setString(_key, jsonEncode(all));
  }
}

// ─── Settings ───────────────────────────────────────────────────────────────

class Settings extends ChangeNotifier {
  Settings(this._prefs);

  final SharedPreferences _prefs;

  /// The base font size, in the discrete steps the slider offers. Every
  /// other size in the editor is derived from it (headings multiply it,
  /// inline code scales it down), so this is the one number that moves the
  /// whole document's typography.
  static const fontSizeSteps = [12.0, 13.0, 14.0, 15.0, 16.0, 18.0, 20.0, 22.0, 24.0];
  static double get minFontSize => fontSizeSteps.first;
  static double get maxFontSize => fontSizeSteps.last;

  /// Symmetric left/right inset for the text, in logical pixels, in the
  /// steps the slider offers. Unlike the old "column width" it does not cap
  /// how wide the text may run — widen the window and the text follows,
  /// with the margin staying put.
  static const indentSteps = [24.0, 40.0, 64.0, 96.0, 140.0, 200.0, 280.0];
  static double get minIndent => indentSteps.first;
  static double get maxIndent => indentSteps.last;

  ThemeMode get themeMode => switch (_prefs.getString('theme_mode')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  set themeMode(ThemeMode v) {
    _prefs.setString('theme_mode', v.name);
    notifyListeners();
  }

  double get fontSize => snapFontSize(_prefs.getDouble('font_size') ?? 15.0);

  set fontSize(double v) {
    _prefs.setDouble('font_size', snapFontSize(v));
    notifyListeners();
  }

  /// Rounds to the nearest offered step, so a value stored by an older
  /// build (or a stray drag) still lands on a real notch.
  static double snapFontSize(double v) => _snap(v, fontSizeSteps);

  static double _snap(double v, List<double> steps) {
    var best = steps.first;
    for (final step in steps) {
      if ((step - v).abs() < (best - v).abs()) best = step;
    }
    return best;
  }

  double get indent => _snap(_prefs.getDouble('indent') ?? 64.0, indentSteps);

  set indent(double v) {
    _prefs.setDouble('indent', _snap(v, indentSteps));
    notifyListeners();
  }

  /// Soft-wrap long lines to the text column. Off means a long line runs on
  /// and the editor scrolls horizontally to follow it.
  bool get softWrap => _prefs.getBool('soft_wrap') ?? true;

  set softWrap(bool v) {
    _prefs.setBool('soft_wrap', v);
    notifyListeners();
  }

  /// Proportional font for the editor, instead of the monospace default.
  bool get proportionalEditorFont =>
      _prefs.getBool('proportional_editor_font') ?? false;

  set proportionalEditorFont(bool v) {
    _prefs.setBool('proportional_editor_font', v);
    notifyListeners();
  }

  /// When the app last checked GitHub for a new release. Throttles the
  /// automatic on-launch check — each open Window would otherwise fire its
  /// own request. Manual "检查更新…" always bypasses this.
  DateTime? get lastUpdateCheckAt {
    final ms = _prefs.getInt('last_update_check_at');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  set lastUpdateCheckAt(DateTime v) =>
      _prefs.setInt('last_update_check_at', v.millisecondsSinceEpoch);

  /// A release tag the user dismissed with "跳过此版本" — the automatic
  /// check won't prompt for it again. Manual checks always show it.
  String? get skippedUpdateTag => _prefs.getString('skipped_update_tag');

  set skippedUpdateTag(String v) => _prefs.setString('skipped_update_tag', v);

  // ─── Keyboard shortcuts ───────────────────────────────────────────────

  static const _shortcutsKey = 'shortcut_overrides_v1';

  /// Only the bindings that differ from their default are stored, so an
  /// action whose default changes in a later release follows that change
  /// unless the user has deliberately rebound it.
  Map<ShortcutAction, SingleActivator> get shortcutOverrides =>
      ShortcutCodec.decodeAll(_prefs.getString(_shortcutsKey));

  /// The binding actually in force for [action].
  SingleActivator activatorFor(ShortcutAction action) =>
      shortcutOverrides[action] ?? action.defaultActivator;

  /// The action already bound to this keystroke, if any — used to refuse a
  /// duplicate rather than leave two commands fighting over one key.
  ShortcutAction? actionBoundTo(SingleActivator a, {ShortcutAction? ignoring}) {
    for (final action in ShortcutAction.values) {
      if (action == ignoring) continue;
      if (sameBinding(activatorFor(action), a)) return action;
    }
    return null;
  }

  Future<void> setShortcut(ShortcutAction action, SingleActivator a) async {
    final next = Map<ShortcutAction, SingleActivator>.from(shortcutOverrides);
    if (sameBinding(a, action.defaultActivator)) {
      next.remove(action);
    } else {
      next[action] = a;
    }
    await _prefs.setString(_shortcutsKey, ShortcutCodec.encodeAll(next));
    notifyListeners();
  }

  /// Drops every override at once — what the "还原默认" button does.
  Future<void> resetShortcuts() async {
    await _prefs.remove(_shortcutsKey);
    notifyListeners();
  }

  bool get hasShortcutOverrides => shortcutOverrides.isNotEmpty;

  /// Re-reads every value from the platform's preferences store. Each Window
  /// runs its own engine with its own `SharedPreferences` cache, so a change
  /// made in one (the Preferences window, another Window) never appears here
  /// on its own — the native side calls this in response to its
  /// `settingsChanged` broadcast.
  Future<void> refresh() async {
    await _prefs.reload();
    notifyListeners();
  }
}

class Stores {
  const Stores(this.recents, this.cursors, this.settings);
  final RecentsStore recents;
  final CursorStore cursors;
  final Settings settings;

  static Future<Stores> open() async {
    final prefs = await SharedPreferences.getInstance();
    return Stores(RecentsStore(prefs), CursorStore(prefs), Settings(prefs));
  }
}
