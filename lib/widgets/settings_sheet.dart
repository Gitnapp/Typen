import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';

Future<void> showSettingsSheet(BuildContext context, Settings settings) {
  return showDialog(
    context: context,
    barrierColor: Colors.black38,
    builder: (_) => _SettingsSheet(settings: settings),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.settings});
  final Settings settings;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.settings;

    return AlertDialog(
      backgroundColor: p.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.border),
      ),
      contentPadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
      title: Text(
        '偏好设置',
        style: TextStyle(
          color: p.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row(
              label: '外观',
              child: _Segmented<ThemeMode>(
                value: s.themeMode,
                options: const {
                  ThemeMode.system: '跟随系统',
                  ThemeMode.light: '浅色',
                  ThemeMode.dark: '深色',
                },
                onChanged: (v) => setState(() => s.themeMode = v),
              ),
            ),
            _Row(
              label: '字号',
              child: _Slider(
                value: s.fontSize,
                min: Settings.minFontSize,
                max: Settings.maxFontSize,
                display: s.fontSize.toStringAsFixed(0),
                onChanged: (v) => setState(() => s.fontSize = v),
              ),
            ),
            _Row(
              label: '列宽',
              child: _Slider(
                value: s.columnWidth,
                min: Settings.minColumnWidth,
                max: Settings.maxColumnWidth,
                display: s.columnWidth.toStringAsFixed(0),
                onChanged: (v) => setState(() => s.columnWidth = v),
              ),
            ),
            _Row(
              label: '编辑器字体',
              child: _Segmented<bool>(
                value: s.proportionalEditorFont,
                options: const {false: '等宽', true: '比例'},
                onChanged: (v) =>
                    setState(() => s.proportionalEditorFont = v),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('完成', style: TextStyle(color: p.gold)),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                color: context.palette.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        for (final entry in options.entries)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onChanged(entry.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: kAppEase,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: entry.key == value ? p.surface3 : p.surface2,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: entry.key == value ? p.borderHover : p.border,
                    ),
                  ),
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      color:
                          entry.key == value ? p.textPrimary : p.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: p.gold,
              inactiveTrackColor: p.surface3,
              thumbColor: p.gold,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: p.textMuted,
              fontSize: 11.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
