import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Every command whose shortcut the user is allowed to rebind.
///
/// Deliberately only Typen's own commands. The standard editing keys
/// (undo/redo/cut/copy/paste/select-all) stay fixed: they are OS-wide
/// conventions, and their menu entry is not the only thing bound to them —
/// Flutter's own text-field bindings answer them too, so rebinding the menu
/// would leave the old key still working and read as a bug.
enum ShortcutAction {
  newDocument('新建'),
  newWindow('新建窗口'),
  open('打开…'),
  closeWindow('关闭窗口'),
  save('保存'),
  saveAs('另存为…'),
  toggleMode('切换源码/预览'),
  find('查找…'),
  findReplace('查找与替换…'),
  findNext('查找下一个'),
  findPrevious('查找上一个'),
  preferences('偏好设置…');

  const ShortcutAction(this.label);

  /// What the Preferences list calls this row.
  final String label;

  /// The binding shipped with the app, and what "还原默认" goes back to.
  SingleActivator get defaultActivator => switch (this) {
        newDocument =>
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
        newWindow => const SingleActivator(
            LogicalKeyboardKey.keyN,
            meta: true,
            shift: true,
          ),
        open => const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
        closeWindow =>
          const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
        save => const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
        saveAs => const SingleActivator(
            LogicalKeyboardKey.keyS,
            meta: true,
            shift: true,
          ),
        toggleMode =>
          const SingleActivator(LogicalKeyboardKey.slash, meta: true),
        find => const SingleActivator(LogicalKeyboardKey.keyF, meta: true),
        findReplace => const SingleActivator(
            LogicalKeyboardKey.keyF,
            meta: true,
            alt: true,
          ),
        findNext => const SingleActivator(LogicalKeyboardKey.keyG, meta: true),
        findPrevious => const SingleActivator(
            LogicalKeyboardKey.keyG,
            meta: true,
            shift: true,
          ),
        preferences =>
          const SingleActivator(LogicalKeyboardKey.comma, meta: true),
      };
}

/// Serialises a [SingleActivator] to and from the platform store.
///
/// The key travels as its `keyId` rather than a label: ids are stable across
/// releases and keyboard layouts, whereas a label is neither.
class ShortcutCodec {
  const ShortcutCodec._();

  static Map<String, Object?> toJson(SingleActivator a) => {
        'key': a.trigger.keyId,
        if (a.meta) 'meta': true,
        if (a.shift) 'shift': true,
        if (a.alt) 'alt': true,
        if (a.control) 'control': true,
      };

  static SingleActivator? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['key'];
    if (id is! int) return null;
    final key = LogicalKeyboardKey.findKeyByKeyId(id);
    if (key == null) return null;
    return SingleActivator(
      key,
      meta: raw['meta'] == true,
      shift: raw['shift'] == true,
      alt: raw['alt'] == true,
      control: raw['control'] == true,
    );
  }

  static String encodeAll(Map<ShortcutAction, SingleActivator> overrides) =>
      jsonEncode({
        for (final e in overrides.entries) e.key.name: toJson(e.value),
      });

  static Map<ShortcutAction, SingleActivator> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return const {};
      final out = <ShortcutAction, SingleActivator>{};
      for (final action in ShortcutAction.values) {
        final a = fromJson(map[action.name]);
        if (a != null) out[action] = a;
      }
      return out;
    } catch (_) {
      // A malformed store is not worth crashing over — every action simply
      // falls back to its default.
      return const {};
    }
  }
}

/// How a binding reads in the UI: `⇧⌘N`, macOS order.
String describeActivator(SingleActivator a) {
  final b = StringBuffer();
  if (a.control) b.write('⌃');
  if (a.alt) b.write('⌥');
  if (a.shift) b.write('⇧');
  if (a.meta) b.write('⌘');
  b.write(_keyLabel(a.trigger));
  return b.toString();
}

String _keyLabel(LogicalKeyboardKey key) {
  final named = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.comma: ',',
    LogicalKeyboardKey.period: '.',
    LogicalKeyboardKey.slash: '/',
    LogicalKeyboardKey.backslash: '\\',
    LogicalKeyboardKey.semicolon: ';',
    LogicalKeyboardKey.quote: '\'',
    LogicalKeyboardKey.bracketLeft: '[',
    LogicalKeyboardKey.bracketRight: ']',
    LogicalKeyboardKey.minus: '-',
    LogicalKeyboardKey.equal: '=',
    LogicalKeyboardKey.backquote: '`',
    LogicalKeyboardKey.space: '空格',
    LogicalKeyboardKey.enter: '↩',
    LogicalKeyboardKey.tab: '⇥',
    LogicalKeyboardKey.backspace: '⌫',
    LogicalKeyboardKey.delete: '⌦',
    LogicalKeyboardKey.escape: '⎋',
    LogicalKeyboardKey.arrowUp: '↑',
    LogicalKeyboardKey.arrowDown: '↓',
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.arrowRight: '→',
  };
  final special = named[key];
  if (special != null) return special;
  final label = key.keyLabel;
  return label.isEmpty ? '?' : label.toUpperCase();
}

/// True when these two bindings would fire on the same keystroke.
bool sameBinding(SingleActivator a, SingleActivator b) =>
    a.trigger == b.trigger &&
    a.meta == b.meta &&
    a.shift == b.shift &&
    a.alt == b.alt &&
    a.control == b.control;
