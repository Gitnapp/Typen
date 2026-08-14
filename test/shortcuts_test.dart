import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typen/shortcuts.dart';
import 'package:typen/store.dart';

void main() {
  Future<Settings> boot([Map<String, Object> seed = const {}]) async {
    SharedPreferences.setMockInitialValues(seed);
    return (await Stores.open()).settings;
  }

  test('a binding survives a round trip through the store format', () {
    const original = SingleActivator(
      LogicalKeyboardKey.keyK,
      meta: true,
      shift: true,
      alt: true,
    );
    final back = ShortcutCodec.fromJson(ShortcutCodec.toJson(original))!;
    expect(sameBinding(back, original), isTrue);
  });

  test('a malformed store degrades to defaults instead of throwing', () {
    expect(ShortcutCodec.decodeAll('not json at all'), isEmpty);
    expect(ShortcutCodec.decodeAll('{"newDocument": {"key": "nope"}}'), isEmpty);
    expect(ShortcutCodec.decodeAll(null), isEmpty);
  });

  test('describeActivator writes modifiers in macOS order', () {
    expect(
      describeActivator(const SingleActivator(
        LogicalKeyboardKey.keyN,
        meta: true,
        shift: true,
      )),
      '⇧⌘N',
    );
    expect(
      describeActivator(
        const SingleActivator(LogicalKeyboardKey.slash, meta: true),
      ),
      '⌘/',
    );
  });

  testWidgets('every action answers with its default until rebound',
      (tester) async {
    final settings = await boot();
    for (final action in ShortcutAction.values) {
      expect(
        sameBinding(settings.activatorFor(action), action.defaultActivator),
        isTrue,
        reason: '${action.label} did not start on its default',
      );
    }
    expect(settings.hasShortcutOverrides, isFalse);
  });

  testWidgets('rebinding takes effect, and 还原默认 puts everything back',
      (tester) async {
    final settings = await boot();
    const custom = SingleActivator(LogicalKeyboardKey.keyJ, meta: true);

    await settings.setShortcut(ShortcutAction.save, custom);
    expect(sameBinding(settings.activatorFor(ShortcutAction.save), custom),
        isTrue);
    expect(settings.hasShortcutOverrides, isTrue);
    // Untouched actions keep their defaults.
    expect(
      sameBinding(
        settings.activatorFor(ShortcutAction.open),
        ShortcutAction.open.defaultActivator,
      ),
      isTrue,
    );

    await settings.resetShortcuts();
    expect(settings.hasShortcutOverrides, isFalse);
    expect(
      sameBinding(
        settings.activatorFor(ShortcutAction.save),
        ShortcutAction.save.defaultActivator,
      ),
      isTrue,
    );
  });

  testWidgets('rebinding back to the default stops being an override',
      (tester) async {
    final settings = await boot();
    await settings.setShortcut(
      ShortcutAction.save,
      const SingleActivator(LogicalKeyboardKey.keyJ, meta: true),
    );
    expect(settings.hasShortcutOverrides, isTrue);

    await settings.setShortcut(
      ShortcutAction.save,
      ShortcutAction.save.defaultActivator,
    );
    expect(settings.hasShortcutOverrides, isFalse);
  });

  testWidgets('a keystroke another command already owns is reported',
      (tester) async {
    final settings = await boot();
    // ⌘O is 打开… by default.
    final clash = settings.actionBoundTo(
      ShortcutAction.open.defaultActivator,
      ignoring: ShortcutAction.save,
    );
    expect(clash, ShortcutAction.open);

    // Rebinding an action onto its *own* current key is not a conflict.
    expect(
      settings.actionBoundTo(
        ShortcutAction.open.defaultActivator,
        ignoring: ShortcutAction.open,
      ),
      isNull,
    );
  });

  testWidgets('overrides survive a reload from the platform store',
      (tester) async {
    final settings = await boot();
    const custom = SingleActivator(LogicalKeyboardKey.keyJ, meta: true);
    await settings.setShortcut(ShortcutAction.save, custom);

    // A second window reads the same store through its own cache.
    final other = (await Stores.open()).settings;
    await other.refresh();
    expect(
      sameBinding(other.activatorFor(ShortcutAction.save), custom),
      isTrue,
    );
  });
}
