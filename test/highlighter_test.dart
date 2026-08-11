import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typen/theme.dart';
import 'package:typen/widgets/markdown_highlighter.dart';

const _sample = '''---
title: Front matter
---

# Heading one

Some **bold**, some *italic*, `inline code`, a [link](https://a.com) and an
![image](./a.png).

> a quote
> > nested

- [ ] todo
- [x] done
  - nested bullet

1. first
2. second

```dart
void main() => print('hi');
```

    indented code

| a | b |
|---|---|
| 1 | 2 |

***

中文段落，含标点。Emoji 🎉 and ~~struck~~ text.
''';

Future<TextSpan> spanFor(
  WidgetTester tester,
  MarkdownHighlightingController controller, {
  bool withComposing = false,
}) async {
  late TextSpan span;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          span = controller.buildTextSpan(
            context: context,
            style: const TextStyle(),
            withComposing: withComposing,
          );
          return const SizedBox();
        },
      ),
    ),
  );
  return span;
}

MarkdownHighlightingController make(String text) =>
    MarkdownHighlightingController(
      text: text,
      config: const HighlightConfig(
        palette: AppPalette.dark,
        fontSize: 15,
        monoFamily: 'Menlo',
        proportional: false,
      ),
    );

void main() {
  testWidgets('highlighting never alters a single character', (tester) async {
    final controller = make(_sample);
    final span = await spanFor(tester, controller);
    // The invariant that makes styling safe: what is painted is exactly the
    // buffer, so no amount of highlighting can corrupt a document.
    expect(span.toPlainText(), equals(_sample));
  });

  testWidgets('holds for adversarial inputs too', (tester) async {
    for (final text in [
      '',
      '\n',
      '\n\n\n',
      '#',
      '# ',
      '```',
      '```\nunclosed',
      '---',
      '---\nnot front matter',
      '*',
      '**',
      '`',
      '[](',
      '![](',
      'a' * 5000,
      '中' * 500,
      '\t\t- tabbed',
      '> ' * 50,
      '|||||',
    ]) {
      final span = await spanFor(tester, make(text));
      expect(span.toPlainText(), equals(text), reason: 'broke on ${text.length} chars');
    }
  });

  testWidgets('find-match overlay preserves the text as well', (tester) async {
    final controller = make(_sample);
    controller.setMatches(
      const [
        TextRange(start: 0, end: 3),
        TextRange(start: 40, end: 47),
        TextRange(start: 100, end: 104),
      ],
      1,
    );
    final span = await spanFor(tester, controller);
    expect(span.toPlainText(), equals(_sample));
  });

  testWidgets('spans are contiguous and non-overlapping', (tester) async {
    final controller = make(_sample);
    final span = await spanFor(tester, controller);
    final children = span.children!.cast<TextSpan>();
    final rebuilt = children.map((c) => c.text ?? '').join();
    expect(rebuilt, equals(_sample));
    expect(children.every((c) => (c.text ?? '').isNotEmpty), isTrue);
  });

  testWidgets('headings really do get a larger style', (tester) async {
    final controller = make('# Big\n\nnormal\n');
    final span = await spanFor(tester, controller);
    final children = span.children!.cast<TextSpan>();
    final heading = children.firstWhere((c) => c.text == 'Big');
    final body = children.firstWhere((c) => c.text!.contains('normal'));
    expect(heading.style!.fontSize, greaterThan(body.style!.fontSize!));
  });
}
