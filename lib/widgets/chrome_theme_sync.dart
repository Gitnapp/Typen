import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';

import '../native.dart';

/// Pushes the app's resolved brightness to the native side, so the window
/// chrome (the GTK header bar on Linux) follows the same light/dark choice —
/// system or explicit — as the content. macOS chrome does this on its own;
/// the call degrades to a no-op there.
class ChromeThemeSync extends StatelessWidget {
  const ChromeThemeSync({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Native.setDarkMode(dark);
    });
    return child;
  }
}
