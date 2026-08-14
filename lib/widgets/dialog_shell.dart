import 'package:flutter/material.dart';

import '../theme.dart';

/// How an action button reads. `destructive` and `plain` render isolated on
/// the left, away from `secondary`/`primary` on the right — the choice that
/// can't be undone stays visually apart from the safe ones either side of
/// it, rather than sitting in the same row a stray click could hit.
enum DialogActionKind { primary, secondary, destructive, plain }

class DialogAction<T> {
  const DialogAction(this.label, this.kind, this.value);
  final String label;
  final DialogActionKind kind;
  final T value;
}

/// Shows a dialog with the app's shared card chrome: rounded, shadowed,
/// borderless, a fixed width so the actions row's left/right split always
/// has room to lay out. Exactly one of [body] / [content] should be given —
/// [body] for a plain message, [content] for anything richer (composing in
/// the same chrome and actions row rather than duplicating it).
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required String title,
  String? body,
  Widget? content,
  required List<DialogAction<T>> actions,
  bool barrierDismissible = false,
}) {
  assert(
    (body == null) != (content == null),
    'showAppDialog needs exactly one of body/content',
  );
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black54,
    builder: (ctx) => _AppDialogShell<T>(
      title: title,
      body: body,
      content: content,
      actions: actions,
    ),
  );
}

class _AppDialogShell<T> extends StatelessWidget {
  const _AppDialogShell({
    required this.title,
    required this.body,
    required this.content,
    required this.actions,
  });

  final String title;
  final String? body;
  final Widget? content;
  final List<DialogAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Same card chrome as `_Section` in the Preferences window — surface0
    // with a hairline border and no shadow. A dialog drawn on surface1 with
    // elevation 24 instead reads as a heavier, different-looking card than
    // everything else in the app, which is the one thing a shared shell is
    // supposed to prevent.
    return Dialog(
      backgroundColor: p.surface0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusSurface),
        side: BorderSide(color: p.border),
      ),
      elevation: 0,
      child: SizedBox(
        width: 380,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (body != null)
                Text(
                  body!,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                )
              else
                content!,
              const SizedBox(height: 22),
              _ActionsRow<T>(actions: actions),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionsRow<T> extends StatelessWidget {
  const _ActionsRow({required this.actions});
  final List<DialogAction<T>> actions;

  static bool _isLeft(DialogAction a) =>
      a.kind == DialogActionKind.destructive || a.kind == DialogActionKind.plain;

  @override
  Widget build(BuildContext context) {
    final left = actions.where(_isLeft).toList();
    final right = actions.where((a) => !_isLeft(a)).toList();
    return Row(
      children: [
        _spaced([for (final a in left) _DialogButton<T>(action: a)]),
        const Spacer(),
        _spaced([for (final a in right) _DialogButton<T>(action: a)]),
      ],
    );
  }

  Widget _spaced(List<Widget> items) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            items[i],
          ],
        ],
      );
}

class _DialogButton<T> extends StatelessWidget {
  const _DialogButton({required this.action});
  final DialogAction<T> action;

  static final _shape =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusControl));
  static const _padding = EdgeInsets.symmetric(horizontal: 16);
  static const _minSize = Size(0, kControlHeight);
  static const _primaryText = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const _plainText = TextStyle(fontSize: 13, fontWeight: FontWeight.w500);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    void onTap() => Navigator.pop(context, action.value);

    return switch (action.kind) {
      DialogActionKind.primary => FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            shape: _shape,
            padding: _padding,
            minimumSize: _minSize,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: _primaryText,
          ),
          child: Text(action.label),
        ),
      // Filled, not outlined: buttons in this app carry their weight with
      // colour alone, and hover/press deepen that fill (see buildAppTheme's
      // overlay colours) rather than lighting up a border.
      DialogActionKind.secondary => FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            foregroundColor: p.textPrimary,
            backgroundColor: p.surface2,
            // One step up the surface ramp — reads in both palettes, unlike
            // the translucent white the accent-filled primary can use.
            overlayColor: p.surface3,
            elevation: 0,
            shape: _shape,
            padding: _padding,
            minimumSize: _minSize,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: _plainText,
          ),
          child: Text(action.label),
        ),
      DialogActionKind.destructive => TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: p.destructive,
            shape: _shape,
            padding: _padding,
            minimumSize: _minSize,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: _plainText,
          ),
          child: Text(action.label),
        ),
      DialogActionKind.plain => TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: p.textMuted,
            shape: _shape,
            padding: _padding,
            minimumSize: _minSize,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: _plainText,
          ),
          child: Text(action.label),
        ),
    };
  }
}
