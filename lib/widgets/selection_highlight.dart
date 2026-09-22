import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Selection highlight rects for the source field, computed from the text
/// layout itself rather than from the boxes Flutter would paint.
///
/// The raw boxes get three deterministic corrections:
///
///  * Vertical union per visual line: runs of differing font metrics on one
///    line (inline code next to prose, bold next to regular, CJK next to
///    Latin fallback) produce baseline-aligned boxes of different heights,
///    which paint as teeth along the selection's edge. Boxes arrive in text
///    order, so a new line starts at the first box whose top clears the
///    running line's bottom.
///  * Half-pixel vertical inflation: line heights get pixel-rounded while
///    the boxes don't, and the sub-pixel seam that leaves behind rasterises
///    as a dark hairline at fractional screen scales. With an opaque
///    selection colour the overlap is invisible.
///  * Rows the selection swallows whole (trailing newline included, or the
///    text ends there) extend to [rowWidth] — the flat full-width block.
///    [ui.BoxWidthStyle.max] can't be trusted for this: it extends lines to
///    the layout width but drops the extension exactly on the longest line,
///    a staircase on the right edge. The final, partially selected row keeps
///    hugging the text instead of overshooting the sentence.
List<Rect> sourceSelectionRects(
  TextPainter painter,
  TextSelection selection, {
  required double rowWidth,
}) {
  if (!selection.isValid || selection.isCollapsed) return const [];
  final plain = painter.text?.toPlainText() ?? '';
  final boxes = painter.getBoxesForSelection(
    selection,
    boxHeightStyle: ui.BoxHeightStyle.max,
    boxWidthStyle: ui.BoxWidthStyle.tight,
  );
  if (boxes.isEmpty) return const [];

  // Group boxes per visual line and union their vertical extents.
  final groups = <List<Rect>>[];
  var lineBottom = double.negativeInfinity;
  for (final box in boxes) {
    final r = box.toRect();
    if (groups.isNotEmpty && r.top >= lineBottom - 0.5) {
      groups.add(<Rect>[]);
      lineBottom = double.negativeInfinity;
    }
    if (groups.isEmpty) groups.add(<Rect>[]);
    groups.last.add(r);
    if (r.bottom > lineBottom) lineBottom = r.bottom;
  }

  final rects = <Rect>[];
  for (var g = 0; g < groups.length; g++) {
    final group = groups[g];
    var top = group.first.top;
    var bottom = group.first.bottom;
    var rightmost = group.first;
    for (final r in group) {
      if (r.top < top) top = r.top;
      if (r.bottom > bottom) bottom = r.bottom;
      if (r.right > rightmost.right) rightmost = r;
    }
    var extend = g < groups.length - 1;
    if (!extend) {
      // The final row extends only when the selection includes the line's
      // trailing newline (or the text simply ends there).
      final probe = painter.getPositionForOffset(
        Offset(rightmost.right + 1, rightmost.center.dy),
      );
      final i = probe.offset;
      extend =
          i >= plain.length ||
          (plain[i] == '\n' && i >= selection.start && i < selection.end);
    }
    for (final r in group) {
      rects.add(
        Rect.fromLTRB(r.left, top - 0.5, extend ? rowWidth : r.right, bottom + 0.5),
      );
    }
  }
  return rects;
}

/// Paints the source field's selection highlight underneath the text. The
/// field keeps painting its own boxes too — identical colour, so the union is
/// just these gap-free rects.
class SourceSelectionHighlight extends StatelessWidget {
  const SourceSelectionHighlight({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.color,
    required this.style,
    required this.strutStyle,
    required this.softWrap,
  });

  final TextEditingController controller;
  final ScrollController scrollController;
  final Color color;

  /// Must equal the TextField's own style/strut so the mirrored layout lands
  /// on the same coordinates.
  final TextStyle style;
  final StrutStyle strutStyle;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: CustomPaint(
        painter: _SourceSelectionPainter(
          span: controller.buildTextSpan(
            context: context,
            style: style,
            withComposing: false,
          ),
          selection: controller.selection,
          color: color,
          strutStyle: strutStyle,
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
          softWrap: softWrap,
          scroll: scrollController,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SourceSelectionPainter extends CustomPainter {
  _SourceSelectionPainter({
    required this.span,
    required this.selection,
    required this.color,
    required this.strutStyle,
    required this.textScaler,
    required this.textDirection,
    required this.softWrap,
    required ScrollController scroll,
  }) : _scroll = scroll,
       super(repaint: scroll);

  final InlineSpan span;
  final TextSelection selection;
  final Color color;
  final StrutStyle strutStyle;
  final TextScaler textScaler;
  final TextDirection textDirection;
  final bool softWrap;
  final ScrollController _scroll;

  TextPainter? _painter;
  InlineSpan? _laidSpan;
  double? _laidWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (!selection.isValid || selection.isCollapsed) return;
    // In no-wrap mode the field sizes itself to its longest line; laying out
    // unbounded lands on the same coordinates, and rows then extend to that
    // longest line's width.
    final width = softWrap ? size.width : double.infinity;
    if (_painter == null ||
        !identical(_laidSpan, span) ||
        _laidWidth != width) {
      _painter =
          TextPainter(
            text: span,
            textDirection: textDirection,
            strutStyle: strutStyle,
            textScaler: textScaler,
          )..layout(maxWidth: width);
      _laidSpan = span;
      _laidWidth = width;
    }
    final rowWidth = softWrap ? size.width : _painter!.width;
    final rects = sourceSelectionRects(
      _painter!,
      selection,
      rowWidth: rowWidth,
    );
    if (rects.isEmpty) return;
    final paint = Paint()..color = color;
    canvas.save();
    canvas.translate(0, -(_scroll.hasClients ? _scroll.offset : 0.0));
    for (final rect in rects) {
      canvas.drawRect(rect, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SourceSelectionPainter oldDelegate) =>
      oldDelegate.span != span ||
      oldDelegate.selection != selection ||
      oldDelegate.color != color ||
      oldDelegate.strutStyle != strutStyle ||
      oldDelegate.textScaler != textScaler ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.softWrap != softWrap;
}
