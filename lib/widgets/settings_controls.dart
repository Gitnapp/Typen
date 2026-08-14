import 'package:flutter/material.dart';

import '../theme.dart';

/// A row of mutually-exclusive text pills — the segmented control every
/// settings page in the app uses for small, closed option sets.
///
/// No outline: resting, hover and selected are carried by the fill alone,
/// so the row reads as soft chips rather than a grid of boxed buttons.
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in options.entries)
          Padding(
            // Gap on the left, so the last chip sits flush with the right
            // edge the rows align to.
            padding: const EdgeInsets.only(left: 6),
            child: _Chip(
              label: entry.value,
              selected: entry.key == value,
              onTap: () => onChanged(entry.key),
            ),
          ),
      ],
    );
  }
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final Color background;
    if (widget.selected) {
      background = p.accent;
    } else if (_hovered) {
      background = p.surface3;
    } else {
      background = p.surface2;
    }
    return MouseRegion(
      // Arrow, not the hand: this window's controls read as native macOS
      // chrome, where a pointing hand means a link.
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: kControlHeight,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(kRadiusControl),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.selected ? p.onAccent : p.textSecondary,
              fontSize: 11.5,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

SliderThemeData _sliderTheme(AppPalette p) => SliderThemeData(
      // Slider's own default cursor is the hand; the rest of this window
      // uses the arrow.
      mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.basic),
      trackHeight: 3,
      activeTrackColor: p.accent,
      inactiveTrackColor: p.surface3,
      thumbColor: p.accent,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 7,
        elevation: 2,
      ),
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 1.5),
      activeTickMarkColor: p.accent,
      inactiveTickMarkColor: p.textMuted,
      showValueIndicator: ShowValueIndicator.never,
    );

/// A slider that only stops on the values it is given, with a tick under
/// each one — the shape a reading app uses for text size, where the steps
/// are the whole point and an arbitrary 15.3 would mean nothing.
class SettingsStepSlider extends StatelessWidget {
  const SettingsStepSlider({
    super.key,
    required this.value,
    required this.steps,
    required this.display,
    required this.onChanged,
    this.onChangeEnd,
  });

  final double value;
  final List<double> steps;
  final String display;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  int get _index {
    var best = 0;
    for (var i = 0; i < steps.length; i++) {
      if ((steps[i] - value).abs() < (steps[best] - value).abs()) best = i;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: _sliderTheme(p),
            // The value travels as an *index*, which is what makes the thumb
            // click onto a notch and draws the ticks — and it lets the steps
            // be unevenly spaced (12,13,14,15,16,18,20…) without the track
            // lying about the distance between them.
            child: Slider(
              value: _index.toDouble(),
              min: 0,
              max: (steps.length - 1).toDouble(),
              divisions: steps.length - 1,
              onChanged: (i) => onChanged(steps[i.round()]),
              onChangeEnd: onChangeEnd == null
                  ? null
                  : (i) => onChangeEnd!(steps[i.round()]),
            ),
          ),
        ),
        _ValueLabel(display),
      ],
    );
  }
}

class _ValueLabel extends StatelessWidget {
  const _ValueLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: 38,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: p.textMuted,
          fontSize: 11.5,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// The on/off switch settings rows use, scaled down to sit comfortably
/// among this window's other controls.
class SettingsToggle extends StatelessWidget {
  const SettingsToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Transform.scale(
      scale: 0.68,
      alignment: Alignment.centerRight,
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: p.onAccent,
        activeTrackColor: p.accent,
        inactiveThumbColor: p.textSecondary,
        inactiveTrackColor: p.surface3,
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        mouseCursor: SystemMouseCursors.basic,
      ),
    );
  }
}
