import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../store.dart';
import '../theme.dart';
import 'markdown_highlighter.dart';

enum EditorMode { source, preview }

/// Whether [text] already ends on a blank line — the buffer either is empty
/// or its last byte is the newline that starts that blank line. An empty
/// document counts too: there is nothing to append a line after.
bool hasTrailingBlankLine(String text) => text.isEmpty || text.endsWith('\n');

/// A source editor scroll position with one extra line after Flutter's own
/// editable-text extent. The buffer stays byte-faithful; the space is viewport
/// geometry rather than a synthetic newline in [TextEditingController.text].
class SourceScrollController extends ScrollController {
  SourceScrollController({required this.trailingExtent});

  final ValueGetter<double> trailingExtent;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SourceScrollPosition(
    physics: physics,
    context: context,
    trailingExtent: trailingExtent,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}

class _SourceScrollPosition extends ScrollPositionWithSingleContext {
  _SourceScrollPosition({
    required super.physics,
    required super.context,
    required this.trailingExtent,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  final ValueGetter<double> trailingExtent;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final trailing = math.max(0.0, trailingExtent());
    return super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent + trailing,
    );
  }
}

/// The editable buffer is plain Markdown text and nothing else. [preview] is
/// strictly a renderer — it has no path back to the buffer or to disk, which
/// is what makes "the file you opened is the file you save" structurally true
/// rather than something that has to be tested for.
class EditorPane extends StatelessWidget {
  const EditorPane({
    super.key,
    required this.controller,
    required this.undoController,
    required this.focusNode,
    required this.scrollController,
    required this.previewScrollController,
    required this.previewFocusNode,
    required this.mode,
    required this.settings,
    required this.documentDir,
  });

  final MarkdownHighlightingController controller;
  final UndoHistoryController undoController;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final ScrollController previewScrollController;
  final FocusNode previewFocusNode;
  final EditorMode mode;
  final Settings settings;
  final String? documentDir;

  /// Identifies the source field's element across a soft-wrap toggle, which
  /// swaps whether it sits directly under [Offstage] or inside an extra
  /// horizontal [SingleChildScrollView]. Without it that swap looks like a
  /// different widget to Flutter, which tears down the old element and
  /// mounts a new one in the same frame — briefly leaving [scrollController]
  /// attached to both and tripping "attached to multiple scroll views".
  /// A GlobalKey instead makes Flutter move the existing element (and its
  /// live scroll attachment) to its new parent.
  static final _sourceFieldKey = GlobalKey(debugLabel: 'sourceField');

  static const monoFamily = 'Menlo';
  static const sourceBottomSpaceKey = ValueKey('source-bottom-space');

  /// Smallest gap between the text and the window edge, used once the window
  /// is too narrow to reach the configured column width.
  static const _minSideInset = 40.0;

  double get _sourceLineExtent => settings.fontSize * 1.6;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    controller.config = HighlightConfig(
      palette: palette,
      fontSize: settings.fontSize,
      monoFamily: monoFamily,
      proportional: settings.proportionalEditorFont,
    );

