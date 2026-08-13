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

  testWidgets(
    'hovering an unselected sidebar item shades its background and keeps '
    'the basic (not click) cursor',
    (tester) async {
      final stores = await boot();
      await tester.pumpWidget(PreferencesApp(stores: stores));
      await tester.pumpAndSettle();

      // "外观" is selected by default; "关于" is not — hover that one.
      final aboutRow = find.ancestor(
        of: find.text('关于'),
        matching: find.byType(AnimatedContainer),
      );
      expect(aboutRow, findsOneWidget);

      Color backgroundOf() =>
          (tester.widget<AnimatedContainer>(aboutRow).decoration
                  as BoxDecoration)
              .color!;

      final context = tester.element(find.text('关于'));
      final p = context.palette;
      expect(backgroundOf(), Colors.transparent);

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();

      await gesture.moveTo(tester.getCenter(aboutRow));
      await tester.pumpAndSettle();

      expect(backgroundOf(), p.surface2);

      final region = tester.widget<MouseRegion>(
        find.ancestor(of: aboutRow, matching: find.byType(MouseRegion)).first,
      );
      expect(region.cursor, SystemMouseCursors.basic);

      await gesture.moveTo(const Offset(0, 0));
      await tester.pumpAndSettle();
      expect(backgroundOf(), Colors.transparent);
    },
  );

  testWidgets(
    'a sitting-still hover does not flicker — tiny sub-pixel jitter stays '
    'inside the hovered colour, never bounces back to transparent',
    (tester) async {
      final stores = await boot();
      await tester.pumpWidget(PreferencesApp(stores: stores));
      await tester.pumpAndSettle();

      final aboutRow = find.ancestor(
        of: find.text('关于'),
        matching: find.byType(AnimatedContainer),
      );
      Color backgroundOf() =>
          (tester.widget<AnimatedContainer>(aboutRow).decoration
                  as BoxDecoration)
              .color!;
      final context = tester.element(find.text('关于'));
      final p = context.palette;

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();

      final center = tester.getCenter(aboutRow);
      await gesture.moveTo(center);
      await tester.pumpAndSettle();
      expect(backgroundOf(), p.surface2);

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
          backgroundOf(),
          p.surface2,
          reason: 'flickered back out on jitter step $i',
        );
      }
    },
  );

  testWidgets(
    'hovering the old dead zone just past a row\'s edge still counts as '
    'hovering that row — MouseRegion has to cover its own outer padding',
    (tester) async {
      final stores = await boot();
      await tester.pumpWidget(PreferencesApp(stores: stores));
      await tester.pumpAndSettle();

      final aboutRow = find.ancestor(
        of: find.text('关于'),
        matching: find.byType(AnimatedContainer),
      );
      Color backgroundOf() =>
          (tester.widget<AnimatedContainer>(aboutRow).decoration
                  as BoxDecoration)
              .color!;
      final context = tester.element(find.text('关于'));
      final p = context.palette;

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();

      // Just below the row's own bottom edge — inside the 1.5px padding
      // that used to sit outside MouseRegion (the dead zone between rows).
      final justPastEdge = tester.getBottomLeft(aboutRow) + const Offset(4, 1);
      await gesture.moveTo(justPastEdge);
      await tester.pumpAndSettle();

      expect(backgroundOf(), p.surface2);
    },
  );
}
