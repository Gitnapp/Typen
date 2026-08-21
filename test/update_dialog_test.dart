import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typen/theme.dart';
import 'package:typen/update_checker.dart';
import 'package:typen/widgets/update_dialog.dart';

void main() {
  const release = GitHubRelease(
    tagName: 'v9.9.9',
    name: 'Typen v9.9.9 — test release',
    htmlUrl: 'https://github.com/Gitnapp/Typen/releases/tag/v9.9.9',
    body: '这是一条测试用的发布说明。',
    assets: [],
  );

  testWidgets('shows the release name, notes, and all three actions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showUpdateDialog(context, release),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text(release.name), findsOneWidget);
    expect(find.text(release.body), findsOneWidget);
    expect(find.text('跳过此版本'), findsOneWidget);
    expect(find.text('以后再说'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    for (final label in ['跳过此版本', '以后再说', '立即更新']) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (widget) => widget is FilledButton || widget is TextButton,
        ),
      );
      expect(tester.getSize(button).height, kControlHeight);
    }
  });

  testWidgets('"跳过此版本" resolves with UpdateDialogAction.skip and closes',
      (tester) async {
    UpdateDialogAction? action;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              action = await showUpdateDialog(context, release);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过此版本'));
    await tester.pumpAndSettle();

    expect(action, UpdateDialogAction.skip);
    expect(find.text('发现新版本'), findsNothing);
  });

  testWidgets('showUpToDateDialog(failed: false) reads as up to date',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showUpToDateDialog(context, failed: false),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('已是最新版本'), findsOneWidget);
    await tester.tap(find.text('好'));
    await tester.pumpAndSettle();
    expect(find.text('已是最新版本'), findsNothing);
  });

  testWidgets('showUpToDateDialog(failed: true) reads as a failure',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showUpToDateDialog(context, failed: true),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('检查更新失败'), findsOneWidget);
  });
}