    return Container(
      color: palette.surface0,
      // The scroll viewport spans the whole window so its scrollbar rides the
      // window edge; the reading column is produced by insetting the *content*
      // instead of narrowing the viewport.
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The user's indent, but never so wide on a narrow window that the
          // text is squeezed into nothing — leave a readable column no matter
          // how the two are combined.
          final side = math.min(
            settings.indent,
            math.max(_minSideInset, (constraints.maxWidth - 240) / 2),
          );
          // The source field stays mounted while previewing so its undo stack,
          // selection and scroll position survive a mode switch. The preview
          // is only built when it is actually on screen — re-parsing Markdown
          // on every keystroke would be pure waste.
          return Stack(
            children: [
              Offstage(
                offstage: mode != EditorMode.source,
                child: _buildSource(palette, side, constraints.maxWidth),
              ),
              // Fills the Stack rather than wrapping its content: the
              // viewport has to span the window so the scrollbar rides the
              // window edge, the way the source view's does.
              if (mode == EditorMode.preview)
                Positioned.fill(child: _buildPreview(context, palette, side)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSource(AppPalette palette, double side, double viewportWidth) {
    if (settings.softWrap) return _sourceField(palette, side);
    // Wrapping off: the field has to be free to run past the viewport, so it
    // sits in a horizontal scroller and takes the width of its longest line
    // (never less than the viewport, or short documents would shrink the
    // editable area to a sliver).
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: viewportWidth),
        child: IntrinsicWidth(child: _sourceField(palette, side)),
      ),
    );
  }

  Widget _sourceField(AppPalette palette, double side) {
    // The field fills the pane edge to edge: the scrollbar then rides the
    // window edge with a thumb track exactly as tall as the viewport, and the
    // horizontal inset sits *inside* the field, where it moves the text
    // without narrowing that viewport.
    return Scrollbar(
      key: _sourceFieldKey,
      controller: scrollController,
      child: ScrollConfiguration(
        // TextField forces a scrollbar of its own on every multi-line field
        // and exposes no way to turn it off — but it asks the ambient
        // behaviour to build it, so a behaviour that builds nothing wins.
        behavior: const _NoScrollbarBehavior(),
        // Rebuilds just the field when the selection moves, so the caret
        // picks up `headingScaleAt` the moment it lands on a different line
        // — a plain build-time read would only refresh on unrelated rebuilds.
        child: Stack(
          children: [
            // Rebuilds just the field when the selection moves, so the caret
            // picks up `headingScaleAt` the moment it lands on a different line.
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => TextField(
                controller: controller,
                undoController: undoController,
                focusNode: focusNode,
                scrollController: scrollController,
                // Ambient physics on macOS is BouncingScrollPhysics, which lets
                // `pixels` sit outside [min, max] and makes the thumb flicker.
                scrollPhysics: const ClampingScrollPhysics(),
                scrollPadding: const EdgeInsets.symmetric(vertical: 80),
                maxLines: null,
                expands: true,
                autofocus: true,
                cursorColor: palette.gold,
                cursorWidth: 2,
                cursorHeight:
                    settings.fontSize *
                    controller.headingScaleAt(controller.selection.baseOffset) *
                    1.2,
                // A non-forced strut supplies the first rich-text line with
                // the same baseline/leading contract as every later line. H1
                // spans may still grow beyond it; they are no longer clipped
                // against the smaller root TextField metrics at y=0.
                strutStyle: StrutStyle(
                  fontFamily: settings.proportionalEditorFont
                      ? null
                      : monoFamily,
                  fontSize: settings.fontSize,
                  height: 1.6,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
                // The controller supplies every span's style; this only sets
                // the metrics the field uses for an empty buffer and caret.
                style: TextStyle(
                  color: palette.textPrimary,
                  fontFamily: settings.proportionalEditorFont
                      ? null
                      : monoFamily,
                  fontSize: settings.fontSize,
                  height: 1.6,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.fromLTRB(side, 24, side, 0),
                ),
              ),
            ),
            ListenableBuilder(
              // The buffer already ending on a blank line makes this space
              // redundant — that line *is* the room to click into — so this
              // has to redraw on every keystroke, not just every scroll.
              listenable: Listenable.merge([scrollController, controller]),
              builder: (context, _) {
                if (hasTrailingBlankLine(controller.text)) {
                  return const SizedBox.shrink();
                }
                final atBottom =
                    scrollController.hasClients &&
                    scrollController.position.hasContentDimensions &&
                    scrollController.position.extentAfter <= 0.5;
                if (!atBottom) return const SizedBox.shrink();
                return Positioned(
                  left: side,
                  right: side,
                  bottom: 0,
                  height: _sourceLineExtent,
                  child: Semantics(
                    button: true,
                    label: '在文末新起一行',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.text,
                      child: GestureDetector(
                        key: sourceBottomSpaceKey,
                        behavior: HitTestBehavior.opaque,
                        onTap: _appendLineFromBottomSpace,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _appendLineFromBottomSpace() {
    final text = '${controller.text}\n';
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    });
  }

  /// YAML front matter is metadata, not prose — Markdown renderers do not
  /// know that and would show it as a stray heading. Dropped for display
  /// only; the buffer keeps every byte.
  static String stripFrontMatter(String text) {
    if (!text.startsWith('---')) return text;
    final lines = text.split('\n');
    if (lines.first.trimRight() != '---') return text;
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trimRight();
      if (line == '---' || line == '...') {
        return lines.skip(i + 1).join('\n').trimLeft();
      }
    }
    return text;
  }

  Widget _buildPreview(BuildContext context, AppPalette palette, double side) {
    // The preview's ListView gets no scrollbar of its own on desktop — it has
    // no controller to hang one on, and MaterialApp only installs a
    // PrimaryScrollController on mobile. Driving it explicitly gives the
    // preview a scrollbar at the same window edge as the source view, and
    // keeps its scroll position across mode switches.
    // Arrow and page keys reach a scroll view via ScrollAction, which looks
    // *upwards* from whatever holds focus — first for an enclosing Scrollable,
    // then for a PrimaryScrollController. The focus node sits above the list,
    // so only the second route can work: hence the controller above the focus.
    // Without this the preview is mouse-only.
    return PrimaryScrollController(
      controller: previewScrollController,
      child: Focus(
        focusNode: previewFocusNode,
        child: Scrollbar(
          controller: previewScrollController,
          child: ScrollConfiguration(
            behavior: const _NoScrollbarBehavior(),
            // `Markdown` (the scrolling widget) lays its blocks out in a
            // ListView, which is sliver-backed: Flutter only lays out items
            // near the viewport and *estimates* maxScrollExtent from the
            // average extent-so-far until every child has been measured. On
            // content with uneven block heights (headings, code blocks,
            // lists) that estimate visibly changes as you scroll — which is
            // what made the Scrollbar's thumb resize while scrolling.
            // MarkdownBody lays every block out in a plain Column instead —
            // no lazy layout, no estimate, exact height once — wrapped in
            // our own SingleChildScrollView for a maxScrollExtent that's
            // constant from the first frame.
            //
            // flutter_markdown_plus's own `selectable: true` gives every
            // block its own independent SelectableText, so a drag never
            // crosses a block boundary. SelectionArea instead makes every
            // Text.rich it wraps share one continuous selection — which
            // needs `selectable: false` here so the package doesn't wrap
            // things in its own SelectableText too.
            child: SelectionArea(
              child: SingleChildScrollView(
                controller: previewScrollController,
                padding: EdgeInsets.fromLTRB(side, 24, side, 60),
                child: MarkdownBody(
                  data: stripFrontMatter(controller.text),
                  selectable: false,
                  extensionSet: md.ExtensionSet.gitHubWeb,
                  styleSheet: _styleSheet(palette),
                  imageBuilder: _buildImage,
                  onTapLink: (text, href, title) => _openLink(href),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Resolves relative image paths against the document's own directory, the
  /// way every other Markdown tool does.
  Widget _buildImage(Uri uri, String? title, String? alt) {
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return Image.network(uri.toString(), errorBuilder: _imageError);
    }
    final raw = Uri.decodeFull(uri.path);
    final resolved = p.isAbsolute(raw)
        ? raw
        : (documentDir == null ? raw : p.normalize(p.join(documentDir!, raw)));
    if (!File(resolved).existsSync()) {
      return _imageError(null, alt ?? raw, null);
    }
    return Image.file(File(resolved), errorBuilder: _imageError);
  }

  Widget _imageError(BuildContext? context, Object error, StackTrace? _) =>
      Builder(
        builder: (ctx) => Text(
          '⃠ $error',
          style: TextStyle(color: ctx.palette.textMuted, fontSize: 12),
        ),
      );

  Future<void> _openLink(String? href) async {
    if (href == null || href.isEmpty) return;
    try {
      await Process.run('open', [href]);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: href));
    }
  }

  MarkdownStyleSheet _styleSheet(AppPalette p) {
    final size = settings.fontSize;
    final body = TextStyle(
      color: p.textPrimary,
      fontSize: size + 1,
      height: 1.7,
      leadingDistribution: TextLeadingDistribution.even,
    );
    TextStyle heading(double scale, FontWeight weight) => TextStyle(
      color: p.textPrimary,
      fontSize: (size + 1) * scale,
      fontWeight: weight,
      height: 1.3,
      leadingDistribution: TextLeadingDistribution.even,
    );

    return MarkdownStyleSheet(
      p: body,
      pPadding: const EdgeInsets.only(bottom: 10),
      a: TextStyle(color: p.gold, decoration: TextDecoration.underline),
      em: const TextStyle(fontStyle: FontStyle.italic),
      strong: const TextStyle(fontWeight: FontWeight.w700),
      del: TextStyle(
        decoration: TextDecoration.lineThrough,
        color: p.textMuted,
      ),
      h1: heading(1.85, FontWeight.w700),
      h2: heading(1.45, FontWeight.w700),
      h3: heading(1.2, FontWeight.w600),
      h4: heading(1.05, FontWeight.w600),
      h5: heading(1.0, FontWeight.w600),
      h6: heading(0.95, FontWeight.w600),
      h1Padding: const EdgeInsets.only(top: 26, bottom: 10),
      h2Padding: const EdgeInsets.only(top: 22, bottom: 9),
      h3Padding: const EdgeInsets.only(top: 18, bottom: 7),
      h4Padding: const EdgeInsets.only(top: 14, bottom: 6),
      code: TextStyle(
        fontFamily: monoFamily,
        fontSize: size * 0.9,
        color: p.emerald,
        backgroundColor: p.surface2,
      ),
      codeblockPadding: const EdgeInsets.all(14),
      codeblockDecoration: BoxDecoration(
        color: p.surface1,
        borderRadius: BorderRadius.circular(kRadiusControl),
        border: Border.all(color: p.border),
      ),
      blockquote: TextStyle(
        color: p.textSecondary,
        fontSize: size + 1,
        height: 1.7,
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: p.gold, width: 3)),
      ),
      listBullet: body,
      listIndent: 22,
      blockSpacing: 10,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.border, width: 1)),
      ),
      tableHead: TextStyle(
        color: p.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: size,
      ),
      tableBody: TextStyle(color: p.textPrimary, fontSize: size),
      tableBorder: TableBorder.all(color: p.border),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      tableHeadCellsDecoration: BoxDecoration(color: p.surface1),
      checkbox: TextStyle(color: p.gold, fontSize: size),
    );
  }
}

/// Builds no scrollbar at all.
///
/// [TextField] hard-codes `scrollbars: _isMultiline` when it copies the
/// ambient behaviour, so the usual `copyWith(scrollbars: false)` is ignored —
/// but the copy still delegates the actual construction here, which lets the
/// pane draw one scrollbar of its own at the window edge instead.
class _NoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
