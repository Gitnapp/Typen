// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui show BoxHeightStyle, BoxWidthStyle, TextBox;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A `Text.rich` replacement whose selection highlight covers the full line
/// height instead of hugging the glyphs.
///
/// Under a [SelectionArea], a paragraph's selection is painted by
/// `_SelectableFragment.paintSelection`, which calls
/// `RenderParagraph.getBoxesForSelection` with the default
/// [ui.BoxHeightStyle.tight] — there is no public knob for it. The only seam
/// that reaches that call is the render object itself, which is what
/// [LineHeightParagraph] provides: every selection-box request is answered
/// with [ui.BoxHeightStyle.max], so a selected line is highlighted from line
/// top to line bottom and adjacent selected lines tile into one flat block
/// (the Xcode/Typora look).
///
/// The widget side mirrors the registrar path of `Text.build`
/// (`_SelectableTextContainer` + `_RichText`, both private): one nested
/// [SelectionContainer] with a [StaticSelectionContainerDelegate] per text
/// block, and a [RichText] registering with the ambient registrar. Known
/// delta from stock `Text.rich`: MediaQuery's lineHeightScaleFactor and
/// letter/word-spacing overrides are not re-applied (this app never sets
/// them).
class LineHeightText extends StatelessWidget {
  const LineHeightText(
    this.text, {
    super.key,
    this.textAlign = TextAlign.start,
    this.textScaler,
    this.strutStyle,
  });

  final TextSpan text;
  final TextAlign textAlign;
  final TextScaler? textScaler;
  final StrutStyle? strutStyle;

  @override
  Widget build(BuildContext context) {
    final DefaultTextStyle defaultTextStyle = DefaultTextStyle.of(context);
    TextStyle effectiveTextStyle = defaultTextStyle.style;
    if (MediaQuery.boldTextOf(context)) {
      effectiveTextStyle = effectiveTextStyle.merge(
        const TextStyle(fontWeight: FontWeight.bold),
      );
    }
    final TextSpan effectiveTextSpan = TextSpan(
      style: effectiveTextStyle,
      children: <InlineSpan>[text],
    );
    final TextScaler effectiveTextScaler =
        textScaler ?? MediaQuery.textScalerOf(context);
    final Color selectionColor =
        DefaultSelectionStyle.of(context).selectionColor ??
        DefaultSelectionStyle.defaultColor;
    if (SelectionContainer.maybeOf(context) == null) {
      return LineHeightRichText(
        text: effectiveTextSpan,
        textAlign: textAlign,
        textScaler: effectiveTextScaler,
        strutStyle: strutStyle,
        selectionColor: selectionColor,
      );
    }
    return MouseRegion(
      cursor:
          DefaultSelectionStyle.of(context).mouseCursor ??
          SystemMouseCursors.text,
      child: _LineHeightSelectableContainer(
        text: effectiveTextSpan,
        textAlign: textAlign,
        textScaler: effectiveTextScaler,
        strutStyle: strutStyle,
        selectionColor: selectionColor,
      ),
    );
  }
}

/// Mirrors `_SelectableTextContainer`: gives the block its own selection
/// delegate so it behaves as one selectable unit inside the shared
/// [SelectionArea]. Uses the public [StaticSelectionContainerDelegate]; the
/// stock text widget's private subclass only adds select-paragraph and
/// widget-span ordering polish on top of it.
class _LineHeightSelectableContainer extends StatefulWidget {
  const _LineHeightSelectableContainer({
    required this.text,
    required this.textAlign,
    required this.textScaler,
    required this.strutStyle,
    required this.selectionColor,
  });

  final TextSpan text;
  final TextAlign textAlign;
  final TextScaler textScaler;
  final StrutStyle? strutStyle;
  final Color selectionColor;

  @override
  State<_LineHeightSelectableContainer> createState() =>
      _LineHeightSelectableContainerState();
}

class _LineHeightSelectableContainerState
    extends State<_LineHeightSelectableContainer> {
  late final StaticSelectionContainerDelegate _selectionDelegate =
      StaticSelectionContainerDelegate();
  final GlobalKey _textKey = GlobalKey();

  @override
  void dispose() {
    _selectionDelegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionContainer(
      delegate: _selectionDelegate,
      child: LineHeightRichText(
        key: _textKey,
        text: widget.text,
        textAlign: widget.textAlign,
        textScaler: widget.textScaler,
        strutStyle: widget.strutStyle,
        selectionRegistrar: SelectionContainer.maybeOf(context),
        selectionColor: widget.selectionColor,
      ),
    );
  }
}

