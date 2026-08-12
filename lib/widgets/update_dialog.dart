import 'package:flutter/material.dart';

import '../theme.dart';
import '../update_checker.dart';
import 'dialog_shell.dart';

enum UpdateDialogAction { install, skip, later }

/// Shows the "a new version is available" dialog and returns what the user
/// chose. The caller drives the actual download/install (see `Updater` and
/// `_AboutPage._install`) and persists [skippedUpdateTag] itself — this
/// dialog only asks.
Future<UpdateDialogAction?> showUpdateDialog(
  BuildContext context,
  GitHubRelease release,
) {
  final notes = release.body.trim();
  return showAppDialog<UpdateDialogAction>(
    context,
    title: '发现新版本',
    barrierDismissible: true,
    content: Builder(
      builder: (context) {
        final p = context.palette;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              release.name,
              style: TextStyle(
                color: p.gold,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Text(
                    notes,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    ),
    actions: const [
      DialogAction('跳过此版本', DialogActionKind.plain, UpdateDialogAction.skip),
      DialogAction(
        '以后再说',
        DialogActionKind.secondary,
        UpdateDialogAction.later,
      ),
      DialogAction(
        '立即更新',
        DialogActionKind.primary,
        UpdateDialogAction.install,
      ),
    ],
  );
}

/// Shows the "you're up to date" / "check failed" result of a manual check.
Future<void> showUpToDateDialog(BuildContext context, {required bool failed}) {
  return showAppDialog<void>(
    context,
    barrierDismissible: true,
    title: failed ? '检查更新失败' : '已是最新版本',
    body: failed ? '无法连接到 GitHub，请稍后再试。' : 'Typen 当前已经是最新版本。',
    actions: const [DialogAction('好', DialogActionKind.primary, null)],
  );
}

/// Shows an update-pipeline failure — download, extraction, signature
/// verification, or install all collapse to this single dialog shape.
Future<void> showUpdateFailedDialog(BuildContext context, String message) {
  return showAppDialog<void>(
    context,
    barrierDismissible: true,
    title: '更新失败',
    body: message,
    actions: const [DialogAction('好', DialogActionKind.primary, null)],
  );
}
