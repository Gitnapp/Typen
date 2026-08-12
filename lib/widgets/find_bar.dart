import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../find.dart';
import '../theme.dart';

class FindBar extends StatelessWidget {
  const FindBar({
    super.key,
    required this.controller,
    required this.queryFocus,
    required this.queryController,
    required this.replaceController,
    required this.showReplace,
    required this.onQueryChanged,
    required this.onToggleOption,
    required this.onStep,
    required this.onReplace,
    required this.onReplaceAll,
    required this.onToggleReplace,
    required this.onClose,
  });

  final FindController controller;
  final FocusNode queryFocus;
  final TextEditingController queryController;
  final TextEditingController replaceController;
  final bool showReplace;
  final ValueChanged<String> onQueryChanged;
  final void Function({bool? caseSensitive, bool? useRegex}) onToggleOption;
  final ValueChanged<int> onStep;
  final VoidCallback onReplace;
  final VoidCallback onReplaceAll;
  final VoidCallback onToggleReplace;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final count = controller.matches.length;
    final label = controller.badPattern
        ? '正则无效'
        : controller.query.isEmpty
            ? ''
            : count == 0
                ? '无结果'
                : '${controller.current + 1}/$count';

    return Container(
      decoration: BoxDecoration(
        color: p.surface1,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _IconToggle(
                icon: showReplace
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                tooltip: '替换',
                active: showReplace,
                onTap: onToggleReplace,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _Field(
                  controller: queryController,
                  focusNode: queryFocus,
                  hint: '查找',
                  onChanged: onQueryChanged,
                  onSubmit: (shift) => onStep(shift ? -1 : 1),
                  onEscape: onClose,
                  error: controller.badPattern,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 62,
                child: Text(
                  label,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: controller.badPattern ? p.coral : p.textMuted,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _IconToggle(
                label: 'Aa',
                tooltip: '区分大小写',
                active: controller.caseSensitive,
                onTap: () =>
                    onToggleOption(caseSensitive: !controller.caseSensitive),
              ),
              _IconToggle(
                label: '.*',
                tooltip: '正则表达式',
                active: controller.useRegex,
                onTap: () => onToggleOption(useRegex: !controller.useRegex),
              ),
              const SizedBox(width: 4),
              _IconToggle(
                icon: Icons.arrow_upward,
                tooltip: '上一个（⇧⌘G）',
                onTap: () => onStep(-1),
              ),
              _IconToggle(
                icon: Icons.arrow_downward,
                tooltip: '下一个（⌘G）',
                onTap: () => onStep(1),
              ),
              _IconToggle(
                icon: Icons.close,
                tooltip: '关闭（esc）',
                onTap: onClose,
              ),
            ],
          ),
          if (showReplace) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 30),
                Expanded(
                  child: _Field(
                    controller: replaceController,
                    hint: '替换为',
                    onChanged: (_) {},
                    onSubmit: (_) => onReplace(),
                    onEscape: onClose,
                  ),
                ),
                const SizedBox(width: 8),
                _TextButton(label: '替换', onTap: onReplace),
                const SizedBox(width: 6),
                _TextButton(label: '全部替换', onTap: onReplaceAll),
                const SizedBox(width: 34),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onSubmit,
    required this.onEscape,
    this.focusNode,
    this.error = false,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final bool error;
  final ValueChanged<String> onChanged;
  final void Function(bool shiftPressed) onSubmit;
  final VoidCallback onEscape;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): _SubmitIntent(false),
        SingleActivator(LogicalKeyboardKey.enter, shift: true):
            _SubmitIntent(true),
        SingleActivator(LogicalKeyboardKey.escape): _EscapeIntent(),
      },
      child: Actions(
        actions: {
          _SubmitIntent: CallbackAction<_SubmitIntent>(
            onInvoke: (i) {
              onSubmit(i.shift);
              return null;
            },
          ),
          _EscapeIntent: CallbackAction<_EscapeIntent>(
            onInvoke: (_) {
              onEscape();
              return null;
            },
          ),
        },
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: p.surface0,
            borderRadius: BorderRadius.circular(kRadiusControl),
            border: Border.all(color: error ? p.coral : p.border),
          ),
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            cursorColor: p.gold,
            style: TextStyle(color: p.textPrimary, fontSize: 12.5),
            decoration: InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              hintText: hint,
              hintStyle: TextStyle(color: p.textMuted, fontSize: 12.5),
            ),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class _SubmitIntent extends Intent {
  const _SubmitIntent(this.shift);
  final bool shift;
}

class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

class _IconToggle extends StatelessWidget {
  const _IconToggle({
    this.icon,
    this.label,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData? icon;
  final String? label;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 26,
            height: 24,
            alignment: Alignment.center,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: active ? p.surface3 : Colors.transparent,
              borderRadius: BorderRadius.circular(kRadiusControl),
            ),
            child: icon != null
                ? Icon(
                    icon,
                    size: 14,
                    color: active ? p.gold : p.textSecondary,
                  )
                : Text(
                    label!,
                    style: TextStyle(
                      color: active ? p.gold : p.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(kRadiusControl),
            border: Border.all(color: p.border),
          ),
          child: Text(
            label,
            style: TextStyle(color: p.textSecondary, fontSize: 11.5),
          ),
        ),
      ),
    );
  }
}
