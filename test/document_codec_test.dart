import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:typen/document_file.dart';

Uint8List b(List<int> v) => Uint8List.fromList(v);
Uint8List u(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  // DocumentFile.write reaches for the native channel first; the binding must
  // exist for it to report MissingPluginException and fall back to Dart.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('byte fidelity', () {
    // Every one of these is a construct the previous WYSIWYG round-trip
    // destroyed. They must now survive untouched, byte for byte.
    final corpus = <String, Uint8List>{
      'empty': b([]),
      'plain LF': u('# Title\n\nBody text.\n'),
      'no trailing newline': u('# Title\n\nBody'),
      'CRLF': u('# Title\r\n\r\nBody\r\n'),
      'BOM + LF': b([0xEF, 0xBB, 0xBF, ...utf8.encode('# Title\n')]),
      'BOM + CRLF': b([0xEF, 0xBB, 0xBF, ...utf8.encode('# T\r\nx\r\n')]),
      'fenced code': u('# Install\n\n```bash\nflutter pub get\n```\n'),
      'tilde fence': u('~~~\nplain\n~~~\n'),
      'indented code': u('    indented code\n'),
      'html block': u('<div align="center">\n  <img src="a.png">\n</div>\n'),
      'front matter': u('---\ntitle: Hello\ntags: [a, b]\n---\n\n# Body\n'),
      'footnote': u('Text with a note[^1].\n\n[^1]: The note.\n'),
      'reference link': u('See [docs][d].\n\n[d]: https://example.com\n'),
      'hard break': u('line one  \nline two\n'),
      'escapes': u(r'\*not emphasis\* and 100\% sure' '\n'),
      'nested quote': u('> outer\n> > inner\n'),
      'table alignment': u('| A | B |\n|:--|--:|\n| 1 | 2 |\n'),
      'ordered start at 3': u('3. three\n4. four\n'),
      'blank line runs': u('a\n\n\n\nb\n'),
      'CJK': u('中文段落，含标点。\n\n第二段。\n'),
      'emoji + math': u(r'🎉 $e^{i\pi}+1=0$ and $$\int_0^1 x\,dx$$' '\n'),
      'mixed markers': u('- a\n  - b\n    - c\n\n* x\n+ y\n'),
      'lone CR': b([0x61, 0x0D, 0x62]),
    };

    corpus.forEach((name, bytes) {
      test('round-trips $name unchanged', () {
        final decoded = DocumentCodec.decode(bytes);
        final (out, _) = DocumentCodec.encode(decoded.text, decoded.encoding);
        expect(out, equals(bytes), reason: 'lost fidelity on "$name"');
      });
    });

    test('non-UTF-8 bytes survive via Latin-1', () {
      final bytes = b([0x48, 0x69, 0xE9, 0xFF, 0x0A]); // invalid UTF-8
      final decoded = DocumentCodec.decode(bytes);
      expect(decoded.encoding.isUtf8, isFalse);
      final (out, _) = DocumentCodec.encode(decoded.text, decoded.encoding);
      expect(out, equals(bytes));
    });

    test('Latin-1 file promotes to UTF-8 once it gains a CJK character', () {
      final decoded = DocumentCodec.decode(b([0xE9, 0x0A]));
      expect(decoded.encoding.isUtf8, isFalse);
      final (out, used) = DocumentCodec.encode('${decoded.text}中\n', decoded.encoding);
      expect(used.isUtf8, isTrue);
      expect(utf8.decode(out), contains('中'));
    });

    test('UTF-16 is refused rather than silently mangled', () {
      expect(
        () => DocumentCodec.decode(b([0xFF, 0xFE, 0x41, 0x00])),
        throwsA(isA<UnsupportedDocumentException>()),
      );
      expect(
        () => DocumentCodec.decode(b([0xFE, 0xFF, 0x00, 0x41])),
        throwsA(isA<UnsupportedDocumentException>()),
      );
    });

    test('the buffer never contains carriage returns from CRLF files', () {
      final decoded = DocumentCodec.decode(u('a\r\nb\r\nc'));
      expect(decoded.text, 'a\nb\nc');
      expect(decoded.encoding.eol, LineEnding.crlf);
    });

    test('mixed line endings are detected and flagged', () {
      final decoded = DocumentCodec.decode(u('a\r\nb\nc\r\n'));
      expect(decoded.encoding.mixedEol, isTrue);
      expect(decoded.encoding.eol, LineEnding.crlf);
    });

    test('an edit changes only what was edited', () {
      final original = u('# Title\n\n```dart\nvoid main() {}\n```\n\nTail\n');
      final decoded = DocumentCodec.decode(original);
      final edited = decoded.text.replaceFirst('Title', 'Titel');
      final (out, _) = DocumentCodec.encode(edited, decoded.encoding);
      expect(utf8.decode(out), '# Titel\n\n```dart\nvoid main() {}\n```\n\nTail\n');
    });
  });

  group('disk round-trip', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('typen_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('read then write reproduces the file exactly', () async {
      final bytes = b([
        0xEF, 0xBB, 0xBF, //
        ...utf8.encode('# Doc\r\n\r\n```js\r\nlet a = 1;\r\n```\r\n'),
      ]);
      final file = File('${dir.path}/doc.md')..writeAsBytesSync(bytes);

      final doc = await DocumentFile.read(file.path);
      await DocumentFile.write(file.path, doc.text, doc.encoding);

      expect(file.readAsBytesSync(), equals(bytes));
    });

    test('a mixed-ending file normalises, and says so', () async {
      // The single documented exception to byte fidelity. It must be visible
      // rather than silent, which is what `mixedEol` is for.
      final bytes = u('a\r\nb\nc\r\n');
      final file = File('${dir.path}/mixed.md')..writeAsBytesSync(bytes);

      final doc = await DocumentFile.read(file.path);
      expect(doc.encoding.mixedEol, isTrue);

      await DocumentFile.write(file.path, doc.text, doc.encoding);
      expect(file.readAsStringSync(), 'a\r\nb\r\nc\r\n');
    });

    test('write leaves no stray temp files behind', () async {
      final file = File('${dir.path}/doc.md')..writeAsStringSync('hi\n');
      final doc = await DocumentFile.read(file.path);
      await DocumentFile.write(file.path, 'hi there\n', doc.encoding);

      expect(file.readAsStringSync(), 'hi there\n');
      expect(
        dir.listSync().map((e) => e.path.split('/').last).toList(),
        equals(['doc.md']),
      );
    });

    test('writing through a symlink replaces the target, not the link',
        () async {
      final target = File('${dir.path}/real.md')..writeAsStringSync('old\n');
      final link = Link('${dir.path}/link.md')..createSync(target.path);

      final doc = await DocumentFile.read(link.path);
      await DocumentFile.write(link.path, 'new\n', doc.encoding);

      expect(FileSystemEntity.isLinkSync(link.path), isTrue);
      expect(target.readAsStringSync(), 'new\n');
    });

    test('a stamp notices an external edit', () async {
      final file = File('${dir.path}/doc.md')..writeAsStringSync('one\n');
      final before = await FileStamp.of(file.path);

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      file.writeAsStringSync('one two three\n');

      final after = await FileStamp.of(file.path);
      expect(before!.matches(after), isFalse);
    });
  });
}
