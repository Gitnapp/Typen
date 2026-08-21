import 'package:flutter/material.dart';

/// Colour tokens for one appearance. Everything in the app reads colours from
/// here via `context.palette`, so adding an appearance is a matter of adding
/// one more const instance — no widget knows whether it is light or dark.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.surface0,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.borderHover,
    required this.gold,
    required this.coral,
    required this.emerald,
    required this.destructive,
    required this.selection,
    required this.findMatch,
    required this.findCurrent,
  });

  final Brightness brightness;

  final Color surface0;
  final Color surface1;
  final Color surface2;
  final Color surface3;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color border;
  final Color borderHover;

  /// Warm branding — headings/emphasis/links in rendered Markdown, the
  /// unsaved-dot, the brand mark. Never a clickable control's own colour;
  /// see [accent] for that.
  final Color gold;
  final Color coral;
  final Color emerald;

  /// The "on" colour for controls: a selected chip, a slider's filled
  /// track, a switch that is on. Deliberately not a hue — it is whatever
  /// stands hardest against the surface, so it is near-white on the dark
  /// palette and near-black on the light one. A fixed white would vanish on
  /// paper; a fixed blue would be the one saturated thing in a monochrome
  /// window.
  Color get accent => textPrimary;

  /// Text drawn *on* [accent], which is the surface colour inverted back.
  Color get onAccent => surface0;

  final Color destructive;

  final Color selection;
  final Color findMatch;
  final Color findCurrent;

  /// The original "Dusk" palette.
  static const dark = AppPalette(
    brightness: Brightness.dark,
    surface0: Color(0xFF0A0A0A),
    surface1: Color(0xFF141414),
    surface2: Color(0xFF1C1C1C),
    surface3: Color(0xFF242424),
    textPrimary: Color(0xFFF5F5F4),
    textSecondary: Color(0xFF8A8A87),
    textMuted: Color(0xFF5C5C59),
    border: Color(0x14FFFFFF),
    borderHover: Color(0x2EFFFFFF),
    gold: Color(0xFFD4A93A),
    coral: Color(0xFFF08A3E),
    emerald: Color(0xFF4A8A5C),
    destructive: Color(0xFFFF453A),
    selection: Color(0x47D4A93A),
    findMatch: Color(0x38D4A93A),
    findCurrent: Color(0x8CF08A3E),
  );

  /// Warm paper counterpart — same hues, inverted ramp.
  static const light = AppPalette(
    brightness: Brightness.light,
    surface0: Color(0xFFFCFCFB),
    surface1: Color(0xFFF4F4F2),
    surface2: Color(0xFFEAEAE7),
    surface3: Color(0xFFDFDFDB),
    textPrimary: Color(0xFF1B1B19),
    textSecondary: Color(0xFF5F5F5B),
    textMuted: Color(0xFF93938E),
    border: Color(0x14000000),
    borderHover: Color(0x2E000000),
    gold: Color(0xFF9A7712),
    coral: Color(0xFFC2621C),
    emerald: Color(0xFF2F6B41),
    destructive: Color(0xFFFF3B30),
    selection: Color(0x479A7712),
    findMatch: Color(0x389A7712),
    findCurrent: Color(0x8CC2621C),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) =>
      t < 0.5 ? this : (other as AppPalette? ?? this);
}

extension PaletteAccess on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}

const Cubic kAppEase = Cubic(0.22, 1, 0.36, 1);

/// The two corner-radius tiers every rounded element in the app draws from —
/// controls (buttons, pills, chips, rows) and surfaces (cards, dialogs).
/// Interactive elements must use [kRadiusControl] for their visible shape
/// *and* for whatever draws their hover/press state, so the highlight never
/// mismatches the shape it's highlighting.
const double kRadiusControl = 8;
const double kRadiusSurface = 14;

/// Shared geometry for every compact button, chip and field in the editor and
/// Preferences. Text buttons keep content-driven widths; icon buttons are
/// square, and every control uses the same height and horizontal padding.
const double kControlHeight = 28;
const double kIconControlWidth = kControlHeight;
const EdgeInsets kControlPadding = EdgeInsets.symmetric(horizontal: 12);

/// Applies the app's shared compact button geometry before layering on the
/// button's semantic colours. Keeping this here prevents Material's 48px
/// default tap target or one-off padding from making adjacent controls jump in
/// size.
ButtonStyle appButtonStyle([ButtonStyle? appearance]) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(0, kControlHeight)),
  maximumSize: const WidgetStatePropertyAll(
    Size(double.infinity, kControlHeight),
  ),
  padding: const WidgetStatePropertyAll(kControlPadding),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusControl)),
  ),
).merge(appearance);

ThemeData buildAppTheme(AppPalette p) {
  // No ripple anywhere — a static hover/press fill instead, same idea as
  // _SidebarItem's own hand-rolled hover. Text/outlined buttons have no
  // background of their own, so an opaque surface tint reads as "a pill
  // appears on hover". A filled button already has a colour of its own
  // (kRadiusControl's accent blue) — painting the same opaque surface tint
  // over it would just replace that colour with grey, so it gets a
  // translucent wash instead, letting the base colour show through.
  ButtonStyle noRipple(WidgetStateProperty<Color?> overlay) => appButtonStyle(
    ButtonStyle(
      splashFactory: NoSplash.splashFactory,
      overlayColor: overlay,
      // A flat colour swap, not a fade — the default cross-fade between
      // hover states is what read as flicker/blinking near a rounded
      // corner's hit-test edge.
      animationDuration: Duration.zero,
    ),
  );
  final surfaceOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.pressed)) return p.surface3;
    if (states.contains(WidgetState.hovered)) return p.surface2;
    return null;
  });
  final washOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.pressed)) return Colors.white24;
    if (states.contains(WidgetState.hovered)) return Colors.white12;
    return null;
  });

  return ThemeData(
    brightness: p.brightness,
    useMaterial3: true,
    extensions: [p],
    scaffoldBackgroundColor: p.surface0,
    canvasColor: p.surface0,
    dividerColor: p.border,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: p.brightness,
      surface: p.surface1,
    ),
    textButtonTheme: TextButtonThemeData(style: noRipple(surfaceOverlay)),
    outlinedButtonTheme:
        OutlinedButtonThemeData(style: noRipple(surfaceOverlay)),
    filledButtonTheme: FilledButtonThemeData(style: noRipple(washOverlay)),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.gold,
      selectionColor: p.selection,
      selectionHandleColor: p.gold,
    ),
    textTheme: TextTheme(
      bodyMedium:
          TextStyle(color: p.textPrimary, fontSize: 14, height: 1.55),
      bodySmall: TextStyle(color: p.textSecondary, fontSize: 12),
      titleMedium:
          TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
    ),
    iconTheme: IconThemeData(color: p.textSecondary),
  );
}
