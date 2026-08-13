import 'package:flutter/material.dart';

import '../theme.dart';

/// Visual configuration for the source editor. Kept separate from the
/// controller so a settings change is a cheap object swap.
class HighlightConfig {
  const HighlightConfig({
    required this.palette,
    required this.fontSize,
    required this.monoFamily,
    required this.proportional,
  });

  final AppPalette palette;
  final double fontSize;
  final String monoFamily;
  final bool proportional;

  TextStyle get base => TextStyle(
        color: palette.textPrimary,
        fontFamily: proportional ? null : monoFamily,
        fontSize: fontSize,
        height: 1.6,
        leadingDistribution: TextLeadingDistribution.even,
      );

  @override
  bool operator ==(Object other) =>
      other is HighlightConfig &&
      other.palette == palette &&
      other.fontSize == fontSize &&
      other.monoFamily == monoFamily &&
      other.proportional == proportional;

  @override
  int get hashCode => Object.hash(palette, fontSize, monoFamily, proportional);
}

class _Piece {
  _Piece(this.start, this.end, this.style);
  final int start;
  final int end;
  final TextStyle style;
}

/// A [TextEditingController] that paints Markdown structure onto plain text.
///
/// The crucial property is that it changes *nothing* about the value: the
/// buffer stays exactly the bytes the user opened, so styling can never
/// corrupt a document the way a rich-text model can.
class MarkdownHighlightingController extends TextEditingController {
  MarkdownHighlightingController({super.text, required HighlightConfig config})
      : _config = config;

  HighlightConfig _config;
  set config(HighlightConfig v) {
    if (_config == v) return;
    _config = v;
    _cache = null;
    notifyListeners();
  }

  /// Ranges to tint as search hits, and which one is current.
  List<TextRange> _matches = const [];
  int _currentMatch = -1;

  void setMatches(List<TextRange> matches, int current) {
    if (_matches.length == matches.length &&
        _currentMatch == current &&
        (matches.isEmpty ||
            (matches.first == _matches.first &&
                matches.last == _matches.last))) {
      return;
    }
    _matches = matches;
    _currentMatch = current;
    _cache = null;
    notifyListeners();
  }

  String? _cachedFor;
  List<_Piece>? _cache;

  static final _fence = RegExp(r'^\s{0,3}(```|~~~)');
  static final _heading = RegExp(r'^(#{1,6})(\s+)(.*)$');
  static final _quote = RegExp(r'^(\s*>+\s?)');
  static final _rule = RegExp(r'^\s{0,3}([-*_])\s*(\1\s*){2,}$');
  static final _bullet = RegExp(r'^(\s*)([-*+]|\d{1,9}[.)])(\s+)');
  static final _task = RegExp(r'^\[([ xX])\]\s');
  static final _indentCode = RegExp(r'^(?: {4}|\t)');

  /// Font-size multiplier for an ATX heading, by level — shared between
  /// syntax highlighting and cursor sizing so the caret is never a
  /// different size than the text it's sitting next to.
  static double _headingScale(int level) => switch (level) {
        1 => 1.6,
        2 => 1.35,
        3 => 1.18,
        _ => 1.06,
      };

  /// The heading-scale multiplier for the line containing [offset] — 1.0 on
  /// any non-heading line.
  double headingScaleAt(int offset) {
    final clamped = offset.clamp(0, text.length);
    final lineStart =
        clamped == 0 ? 0 : text.lastIndexOf('\n', clamped - 1) + 1;
    var lineEnd = text.indexOf('\n', clamped);
    if (lineEnd == -1) lineEnd = text.length;
    final heading = _heading.firstMatch(text.substring(lineStart, lineEnd));
    return heading == null ? 1.0 : _headingScale(heading.group(1)!.length);
  }

