import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typen/store.dart';
import 'package:typen/theme.dart';
import 'package:typen/widgets/preferences_window.dart';

void main() {
  Future<Stores> boot() async {
    SharedPreferences.setMockInitialValues({});
    return Stores.open();
  }

  /// The row's own background box. `.first` because `_Sidebar` is itself a
  /// decorated box further up the tree — the innermost one is the row.
  ///
  /// Deliberately the painted `DecoratedBox`, not the `Container` widget: a
  /// Container's `decoration` field is the *target* value, so reading it
  /// would report the final colour even mid-cross-fade and quietly pass the
  /// "one frame" test below no matter how long an animation ran.
  Finder rowFor(String label) => find
      .ancestor(of: find.text(label), matching: find.byType(DecoratedBox))
      .first;

  Color backgroundOf(WidgetTester tester, Finder row) =>
      (tester.widget<DecoratedBox>(row).decoration as BoxDecoration).color!;

  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    return gesture;
  }

  testWidgets(
    'hovering an unselected sidebar item shades its background and keeps '
    'the basic (not click) cursor',
    (tester) async {
      final stores = await boot();
      await tester.pumpWidget(PreferencesApp(stores: stores));
      await tester.pumpAndSettle();

      // "外观" is selected by default; "关于" is not — hover that one.
      final aboutRow = rowFor('关于');
      final p = tester.element(find.text('关于')).palette;
      expect(backgroundOf(tester, aboutRow), Colors.transparent);

      final gesture = await mouse(tester);
      await gesture.moveTo(tester.getCenter(aboutRow));
      await tester.pumpAndSettle();

      expect(backgroundOf(tester, aboutRow), p.surface2);

      final region = tester.widget<MouseRegion>(
        find.ancestor(of: aboutRow, matching: find.byType(MouseRegion)).first,
      );
      expect(region.cursor, SystemMouseCursors.basic);

      await gesture.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(backgroundOf(tester, aboutRow), Colors.transparent);
    },
  );

  testWidgets(
    'hover lands on its final colour in one frame — no cross-fade through '
    'intermediate colours, which reads as the row changing colour twice',
    (tester) async {
      final stores = await boot();
      await tester.pumpWidget(PreferencesApp(stores: stores));
      await tester.pumpAndSettle();

      final aboutRow = rowFor('关于');
      final p = tester.element(find.text('关于')).palette;

      final gesture = await mouse(tester);
      await gesture.moveTo(tester.getCenter(aboutRow));

      // A single frame, deliberately not pumpAndSettle: an animated fill
      // would still be at (or part-way from) transparent here.
      await tester.pump();
      expect(backgroundOf(tester, aboutRow), p.surface2);

      // And back out, same deal.
      await gesture.moveTo(Offset.zero);
      await tester.pump();
      expect(backgroundOf(tester, aboutRow), Colors.transparent);
    },
  );

  testWidgets(
    'a sitting-still hover does not flicker — tiny sub-pixel jitter stays '
    'inside the hovered colour, never bounces back to transparent',
    (tester) async {
      final stores = await boot();
      await tester.pumpWidget(PreferencesApp(stores: stores));
      await tester.pumpAndSettle();

      final aboutRow = rowFor('关于');
      final p = tester.element(find.text('关于')).palette;

      final gesture = await mouse(tester);
      final center = tester.getCenter(aboutRow);
      await gesture.moveTo(center);
      await tester.pumpAndSettle();
      expect(backgroundOf(tester, aboutRow), p.surface2);

      // A real mouse never sits at the exact same pixel — simulate the
      // sub-pixel noise a trackpad/mouse sensor produces while "still", one
      // frame at a time, and assert the colour never drops back out.
      for (var i = 0; i < 40; i++) {
        final jitter = Offset(
          center.dx + (i.isEven ? 0.4 : -0.4),
          center.dy + (i.isEven ? -0.3 : 0.3),
        );
        await gesture.moveTo(jitter);
        await tester.pump(const Duration(milliseconds: 8));
        expect(
          backgroundOf(tester, aboutRow),
          p.surface2,
          reason: 'flickered back out on jitter step $i',
        );
      }
    },
  );

  testWidgets(
    'clicking a sidebar item actually switches the page, both directions',
    (tester) async {
      final stores = await boot();
      await tester.pumpWidget(PreferencesApp(stores: stores));
      await tester.pumpAndSettle();

      // 外观 is the default page: its own sections are up, 关于's are not.
      expect(find.text('显示'), findsOneWidget);
      expect(find.text('链接'), findsNothing);

      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();
      expect(find.text('链接'), findsOneWidget, reason: 'never reached 关于');
      expect(find.text('显示'), findsNothing);

      await tester.tap(find.text('外观').first);
      await tester.pumpAndSettle();
      expect(find.text('显示'), findsOneWidget, reason: 'could not go back');
      expect(find.text('链接'), findsNothing);
    },
  );

  testWidgets(
    'the whole row is clickable, not just its label — a tap on the row\'s '
    'blank right-hand side still switches page',
    (tester) async {
      final stores = await boot();
      await tester.pumpWidget(PreferencesApp(stores: stores));
      await tester.pumpAndSettle();

      final aboutRow = rowFor('关于');
      // Well right of the "关于" text, inside the row's own painted box.
      final blankSpot = Offset(
        tester.getTopRight(aboutRow).dx - 12,
        tester.getCenter(aboutRow).dy,
      );
      await tester.tapAt(blankSpot);
      await tester.pumpAndSettle();

      expect(find.text('链接'), findsOneWidget);
    },
  );

  testWidgets(
    'hovering the old dead zone just past a row\'s edge still counts as '
    'hovering that row — MouseRegion has to cover its own outer padding',
    (tester) async {
      final stores = await boot();
      await tester.pumpWidget(PreferencesApp(stores: stores));
      await tester.pumpAndSettle();

      final aboutRow = rowFor('关于');
      final p = tester.element(find.text('关于')).palette;

      final gesture = await mouse(tester);
      // Just below the row's own bottom edge — inside the 1.5px padding
      // that used to sit outside MouseRegion (the dead zone between rows).
      await gesture.moveTo(tester.getBottomLeft(aboutRow) + const Offset(4, 1));
      await tester.pumpAndSettle();

      expect(backgroundOf(tester, aboutRow), p.surface2);
    },
  );
}
