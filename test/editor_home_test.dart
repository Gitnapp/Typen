import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typen/main.dart';
import 'package:typen/store.dart';

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

  Future<void> boot(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final stores = await Stores.open();
    await tester.pumpWidget(TypenApp(stores: stores));
    await flush(tester);
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
}
