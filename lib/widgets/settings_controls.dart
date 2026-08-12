import 'package:flutter/material.dart';

import '../theme.dart';

/// A row of mutually-exclusive text pills — the segmented control every
/// settings page in the app uses for small, closed option sets.
class SettingsSegmented<T> extends StatelessWidget {
  const SettingsSegmented({
    super.key,
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
      mainAxisSize: MainAxisSize.min,
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
                    borderRadius: BorderRadius.circular(kRadiusControl),
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

/// A slider with its numeric value pinned to the right — the other recurring
/// settings control, for ranges rather than closed option sets.
class SettingsSlider extends StatelessWidget {
  const SettingsSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.onChangeEnd,
  });

  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  /// Fired once when the drag ends, rather than per tick — for callers that
  /// need to announce the final value (e.g. across a window boundary)
  /// without flooding it mid-drag.
  final ValueChanged<double>? onChangeEnd;

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
              onChangeEnd: onChangeEnd,
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
