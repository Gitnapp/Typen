import 'package:flutter/material.dart';

/// Find & replace over the plain-text buffer. Pure logic — it never touches a
/// controller, it just reports ranges, so it is directly unit-testable.
class FindController extends ChangeNotifier {
  String _query = '';
  String replacement = '';
  bool _caseSensitive = false;
  bool _useRegex = false;

  List<TextRange> _matches = const [];
  int _current = -1;
  bool _badPattern = false;

  String get query => _query;
  bool get caseSensitive => _caseSensitive;
  bool get useRegex => _useRegex;
  List<TextRange> get matches => _matches;
  int get current => _current;
  bool get badPattern => _badPattern;
  TextRange? get currentRange =>
      _current >= 0 && _current < _matches.length ? _matches[_current] : null;

  void update(
    String text, {
    String? query,
    bool? caseSensitive,
    bool? useRegex,
    int? anchor,
  }) {
    _query = query ?? _query;
    _caseSensitive = caseSensitive ?? _caseSensitive;
    _useRegex = useRegex ?? _useRegex;
    _recompute(text, anchor: anchor);
    notifyListeners();
  }

  void refresh(String text, {int? anchor}) {
    _recompute(text, anchor: anchor);
    notifyListeners();
  }

  void clear() {
    _matches = const [];
    _current = -1;
    _badPattern = false;
    notifyListeners();
  }

  void _recompute(String text, {int? anchor}) {
    _badPattern = false;
    if (_query.isEmpty) {
      _matches = const [];
      _current = -1;
      return;
    }

    final found = <TextRange>[];
    if (_useRegex) {
      try {
        final re = RegExp(_query, caseSensitive: _caseSensitive, multiLine: true);
        for (final m in re.allMatches(text)) {
          // A zero-width match would loop forever when stepping through hits.
          if (m.end > m.start) found.add(TextRange(start: m.start, end: m.end));
        }
      } catch (_) {
        _badPattern = true;
        _matches = const [];
        _current = -1;
        return;
      }
    } else {
      final haystack = _caseSensitive ? text : text.toLowerCase();
      final needle = _caseSensitive ? _query : _query.toLowerCase();
      var at = haystack.indexOf(needle);
      while (at != -1) {
        found.add(TextRange(start: at, end: at + needle.length));
        at = haystack.indexOf(needle, at + needle.length);
      }
    }

    _matches = found;
    if (found.isEmpty) {
      _current = -1;
      return;
    }
    if (anchor != null) {
      final idx = found.indexWhere((r) => r.start >= anchor);
      _current = idx == -1 ? 0 : idx;
    } else {
      _current = _current.clamp(0, found.length - 1);
    }
  }

  TextRange? step(int delta) {
    if (_matches.isEmpty) return null;
    _current = (_current + delta) % _matches.length;
    if (_current < 0) _current += _matches.length;
    notifyListeners();
    return _matches[_current];
  }

  /// Text after replacing the current hit, plus where the caret should land.
  (String, int)? replaceCurrent(String text) {
    final range = currentRange;
    if (range == null) return null;
    final out = text.replaceRange(range.start, range.end, replacement);
    return (out, range.start + replacement.length);
  }

  /// Text after replacing every hit. Applied back-to-front so earlier ranges
  /// stay valid while later ones shift.
  (String, int)? replaceAll(String text) {
    if (_matches.isEmpty) return null;
    var out = text;
    for (final range in _matches.reversed) {
      out = out.replaceRange(range.start, range.end, replacement);
    }
    return (out, _matches.first.start + replacement.length);
  }
}