  static final _inline = RegExp(
    r'(?<code>`+[^`\n]+`+)'
    r'|(?<img>!\[[^\]\n]*\]\([^)\n]*\))'
    r'|(?<link>\[[^\]\n]*\]\([^)\n]*\))'
    r'|(?<auto><[a-zA-Z][a-zA-Z0-9+.-]*:[^>\s]+>)'
    r'|(?<bold>\*\*[^\n]+?\*\*|__[^\n]+?__)'
    r'|(?<del>~~[^\n]+?~~)'
    r'|(?<em>\*[^*\n]+?\*|_[^_\n]+?_)',
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final p = _config.palette;
    final pieces = _piecesFor(text);

    var out = pieces;
    for (var i = 0; i < _matches.length; i++) {
      out = _overlay(
        out,
        _matches[i].start,
        _matches[i].end,
        TextStyle(
          backgroundColor: i == _currentMatch ? p.findCurrent : p.findMatch,
        ),
      );
    }
    if (withComposing && value.isComposingRangeValid && !value.composing.isCollapsed) {
      out = _overlay(
        out,
        value.composing.start,
        value.composing.end,
        TextStyle(decoration: TextDecoration.underline, decorationColor: p.gold),
      );
    }

    return TextSpan(
      style: style,
      children: [
        for (final piece in out)
          TextSpan(
            text: text.substring(piece.start, piece.end),
            style: piece.style,
          ),
      ],
    );
  }

  List<_Piece> _piecesFor(String src) {
    if (_cache != null && identical(_cachedFor, src)) return _cache!;
    final pieces = _scan(src);
    _cachedFor = src;
    _cache = pieces;
    return pieces;
  }

  // ─── Block-level scan ─────────────────────────────────────────────────────

  List<_Piece> _scan(String src) {
    final p = _config.palette;
    final base = _config.base;
    final out = <_Piece>[];

    final mono = base.copyWith(
      fontFamily: _config.monoFamily,
      fontSize: _config.fontSize * 0.94,
    );
    final codeStyle = mono.copyWith(color: p.emerald);
    final metaStyle = mono.copyWith(color: p.textMuted);
    final markerStyle = base.copyWith(color: p.gold);
    final mutedStyle = base.copyWith(color: p.textMuted);

    var inFence = false;
    var inFrontMatter = false;
    var lineStart = 0;
    var isFirstLine = true;

    while (lineStart <= src.length) {
      var lineEnd = src.indexOf('\n', lineStart);
      final hasNewline = lineEnd != -1;
      if (!hasNewline) lineEnd = src.length;
      final line = src.substring(lineStart, lineEnd);

      if (isFirstLine && line.trimRight() == '---') {
        inFrontMatter = true;
        out.add(_Piece(lineStart, lineEnd, metaStyle));
      } else if (inFrontMatter) {
        out.add(_Piece(lineStart, lineEnd, metaStyle));
        if (line.trimRight() == '---' || line.trimRight() == '...') {
          inFrontMatter = false;
        }
      } else if (_fence.hasMatch(line)) {
        out.add(_Piece(lineStart, lineEnd, metaStyle));
        inFence = !inFence;
      } else if (inFence || _indentCode.hasMatch(line)) {
        out.add(_Piece(lineStart, lineEnd, codeStyle));
      } else if (line.isEmpty) {
        // nothing to style
      } else if (_rule.hasMatch(line)) {
        out.add(_Piece(lineStart, lineEnd, mutedStyle));
      } else {
        _scanLine(
          src,
          lineStart,
          lineEnd,
          out,
          base: base,
          mono: codeStyle,
          marker: markerStyle,
          muted: mutedStyle,
        );
      }

      if (line.isNotEmpty) isFirstLine = false;
      if (!hasNewline) break;
      out.add(_Piece(lineEnd, lineEnd + 1, base));
      lineStart = lineEnd + 1;
      if (lineStart == src.length) break;
    }

    return _fill(out, src.length, base);
  }

  void _scanLine(
    String src,
    int start,
    int end,
    List<_Piece> out, {
    required TextStyle base,
    required TextStyle mono,
    required TextStyle marker,
    required TextStyle muted,
  }) {
    final p = _config.palette;
    final line = src.substring(start, end);
    var bodyStyle = base;
    var cursor = start;

    final heading = _heading.firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length;
      final scale = _headingScale(level);
      bodyStyle = base.copyWith(
        fontSize: _config.fontSize * scale,
        fontWeight: level <= 2 ? FontWeight.w700 : FontWeight.w600,
        letterSpacing: level == 1 ? -0.4 : 0,
      );
      final prefix = heading.group(1)!.length + heading.group(2)!.length;
      out.add(_Piece(
        cursor,
        cursor + prefix,
        bodyStyle.copyWith(color: p.textMuted, fontWeight: FontWeight.w400),
      ));
      cursor += prefix;
    } else {
      final quote = _quote.firstMatch(line);
      if (quote != null) {
        bodyStyle = base.copyWith(
          color: p.textSecondary,
          fontStyle: FontStyle.italic,
        );
        out.add(_Piece(cursor, cursor + quote.group(1)!.length, marker));
        cursor += quote.group(1)!.length;
      }

      final rest = src.substring(cursor, end);
      final bullet = _bullet.firstMatch(rest);
      if (bullet != null) {
        final indent = bullet.group(1)!.length;
        if (indent > 0) {
          out.add(_Piece(cursor, cursor + indent, base));
        }
        out.add(_Piece(
          cursor + indent,
          cursor + bullet.end,
          marker,
        ));
        cursor += bullet.end;

        final task = _task.firstMatch(src.substring(cursor, end));
        if (task != null) {
          final done = task.group(1)!.toLowerCase() == 'x';
          out.add(_Piece(
            cursor,
            cursor + task.end,
            base.copyWith(color: done ? p.emerald : p.textSecondary),
          ));
          if (done) bodyStyle = base.copyWith(color: p.textMuted);
          cursor += task.end;
        }
      }
    }

