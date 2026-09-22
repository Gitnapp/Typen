import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typen/theme.dart';
import 'package:typen/widgets/selection_highlight.dart';

void main() {
  testWidgets('preview selection boxes cover the full line height and tile', (
    tester,
  ) async {
    const text = 'line one\nline two\nline three\n';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: LineHeightText(
              TextSpan(text: text),
              strutStyle: StrutStyle(
                fontSize: 16,
                height: 1.7,
                leading: 0,
                forceStrutHeight: true,
              ),
            ),
          ),
        ),
      ),
    );

    final paragraph =
        tester.renderObject(find.byType(LineHeightRichText))
            as LineHeightParagraph;
    final boxes = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    expect(boxes.length, 3);
    // Glyph-tight boxes would be ~16px at fontSize 16; full line boxes are
    // 27.2 at height 1.7 (plus the half-pixel seam inflation).
    for (final box in boxes) {
      expect(box.toRect().height, greaterThan(26));
    }
    // Fully selected rows extend to the column width — one flush right edge.
    final rights = boxes.map((b) => b.toRect().right).toSet();
    expect(rights.length, 1);
    expect(rights.single, 800);
    // Adjacent lines' highlights overlap the seam instead of gapping.
    for (var i = 1; i < boxes.length; i++) {
      expect(boxes[i].toRect().top, lessThan(boxes[i - 1].toRect().bottom));
      expect(
        boxes[i - 1].toRect().bottom - boxes[i].toRect().top,
        lessThan(2),
      );
    }
  });

  test('selection colours are opaque so the highlight stays flat', () {
    expect(AppPalette.dark.selection.a, 1.0);
    expect(AppPalette.light.selection.a, 1.0);
  });

  testWidgets('mixed font sizes on one line paint one flat band', (
    tester,
  ) async {
    const text = 'body code rest\nnext line\n';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: LineHeightText(
              TextSpan(
                style: TextStyle(fontSize: 16, height: 1.7),
                children: [
                  TextSpan(text: 'body '),
                  TextSpan(text: 'code', style: TextStyle(fontSize: 14)),
                  TextSpan(text: ' rest\nnext line\n'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final paragraph =
        tester.renderObject(find.byType(LineHeightRichText))
            as LineHeightParagraph;
    final boxes = paragraph
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: text.length),
        )
        .map((b) => b.toRect())
        .toList();

    // Line 0 holds three runs (16px / 14px / 16px); unsnapped, the 14px run's
    // box would be shorter. All boxes on the line share one vertical extent.
    final line0 = boxes.take(3).toList();
    for (final rect in line0) {
      expect(rect.top, closeTo(line0.first.top, 0.01));
      expect(rect.bottom, closeTo(line0.first.bottom, 0.01));
    }
    // And the two lines overlap the seam instead of leaving a gap.
    expect(boxes[3].top, lessThan(line0.first.bottom));
  });

  test('source selection rects: full-width rows, seams overlapped', () {
    const rowWidth = 800.0;
    TextPainter buildPainter() => TextPainter(
      text: const TextSpan(
        style: TextStyle(fontSize: 16, height: 1.6),
        children: [
          TextSpan(text: 'body '),
          TextSpan(text: 'code', style: TextStyle(fontSize: 14)),
          TextSpan(text: ' line\n\nsecond line\nthi'),
        ],
      ),
      textDirection: TextDirection.ltr,
      strutStyle: const StrutStyle(
        fontSize: 16,
        height: 1.6,
        leadingDistribution: TextLeadingDistribution.even,
      ),
    )..layout(maxWidth: rowWidth);

    // Full selection: every row extends to the row width, bands overlap.
    final painter = buildPainter();
    final text = (painter.text as TextSpan).toPlainText();
    final rects = sourceSelectionRects(
      painter,
      TextSelection(baseOffset: 0, extentOffset: text.length),
      rowWidth: rowWidth,
    );
    expect(rects, isNotEmpty);
    for (final rect in rects) {
      expect(rect.right, rowWidth);
    }
    final bands = rects.map((r) => r.top).toSet().toList()..sort();
    expect(bands.length, 4);
    final pitch = bands[1] - bands[0];
    for (var i = 2; i < bands.length; i++) {
      expect(bands[i] - bands[i - 1], closeTo(pitch, 0.01));
    }
    final heights = rects.map((r) => r.height).toSet();
    expect(heights.length, 1);
    expect(heights.single, greaterThan(pitch));

    // Selection ending mid-line: earlier rows extend, the last row hugs.
    final partial = sourceSelectionRects(
      buildPainter(),
      const TextSelection(baseOffset: 0, extentOffset: 19),
      rowWidth: rowWidth,
    );
    final lastTop = partial.map((r) => r.top).reduce((a, b) => a > b ? a : b);
    final lastRow = partial.where((r) => r.top == lastTop);
    for (final rect in lastRow) {
      expect(rect.right, lessThan(rowWidth));
    }
    final earlier = partial.where((r) => r.top < lastTop);
    for (final rect in earlier) {
      expect(rect.right, rowWidth);
    }
  });
}
