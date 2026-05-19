import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class RecentFile {
  RecentFile({required this.path, required this.openedAt});

  final String path;
  final DateTime openedAt;

  Map<String, dynamic> toJson() => {
        'path': path,
        'openedAt': openedAt.toIso8601String(),
      };

  static RecentFile fromJson(Map<String, dynamic> j) => RecentFile(
        path: j['path'] as String,
        openedAt: DateTime.parse(j['openedAt'] as String),
      );
}

class RecentsStore {
  RecentsStore._(this._prefs);

  static const _key = 'recent_files_v1';
  static const _maxEntries = 30;

  final SharedPreferences _prefs;

  static Future<RecentsStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return RecentsStore._(prefs);
  }

  List<RecentFile> load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(RecentFile.fromJson)
          .toList();
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<List<RecentFile>> touch(String path) async {
    final now = DateTime.now();
    final existing = load().where((r) => r.path != path).toList();
    final updated = [RecentFile(path: path, openedAt: now), ...existing]
        .take(_maxEntries)
        .toList();
    await _persist(updated);
    return updated;
  }

  Future<List<RecentFile>> remove(String path) async {
    final updated = load().where((r) => r.path != path).toList();
    await _persist(updated);
    return updated;
  }

  Future<void> clearAll() async {
    await _prefs.remove(_key);
  }

  Future<void> _persist(List<RecentFile> list) async {
    await _prefs.setString(
      _key,
      jsonEncode(list.map((r) => r.toJson()).toList()),
    );
  }
}
