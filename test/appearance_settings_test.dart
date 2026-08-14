import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typen/store.dart';
import 'package:typen/theme.dart';
import 'package:typen/widgets/preferences_window.dart';
import 'package:typen/widgets/settings_controls.dart';

void main() {
  Future<Stores> boot([Map<String, Object> seed = const {}]) async {
    SharedPreferences.setMockInitialValues(seed);
    return Stores.open();
  }

  test('soft wrap is on out of the box', () async {
    final s = (await boot()).settings;
    expect(s.softWrap, isTrue);
    s.softWrap = false;
    expect(s.softWrap, isFalse);
  });

  test('indent is a stepped margin, not a column width', () async {
    final s = (await boot()).settings;
    expect(Settings.indentSteps, contains(s.indent));

    // Off-notch values snap rather than sticking where they land.
    s.indent = 70;
    expect(s.indent, 64.0);
    s.indent = 120;
    expect(s.indent, 140.0);

    // And it stays inside the offered range.
    s.indent = 10_000;
    expect(s.indent, Settings.maxIndent);
    s.indent = -5;
    expect(s.indent, Settings.minIndent);
  });

  test('the base font size only ever lands on an offered step', () async {
    final s = (await boot()).settings;
    expect(Settings.fontSizeSteps, contains(s.fontSize));

    // A value between notches snaps to the nearer one rather than sticking.
    s.fontSize = 16.9;
    expect(s.fontSize, 16.0);
    s.fontSize = 17.4;
    expect(s.fontSize, 18.0);

    // And a stale value written by an older build still reads as a notch.
    final legacy = (await boot({'flutter.font_size': 15.3})).settings;
    expect(Settings.fontSizeSteps, contains(legacy.fontSize));
  });

  testWidgets('the appearance page offers the renamed, restyled controls',
      (tester) async {
    final stores = await boot();
    await tester.pumpWidget(PreferencesApp(stores: stores));
    await tester.pumpAndSettle();

    // Renamed to say what it really drives — headings multiply it.
    expect(find.text('基础字号'), findsOneWidget);
    expect(find.text('字号'), findsNothing);
    // The column-width control is gone in favour of a margin.
    expect(find.text('缩进'), findsOneWidget);
    expect(find.text('列宽'), findsNothing);
    // And wrapping is a switch, defaulting on.
    expect(find.text('自动换行'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    // Base size and indent are both notched — nothing on this page is a
    // free-running slider.
    expect(find.byType(SettingsStepSlider), findsNWidgets(2));
    expect(find.byType(Slider), findsNWidgets(2));
  });

  testWidgets('no control in the settings window draws an outline',
      (tester) async {
    final stores = await boot();
    await tester.pumpWidget(PreferencesApp(stores: stores));
    await tester.pumpAndSettle();

    for (final e in find.byType(DecoratedBox).evaluate()) {
      final d = (e.widget as DecoratedBox).decoration;
      if (d is! BoxDecoration) continue;
      final border = d.border;
      if (border == null) continue;
      // Row dividers are a single bottom edge, and the section card keeps
      // its hairline — an *enclosing* border is what a control must not have.
      // BoxBorder has no left/right getters; isUniform is true only when
      // all four sides are drawn the same, which is what an outline is.
      final enclosing = border.isUniform && border.top != BorderSide.none;
      if (!enclosing) continue;
      final isCard = d.borderRadius == BorderRadius.circular(14);
      expect(
        isCard,
        isTrue,
        reason: 'a control still draws an outline: $d',
      );
    }
  });

  testWidgets('every settings row is exactly the same height, whatever '
      'control it holds', (tester) async {
    final stores = await boot();
    await tester.pumpWidget(PreferencesApp(stores: stores));
    await tester.pumpAndSettle();

    Future<void> checkPage(String sidebarLabel) async {
      // The label appears twice — sidebar item and page heading; the
      // sidebar one comes first in the tree.
      await tester.tap(find.text(sidebarLabel).first);
      await tester.pumpAndSettle();

      // Rows are identified by their label column: a fixed-width SizedBox.
      final labels = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 90 && w.child is Text,
      );
      expect(labels, findsWidgets, reason: '\$sidebarLabel has no rows');

      final heights = <double>{};
      for (final e in labels.evaluate()) {
        final row = find.ancestor(
          of: find.byWidget(e.widget),
          matching: find.byWidgetPredicate((w) => w is SizedBox && w.height == 42),
        );
        expect(row, findsWidgets,
            reason: 'a row on \$sidebarLabel is not the fixed height');
        heights.add(tester.getSize(row.first).height);
      }
      expect(heights, hasLength(1),
          reason: '\$sidebarLabel mixes row heights: \$heights');
    }

    await checkPage('外观');
    await checkPage('快捷键');
  });

  /// The controls a settings row actually holds — scoped to the row's
  /// control slot, so sidebar items and the About page's brand mark (which
  /// share the control radius but are not row controls) stay out of it.
  Finder rowControls() => find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is Align && w.alignment == Alignment.centerRight,
        ),
        matching: find.byWidgetPredicate((w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).borderRadius ==
                BorderRadius.circular(8)),
      );

  testWidgets('every button-like control is the one shared height',
      (tester) async {
    final stores = await boot();
    await tester.pumpWidget(PreferencesApp(stores: stores));
    await tester.pumpAndSettle();

    final heights = <double>{};
    for (final page in ['外观', '快捷键', '关于']) {
      await tester.tap(find.text(page).first);
      await tester.pumpAndSettle();
      for (final e in rowControls().evaluate()) {
        heights.add(tester.getSize(find.byWidget(e.widget).first).height);
      }
    }
    expect(heights, isNotEmpty);
    expect(heights, hasLength(1),
        reason: 'controls come in mixed heights: $heights');
    expect(heights.single, kControlHeight);
  });

  testWidgets('a control never stretches to fill its row', (tester) async {
    final stores = await boot();
    await tester.pumpWidget(PreferencesApp(stores: stores));
    await tester.pumpAndSettle();

    for (final page in ['快捷键', '关于', '外观']) {
      await tester.tap(find.text(page).first);
      await tester.pumpAndSettle();

      // Controls use the 8px control radius; the section card uses 14, so
      // the radius tells the two apart without reaching for private types.
      final controls = find.byWidgetPredicate((w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).borderRadius ==
              BorderRadius.circular(8));

      for (final e in controls.evaluate()) {
        final h = tester.getSize(find.byWidget(e.widget).first).height;
        expect(h, lessThan(42),
            reason: 'a control on $page is ${h}px tall — it has been '
                'stretched to the full row height instead of keeping its '
                'own size');
      }
    }
  });
}
