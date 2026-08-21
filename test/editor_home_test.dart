import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:typen/main.dart';
import 'package:typen/store.dart';
import 'package:typen/theme.dart';
import 'package:typen/widgets/editor_pane.dart';

const _channel = 'typen/native';
const _codec = StandardMethodCodec();

/// A call pushed in from "the native side", exactly the way AppDelegate does
/// at runtime. The reply is captured rather than awaited, because AppKit's
/// termination handshake is likewise fire-and-reply.
class NativeCall {
  Object? reply;
  bool answered = false;
}

NativeCall callFromNative(String method, [Object? args]) {
  final call = NativeCall();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _channel,
    _codec.encodeMethodCall(MethodCall(method, args)),
    (reply) {
      call.answered = true;
      call.reply = reply == null ? null : _codec.decodeEnvelope(reply);
    },
  );
  return call;
}

/// Widget tests run timers under FakeAsync, which never services real file
/// I/O. Alternating a real-loop yield with a pumped frame lets the app's
/// actual `dart:io` work complete while the UI still advances.
Future<void> flush(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Finder get editorField => find.byType(TextField).first;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The menu bar exists only as a channel message — there are no widgets to
  // look for — so it is captured on the way out to the platform.
  List<Map<Object?, Object?>>? menuBar;
  setUp(() {
    menuBar = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.menu, (call) async {
      if (call.method == 'Menu.setMenus') {
        menuBar = ((call.arguments as Map)['0'] as List)
            .cast<Map<Object?, Object?>>();
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.menu, null);
  });

  /// The labels one top-level menu offers. Dividers and platform-provided
  /// items carry no label of their own.
  List<String> menuLabels(String label) {
    final menu = menuBar!.firstWhere((m) => m['label'] == label);
    return [
      for (final child in menu['children'] as List)
        if ((child as Map)['label'] case final String l) l,
    ];
  }

  // flutter_test reports `android`, and PlatformProvidedMenuItem throws on any
  // platform without a system menu — which would fail the whole build. The
  // variant sets and restores the override around each test body.
  final onMacOS = TargetPlatformVariant.only(TargetPlatform.macOS);

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('typen_home'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Stores> boot(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final stores = await Stores.open();
    await tester.pumpWidget(TypenApp(stores: stores));
    await flush(tester);
    return stores;
  }

  File seed(String content, {String name = 'note.md'}) =>
      File('${dir.path}/$name')..writeAsStringSync(content);

  Future<void> openInApp(WidgetTester tester, File file) async {
    callFromNative('openFile', file.path);
    await flush(tester);
  }

  String bufferOf(WidgetTester tester) =>
      tester.widget<TextField>(editorField).controller!.text;

  testWidgets('a file handed over by the native side lands in the buffer',
      (tester) async {
    final file = seed('# Hello\n\n```dart\nvoid main() {}\n```\n');
    await boot(tester);
    await openInApp(tester, file);

    expect(bufferOf(tester), file.readAsStringSync());
  }, variant: onMacOS);

  testWidgets('quitting with unsaved changes prompts, and Save writes',
      (tester) async {
    const original = '# Hello\n\n```dart\nvoid main() {}\n```\n';
    const edited = '# Hello there\n\n```dart\nvoid main() {}\n```\n';
    final file = seed(original);
    await boot(tester);
    await openInApp(tester, file);

    await tester.enterText(editorField, edited);
    await tester.pump();

    // AppKit asks before terminating; the answer must wait for the user.
    final quit = callFromNative('confirmClose');
    await flush(tester);
    expect(quit.answered, isFalse, reason: 'quit must block on the prompt');
    expect(find.text('有未保存的修改'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await flush(tester);

    expect(quit.reply, isTrue);
    expect(file.readAsStringSync(), edited);
  }, variant: onMacOS);

  testWidgets('Cancel refuses the quit and keeps the edits', (tester) async {
    final file = seed('original\n');
    await boot(tester);
    await openInApp(tester, file);

    await tester.enterText(editorField, 'edited\n');
    await tester.pump();

    final quit = callFromNative('confirmClose');
    await flush(tester);
    await tester.tap(find.text('取消'));
    await flush(tester);

    expect(quit.reply, isFalse);
    expect(file.readAsStringSync(), 'original\n');
    expect(bufferOf(tester), 'edited\n');
  }, variant: onMacOS);

  testWidgets('Discard allows the quit and leaves the file alone',
      (tester) async {
    final file = seed('original\n');
    await boot(tester);
    await openInApp(tester, file);

    await tester.enterText(editorField, 'edited\n');
    await tester.pump();

    final quit = callFromNative('confirmClose');
    await flush(tester);
    await tester.tap(find.text('放弃'));
    await flush(tester);

    expect(quit.reply, isTrue);
    expect(file.readAsStringSync(), 'original\n');
  }, variant: onMacOS);

  testWidgets('a clean buffer quits without asking', (tester) async {
    final file = seed('untouched\n');
    await boot(tester);
    await openInApp(tester, file);

    final quit = callFromNative('confirmClose');
    await flush(tester);

    expect(quit.reply, isTrue);
    expect(find.text('有未保存的修改'), findsNothing);
  }, variant: onMacOS);

  testWidgets('saving preserves CRLF and the BOM', (tester) async {
    final file = File('${dir.path}/crlf.md')
      ..writeAsBytesSync([
        0xEF, 0xBB, 0xBF, //
        ...utf8.encode('one\r\ntwo\r\n'),
      ]);
    await boot(tester);
    await openInApp(tester, file);

    // The buffer is normalised to \n — the user never sees a stray CR.
    expect(bufferOf(tester), 'one\ntwo\n');

    await tester.enterText(editorField, 'one\ntwo\nthree\n');
    await tester.pump();
    final quit = callFromNative('confirmClose');
    await flush(tester);
    await tester.tap(find.text('保存'));
    await flush(tester);

    expect(quit.reply, isTrue);
    expect(
      file.readAsBytesSync(),
      [0xEF, 0xBB, 0xBF, ...utf8.encode('one\r\ntwo\r\nthree\r\n')],
    );
  }, variant: onMacOS);

  testWidgets('the Window menu lists the windows the native side pushes down',
      (tester) async {
    await boot(tester);
    expect(menuLabels('窗口'), isEmpty);

    callFromNative('windowsChanged', [
      {'id': 1, 'title': 'note.md', 'isKey': true},
      {'id': 2, 'title': 'Untitled', 'isKey': false},
    ]);
    await flush(tester);

    // No checkmark exists on a PlatformMenuItem, so the key window is marked
    // in its label.
    expect(menuLabels('窗口'), ['✓ note.md', 'Untitled']);
  }, variant: onMacOS);

  testWidgets(
      'a settingsChanged broadcast makes this Window re-read Settings from '
      'the platform store', (tester) async {
    final stores = await boot(tester);
    expect(stores.settings.fontSize, 15.0);

    // A different Window's engine wrote this — SharedPreferences caches per
    // isolate, so this Window's own copy stays stale until it reloads.
    SharedPreferences.setMockInitialValues({'font_size': 20.0});
    expect(stores.settings.fontSize, 15.0, reason: 'stale until told to reload');

    callFromNative('settingsChanged');
    await flush(tester);

    expect(stores.settings.fontSize, 20.0);
  }, variant: onMacOS);

  testWidgets(
      'toggling source/preview carries reading position as a fraction of '
      'each side\'s own scroll extent', (tester) async {
    final file = seed(
      List.generate(200, (i) => '第 $i 段——用来撑满可滚动的长文档。\n\n').join(),
    );
    await boot(tester);
    await openInApp(tester, file);

    final sourceScroll = tester.widget<TextField>(editorField).scrollController!;
    expect(sourceScroll.position.maxScrollExtent, greaterThan(0));
    sourceScroll.jumpTo(sourceScroll.position.maxScrollExtent / 2);
    await tester.pump();
    final sourceFraction =
        sourceScroll.offset / sourceScroll.position.maxScrollExtent;

    await tester.tap(find.byTooltip('切换模式（⌘/）'));
    await flush(tester);

    final previewScroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    expect(previewScroll.position.maxScrollExtent, greaterThan(0));
    final previewFraction =
        previewScroll.offset / previewScroll.position.maxScrollExtent;
    expect(previewFraction, closeTo(sourceFraction, 0.05));

    // Back to source — focus must not drag the offset to the caret instead.
    await tester.tap(find.byTooltip('切换模式（⌘/）'));
    await flush(tester);

    final restoredFraction =
        sourceScroll.offset / sourceScroll.position.maxScrollExtent;
    expect(restoredFraction, closeTo(previewFraction, 0.05));
  }, variant: onMacOS);

  testWidgets('the first source H1 gets the same full line box as the next H1',
      (tester) async {
    const content = '# First H1\n# Second H1\nbody\n';
    final file = seed(content);
    await boot(tester);
    await openInApp(tester, file);

    final editable = tester
        .state<EditableTextState>(find.byType(EditableText).first)
        .renderEditable;
    Rect bounds(int start, int end) => editable
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        )
        .map((box) => box.toRect())
        .reduce((a, b) => a.expandToInclude(b));

    final first = bounds(0, content.indexOf('\n'));
    final secondStart = content.indexOf('\n') + 1;
    final second = bounds(secondStart, content.indexOf('\n', secondStart));

    expect(first.top, greaterThanOrEqualTo(0));
    expect(first.height, greaterThan(30),
        reason: 'the first 24px H1 glyph needs a complete line box');
    // Strut only guarantees line 1 isn't clipped, not pixel parity with
    // later lines — Skia's strut-vs-content line-height merge leaves a few
    // px of slack that doesn't correspond to any visible glyph clipping.
    expect(first.height, closeTo(second.height, 5));
  }, variant: onMacOS);

  testWidgets('the extra bottom line is scrollable and appends on click',
      (tester) async {
    final original = List.generate(80, (i) => 'line $i').join('\n');
    final file = seed(original);
    final stores = await boot(tester);
    await openInApp(tester, file);

    final field = tester.widget<TextField>(editorField);
    final sourceScroll = field.scrollController!;
    sourceScroll.jumpTo(sourceScroll.position.maxScrollExtent);
    await tester.pump();

    final bottomSpace = find.byKey(EditorPane.sourceBottomSpaceKey);
    expect(bottomSpace, findsOneWidget);
    expect(
      tester.getSize(bottomSpace).height,
      stores.settings.fontSize * 1.6,
    );

    await tester.tap(bottomSpace);
    await tester.pump();
    await tester.pump();

    expect(bufferOf(tester), '$original\n');
    expect(field.controller!.selection.baseOffset, original.length + 1);
    expect(sourceScroll.offset, sourceScroll.position.maxScrollExtent);

    // The buffer now ends on a blank line — that line already is the room
    // to click into, so the synthetic space must not still be reserved.
    expect(find.byKey(EditorPane.sourceBottomSpaceKey), findsNothing);
  }, variant: onMacOS);

  testWidgets(
      'a document that already ends on a blank line gets no extra click space',
      (tester) async {
    final original = '${List.generate(80, (i) => 'line $i').join('\n')}\n';
    final file = seed(original);
    await boot(tester);
    await openInApp(tester, file);

    final field = tester.widget<TextField>(editorField);
    final sourceScroll = field.scrollController!;
    sourceScroll.jumpTo(sourceScroll.position.maxScrollExtent);
    await tester.pump();

    expect(find.byKey(EditorPane.sourceBottomSpaceKey), findsNothing);
    expect(bufferOf(tester), original, reason: 'no line was silently added');
  }, variant: onMacOS);

  testWidgets('editor toolbar buttons use the shared compact height',
      (tester) async {
    await boot(tester);

    expect(
      tester.getSize(find.byTooltip('切换模式（⌘/）')).height,
      kControlHeight,
    );
  }, variant: onMacOS);

  testWidgets('an edit made by another program is not silently overwritten',
      (tester) async {
    final file = seed('mine\n');
    await boot(tester);
    await openInApp(tester, file);

    await tester.enterText(editorField, 'my edit\n');
    await tester.pump();

    // Somebody else edits the file behind our back. The sleep is real: the
    // check compares mtime, whose resolution is one second.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      file.writeAsStringSync('their edit\n');
    });

    final quit = callFromNative('confirmClose');
    await flush(tester);
    await tester.tap(find.text('保存'));
    await flush(tester);

    expect(find.text('文件已被其他程序修改'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await flush(tester);

    expect(file.readAsStringSync(), 'their edit\n');
    expect(quit.reply, isFalse);
  }, variant: onMacOS);

  testWidgets(
      'a document too short to scroll previews flush to the top, not centred',
      (tester) async {
    final file = seed('# 只有一行\n');
    await boot(tester);
    await openInApp(tester, file);

    await tester.tap(find.byTooltip('切换模式（⌘/）'));
    await flush(tester);

    final scroller = find.byType(SingleChildScrollView);
    expect(scroller, findsOneWidget);
    final viewportTop = tester.getTopLeft(scroller).dy;
    final contentTop = tester.getTopLeft(find.byType(MarkdownBody)).dy;

    // 24 is the preview's own top padding; anything much past that means
    // something is pushing the content down the viewport.
    expect(
      contentTop - viewportTop,
      closeTo(24, 4),
      reason: 'preview content sits ${contentTop - viewportTop}px below the '
          'viewport top — expected it flush under the 24px padding',
    );
  }, variant: onMacOS);

  testWidgets('preview keeps text on the left, the way the source view does',
      (tester) async {
    final file = seed('123\n\n额\n');
    await boot(tester);
    await openInApp(tester, file);

    final sourceLeft =
        tester.getTopLeft(find.textContaining('123', findRichText: true).first).dx;

    await tester.tap(find.byTooltip('切换模式（⌘/）'));
    await flush(tester);

    final previewText = find.textContaining('123', findRichText: true).first;
    final previewLeft = tester.getTopLeft(previewText).dx;

    expect(
      previewLeft,
      closeTo(sourceLeft, 8),
      reason: 'preview text starts at \$previewLeft but the source view '
          'starts it at \$sourceLeft — the preview is centring it',
    );
  }, variant: onMacOS);

  testWidgets('turning soft wrap off lets a long line run past the viewport',
      (tester) async {
    final long = '${'x' * 400}\n';
    final file = seed(long);
    final stores = await boot(tester);
    await openInApp(tester, file);

    // Wrapping on: the field is capped at the viewport, so the text wraps
    // and there is no horizontal scroller.
    expect(
      find.byWidgetPredicate((w) =>
          w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
      findsNothing,
    );

    stores.settings.softWrap = false;
    await flush(tester);

    expect(
      find.byWidgetPredicate((w) =>
          w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
      findsOneWidget,
      reason: 'no horizontal scroller appeared for the unwrapped line',
    );
  }, variant: onMacOS);
}