/// A [RichText] that lays out with [LineHeightParagraph]. Only
/// [createRenderObject] differs from stock; the inherited
/// `updateRenderObject` keeps every other property in sync because all of
/// them arrive as ordinary [RichText] constructor fields.
class LineHeightRichText extends RichText {
  LineHeightRichText({
    super.key,
    required super.text,
    super.textAlign,
    super.textDirection,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.locale,
    super.strutStyle,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionRegistrar,
    super.selectionColor,
  });

  @override
  RenderParagraph createRenderObject(BuildContext context) {
    assert(textDirection != null || debugCheckHasDirectionality(context));
    return LineHeightParagraph(
      text,
      textAlign: textAlign,
      textDirection: textDirection ?? Directionality.of(context),
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      locale: locale ?? Localizations.maybeLocaleOf(context),
      registrar: selectionRegistrar,
      selectionColor: selectionColor,
      devicePixelRatio:
          MediaQuery.maybeDevicePixelRatioOf(context) ??
          View.maybeOf(context)?.devicePixelRatio ??
          1.0,
    );
  }
}

/// A [RenderParagraph] that reports full-line selection boxes no matter what
/// the caller requests, so highlights tile seamlessly across lines instead of
/// striping at glyph height.
class LineHeightParagraph extends RenderParagraph {
  LineHeightParagraph(
    super.text, {
    required super.textAlign,
    required super.textDirection,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.locale,
    super.strutStyle,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.registrar,
    super.selectionColor,
    super.devicePixelRatio,
  });

  /// Boxes come from [ui.BoxHeightStyle.max] — the full line box, tiling
  /// seamlessly across lines — then get three corrections:
  ///
  ///  * Vertical union per line: runs of differing font metrics on one line
  ///    (inline code next to prose) produce baseline-aligned boxes of
  ///    different heights, which would paint as teeth along the selection's
  ///    edge. Boxes arrive in text order, so a new line starts at the first
  ///    box whose top clears the running line's bottom.
  ///  * Half-pixel vertical inflation: metric-driven boxes leave sub-pixel
  ///    seams between lines (line heights are pixel-rounded, the boxes
  ///    aren't), which rasterise as dark hairlines at fractional screen
  ///    scales. With the opaque selection colour the overlap is invisible.
  ///  * Rows the selection swallows whole extend to the paragraph's full
  ///    width; the final, partially selected row keeps hugging the text.
  @override
  List<ui.TextBox> getBoxesForSelection(
    TextSelection selection, {
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
    ui.BoxWidthStyle boxWidthStyle = ui.BoxWidthStyle.tight,
  }) {
    final boxes = super.getBoxesForSelection(
      selection,
      boxHeightStyle: ui.BoxHeightStyle.max,
      boxWidthStyle: boxWidthStyle,
    );
    if (boxes.isEmpty) return boxes;
    final plain = text.toPlainText();

    final groups = <List<ui.TextBox>>[];
    var lineBottom = double.negativeInfinity;
    for (final box in boxes) {
      final r = box.toRect();
      if (groups.isNotEmpty && r.top >= lineBottom - 0.5) {
        groups.add(<ui.TextBox>[]);
        lineBottom = double.negativeInfinity;
      }
      if (groups.isEmpty) groups.add(<ui.TextBox>[]);
      groups.last.add(box);
      if (r.bottom > lineBottom) lineBottom = r.bottom;
    }

    final snapped = <ui.TextBox>[];
    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      var top = group.first.toRect().top;
      var bottom = group.first.toRect().bottom;
      var rightmost = group.first.toRect();
      for (final box in group) {
        final r = box.toRect();
        if (r.top < top) top = r.top;
        if (r.bottom > bottom) bottom = r.bottom;
        if (r.right > rightmost.right) rightmost = r;
      }
      var extend = g < groups.length - 1;
      if (!extend) {
        // The final row extends only when the selection swallows the line's
        // trailing newline (or reaches past the block's own text).
        final probe = getPositionForOffset(
          Offset(rightmost.right + 1, rightmost.center.dy),
        );
        final i = probe.offset;
        extend =
            i >= plain.length ||
            (plain[i] == '\n' && i >= selection.start && i < selection.end);
      }
      // Blocks shrink-wrap to their text, so size.width *is* the text width —
      // useless. The layout constraint carries the column width instead (the
      // fenced-code block's horizontal scroller gets an unbounded constraint
      // and falls back to hugging its longest line).
      final rowRight = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : size.width;
      for (final box in group) {
        final r = box.toRect();
        snapped.add(
          ui.TextBox.fromLTRBD(
            r.left,
            top - 0.5,
            extend ? rowRight : r.right,
            bottom + 0.5,
            box.direction,
          ),
        );
      }
    }
    return snapped;
  }
}
