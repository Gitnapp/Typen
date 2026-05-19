import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

enum EditorMode { wysiwyg, source }

/// Single-document editor with a WYSIWYG (appflowy_editor) mode and a raw
/// markdown source mode. Content is centered with a max reading-width column
/// (Typora-style).
class EditorPane extends StatefulWidget {
  const EditorPane({
    super.key,
    required this.initialContent,
    required this.onChanged,
    this.mode = EditorMode.wysiwyg,
  });

  final String initialContent;
  final EditorMode mode;
  final ValueChanged<String> onChanged;

  @override
  State<EditorPane> createState() => EditorPaneState();
}

class EditorPaneState extends State<EditorPane> {
  /// Width of the centered content column.
  /// 760 ≈ 65–75 characters at 16px — the line-length sweet spot the major
  /// markdown editors all converge on (Typora 640–860, iA Writer 66ch, GitHub
  /// uncapped, Obsidian 700).
  static const double _columnWidth = 760;

  EditorState? _editorState;
  StreamSubscription<EditorTransactionValue>? _txSub;
  final TextEditingController _sourceCtl = TextEditingController();
  final ScrollController _sourceScroll = ScrollController();

  String _markdown = '';
  late EditorMode _mode;

  @override
  void initState() {
    super.initState();
    _markdown = widget.initialContent;
    _mode = widget.mode;
    if (_mode == EditorMode.wysiwyg) {
      _buildEditorState(_markdown);
    } else {
      _sourceCtl.text = _markdown;
    }
  }

  @override
  void dispose() {
    _txSub?.cancel();
    _editorState?.dispose();
    _sourceCtl.dispose();
    _sourceScroll.dispose();
    super.dispose();
  }

  // ─── External API ─────────────────────────────────────────────────────────
  EditorMode get mode => _mode;

  void switchMode(EditorMode next) {
    if (next == _mode) return;
    if (_mode == EditorMode.wysiwyg) {
      final fromEditor = _editorState != null
          ? documentToMarkdown(_editorState!.document).trimRight()
          : _markdown;
      _markdown = fromEditor;
    } else {
      _markdown = _sourceCtl.text;
    }
    setState(() {
      _mode = next;
      if (next == EditorMode.wysiwyg) {
        _buildEditorState(_markdown);
      } else {
        _sourceCtl.text = _markdown;
      }
    });
  }

  void _buildEditorState(String content) {
    _txSub?.cancel();
    _editorState?.dispose();
    final document = content.trim().isEmpty
        ? Document.blank(withInitialText: true)
        : markdownToDocument(content);
    final state = EditorState(document: document);
    state.logConfiguration.level = AppFlowyEditorLogLevel.off;
    _txSub = state.transactionStream.listen((_) => _onEditorChanged());
    _editorState = state;
  }

  void _onEditorChanged() {
    if (!mounted || _editorState == null) return;
    final next = documentToMarkdown(_editorState!.document).trimRight();
    if (next == _markdown) return;
    _markdown = next;
    widget.onChanged(_markdown);
  }

