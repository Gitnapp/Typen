import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typen/find.dart';
import 'package:typen/theme.dart';
import 'package:typen/widgets/find_bar.dart';

void main() {
  const text = 'The cat sat on the mat.\nThe CAT came back.\n';

  test('literal search is case-insensitive by default', () {
    final find = FindController()..update(text, query: 'cat');
    expect(find.matches.length, 2);
    expect(text.substring(find.matches[1].start, find.matches[1].end), 'CAT');
  });

  test('case sensitivity narrows the hits', () {
    final find = FindController()
      ..update(text, query: 'cat', caseSensitive: true);
    expect(find.matches.length, 1);
  });

  test('stepping wraps in both directions', () {
    // "The" x2 plus the lowercase "the" in "on the mat".
    final find = FindController()..update(text, query: 'The');
    expect(find.matches.length, 3);
    expect(find.current, 0);
    find.step(1);
    expect(find.current, 1);
    find.step(1);
    expect(find.current, 2);
    find.step(1);
    expect(find.current, 0);
    find.step(-1);
    expect(find.current, 2);
  });

  test('the anchor selects the next hit after the caret', () {
    final find = FindController()..update(text, query: 'The', anchor: 24);
    expect(find.current, 2);
    expect(find.matches[2].start, greaterThanOrEqualTo(24));
  });

  test('regex mode works and zero-width matches are dropped', () {
    final find = FindController()
      ..update(text, query: r'\bm\w+', useRegex: true);
    expect(find.matches.length, 1);
    expect(text.substring(find.matches[0].start, find.matches[0].end), 'mat');

    find.update(text, query: r'x*');
    expect(find.matches, isEmpty);
  });

  test('an invalid pattern reports instead of throwing', () {
    final find = FindController()..update(text, query: '[unclosed', useRegex: true);
    expect(find.badPattern, isTrue);
    expect(find.matches, isEmpty);
  });

  test('replace current only touches the current hit', () {
    final find = FindController()..update(text, query: 'The');
    find.replacement = 'A';
    final (out, caret) = find.replaceCurrent(text)!;
    expect(out, 'A cat sat on the mat.\nThe CAT came back.\n');
    expect(caret, 1);
  });

  test('replace all applies back-to-front so ranges stay valid', () {
    final find = FindController()..update(text, query: 'The');
    find.replacement = 'Some';
    final (out, _) = find.replaceAll(text)!;
    expect(out, 'Some cat sat on Some mat.\nSome CAT came back.\n');
  });

  test('replacing with a longer string does not corrupt later hits', () {
    const src = 'a a a';
    final find = FindController()..update(src, query: 'a');
    find.replacement = 'bbb';
    final (out, _) = find.replaceAll(src)!;
    expect(out, 'bbb bbb bbb');
  });

  test('an empty query clears everything', () {
    final find = FindController()..update(text, query: 'cat');
    find.update(text, query: '');
    expect(find.matches, isEmpty);
    expect(find.current, -1);
  });

  testWidgets('find toolbar buttons use the shared compact geometry',
      (tester) async {
    final controller = FindController();
    final query = TextEditingController();
    final replacement = TextEditingController();
    final queryFocus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(query.dispose);
    addTearDown(replacement.dispose);
    addTearDown(queryFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppPalette.light),
        home: Material(
          child: FindBar(
            controller: controller,
            queryFocus: queryFocus,
            queryController: query,
            replaceController: replacement,
            showReplace: true,
            onQueryChanged: (_) {},
            onToggleOption: ({caseSensitive, useRegex}) {},
            onStep: (_) {},
            onReplace: () {},
            onReplaceAll: () {},
            onToggleReplace: () {},
            onClose: () {},
          ),
        ),
      ),
    );

    for (final tooltip in [
      '替换',
      '区分大小写',
      '正则表达式',
      '上一个（⇧⌘G）',
      '下一个（⌘G）',
      '关闭（esc）',
    ]) {
      expect(
        tester.getSize(find.byTooltip(tooltip)),
        const Size(kIconControlWidth, kControlHeight),
      );
    }

    final replaceAll = find
        .ancestor(
          of: find.text('全部替换'),
          matching: find.byType(GestureDetector),
        )
        .first;
    expect(tester.getSize(replaceAll).height, kControlHeight);
  });
}