    _scanInline(src, cursor, end, out, bodyStyle, mono, muted);
  }

  // ─── Inline-level scan ────────────────────────────────────────────────────

  void _scanInline(
    String src,
    int start,
    int end,
    List<_Piece> out,
    TextStyle body,
    TextStyle mono,
    TextStyle muted,
  ) {
    if (start >= end) return;
    final p = _config.palette;
    final text = src.substring(start, end);
    var cursor = 0;

    for (final m in _inline.allMatches(text)) {
      if (m.start > cursor) {
        out.add(_Piece(start + cursor, start + m.start, body));
      }
      final s = start + m.start;
      final e = start + m.end;

      if (m.namedGroup('code') != null) {
        out.add(_Piece(s, e, mono));
      } else if (m.namedGroup('link') != null ||
          m.namedGroup('img') != null) {
        // Style the label, dim the target — the syntax stays visible but stops
        // competing with the prose.
        final split = text.indexOf('](', m.start);
        if (split > 0 && split < m.end) {
          out.add(_Piece(
            s,
            start + split + 1,
            body.copyWith(color: p.gold),
          ));
          out.add(_Piece(start + split + 1, e, muted));
        } else {
          out.add(_Piece(s, e, body.copyWith(color: p.gold)));
        }
      } else if (m.namedGroup('auto') != null) {
        out.add(_Piece(s, e, body.copyWith(color: p.gold)));
      } else if (m.namedGroup('bold') != null) {
        out.add(_Piece(s, e, body.copyWith(fontWeight: FontWeight.w700)));
      } else if (m.namedGroup('del') != null) {
        out.add(_Piece(
          s,
          e,
          body.copyWith(
            decoration: TextDecoration.lineThrough,
            color: p.textMuted,
          ),
        ));
      } else {
        out.add(_Piece(s, e, body.copyWith(fontStyle: FontStyle.italic)));
      }
      cursor = m.end;
    }

    if (cursor < text.length) {
      out.add(_Piece(start + cursor, end, body));
    }
  }

  // ─── Piece list helpers ───────────────────────────────────────────────────

  /// Guarantees the piece list is contiguous and covers [0, length).
  static List<_Piece> _fill(List<_Piece> pieces, int length, TextStyle base) {
    final out = <_Piece>[];
    var at = 0;
    for (final piece in pieces) {
      if (piece.start > at) out.add(_Piece(at, piece.start, base));
      if (piece.end > piece.start) {
        out.add(piece);
        at = piece.end;
      }
    }
    if (at < length) out.add(_Piece(at, length, base));
    return out;
  }

  /// Merges [extra] into every piece overlapping [from, to).
  static List<_Piece> _overlay(
    List<_Piece> pieces,
    int from,
    int to,
    TextStyle extra,
  ) {
    if (to <= from) return pieces;
    final out = <_Piece>[];
    for (final piece in pieces) {
      if (piece.end <= from || piece.start >= to) {
        out.add(piece);
        continue;
      }
      if (piece.start < from) {
        out.add(_Piece(piece.start, from, piece.style));
      }
      out.add(_Piece(
        piece.start < from ? from : piece.start,
        piece.end > to ? to : piece.end,
        piece.style.merge(extra),
      ));
      if (piece.end > to) {
        out.add(_Piece(to, piece.end, piece.style));
      }
    }
    return out;
  }
}
