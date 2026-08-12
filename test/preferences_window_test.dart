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
}