  void _onSourceChanged(String value) {
    if (value == _markdown) return;
    _markdown = value;
    widget.onChanged(_markdown);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface0,
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _columnWidth),
        child: _mode == EditorMode.wysiwyg
            ? _buildWysiwyg()
            : _buildSource(),
      ),
    );
  }

  Widget _buildWysiwyg() {
    // IMPORTANT: in appflowy_editor 6.x, EditorStyle.padding is applied to
    // EACH block (see page_block_component.dart:124-130). So vertical padding
    // here multiplies with the number of blocks — using e.g. vertical: 24
    // would add 24+24=48px of dead space per paragraph. Horizontal only.
    // Top/bottom whitespace is added via [header]/[footer] of AppFlowyEditor.
    final style = EditorStyle.desktop(
      cursorColor: AppColors.gold,
      selectionColor: AppColors.gold.withValues(alpha: 0.26),
      padding: const EdgeInsets.symmetric(horizontal: 40),
      textStyleConfiguration: TextStyleConfiguration(
        // The two competing constraints:
        //   1. cursor height (= getFullHeightForCaret) must match the
        //      visible line box (= selection rect height)
        //   2. visible glyph should sit symmetrically inside that box
        //
        // The library doesn't expose AppFlowyRichText.cursorHeight, so we
        // can't override the caret height directly. The only config that
        // satisfies BOTH constraints is `lineHeight: 1.0` — no extra
        // leading anywhere, so the line box collapses to natural font
        // metrics (ascent + descent ≈ fontSize), which is exactly what
        // the caret rect is. applyHeight*/leadingDistribution become
        // moot when there's no leading to distribute.
        //
        // Tradeoff: when a single paragraph wraps to >1 line, the lines
        // touch (no inter-line space). For typical markdown writing
        // paragraphs are short and break on `\n\n`, so this is rare;
        // inter-paragraph breathing comes from block padding below.
        lineHeight: 1.0,
        applyHeightToFirstAscent: true,
        applyHeightToLastDescent: true,
        leadingDistribution: TextLeadingDistribution.even,
        text: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
        ),
        bold: const TextStyle(fontWeight: FontWeight.w700),
        italic: const TextStyle(fontStyle: FontStyle.italic),
        underline: const TextStyle(decoration: TextDecoration.underline),
        strikethrough:
            const TextStyle(decoration: TextDecoration.lineThrough),
        href: const TextStyle(
          color: AppColors.gold,
          decoration: TextDecoration.underline,
        ),
        code: TextStyle(
          fontFamily: 'Menlo',
          fontSize: 14,
          color: AppColors.textPrimary,
          backgroundColor: AppColors.surface2,
        ),
        autoComplete: const TextStyle(color: AppColors.textMuted),
      ),
      defaultTextDirection: 'ltr',
      textSpanDecorator: null,
    );

    // Heading hierarchy: top margin > bottom margin so heading visually binds
    // to the content below it. Sizes 28/22/18/16, line-height 1.25–1.45.
    final headingBuilder = HeadingBlockComponentBuilder(
      configuration: standardBlockComponentConfiguration.copyWith(
        padding: (node) {
          final level = node.attributes[HeadingBlockKeys.level] as int? ?? 1;
          return switch (level) {
            1 => const EdgeInsets.only(top: 28, bottom: 12),
            2 => const EdgeInsets.only(top: 24, bottom: 10),
            3 => const EdgeInsets.only(top: 20, bottom: 8),
            _ => const EdgeInsets.only(top: 16, bottom: 6),
          };
        },
      ),
      // Headings use height: 1.0 for the same caret-vs-line-box parity
      // reason as body text (see TextStyleConfiguration comment above).
      // Breathing room between heading and adjacent paragraph comes from
      // block padding on the heading block (top: 28/24/20/16, bottom: 12/10/8/6).
      textStyleBuilder: (level) => switch (level) {
        1 => const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.0,
            letterSpacing: -0.4,
            color: AppColors.textPrimary,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        2 => const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.0,
            letterSpacing: -0.2,
            color: AppColors.textPrimary,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        3 => const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.0,
            color: AppColors.textPrimary,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        _ => const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.0,
            color: AppColors.textPrimary,
            leadingDistribution: TextLeadingDistribution.even,
          ),
      },
    );

    final builders = {
      ...standardBlockComponentBuilderMap,
      HeadingBlockKeys.type: headingBuilder,
      ParagraphBlockKeys.type: ParagraphBlockComponentBuilder(
        configuration: standardBlockComponentConfiguration.copyWith(
          // Inter-paragraph breathing room is delivered entirely by block
          // padding here, since lineHeight: 1.0 leaves no leading inside
          // the line itself. ~12px gives the same vertical rhythm a 1.5
          // line-height would produce, without any leading mismatch.
          padding: (_) => const EdgeInsets.only(bottom: 12),
          // Empty paragraphs need a glyph in the placeholder track or the
          // line box collapses below the cursor height. A single space is
          // invisible but anchors the metrics; placeholderTextStyle mirrors
          // the body style (height: 1.0) so empty lines match populated ones.
          placeholderText: (_) => ' ',
          placeholderTextStyle: (_, {textSpan}) => const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            height: 1.0,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
      ),
    };

    return AppFlowyEditor(
      editorState: _editorState!,
      editorStyle: style,
      blockComponentBuilders: builders,
      shrinkWrap: false,
      editable: true,
      autoFocus: true,
      // Top/bottom breathing room as scrollable header/footer rather than
      // per-block padding (see comment on EditorStyle.padding above).
      header: const SizedBox(height: 24),
      footer: const SizedBox(height: 80),
    );
  }

  Widget _buildSource() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 80),
      child: Scrollbar(
        controller: _sourceScroll,
        child: SingleChildScrollView(
          controller: _sourceScroll,
          child: TextField(
            controller: _sourceCtl,
            maxLines: null,
            autofocus: true,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Menlo',
              fontSize: 13.5,
              height: 1.5,
              leadingDistribution: TextLeadingDistribution.even,
            ),
            cursorColor: AppColors.gold,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              hintText: '# Markdown 源码…',
              hintStyle: TextStyle(color: AppColors.textMuted),
            ),
            onChanged: _onSourceChanged,
          ),
        ),
      ),
    );
  }
}
