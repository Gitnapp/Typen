import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../update_checker.dart';
import 'dialog_shell.dart';

enum _UpdateAction { download, skip, later }

/// Shows the "a new version is available" dialog. Returns once the user has
/// dismissed it; the caller doesn't need the result — [skippedUpdateTag] is
/// persisted internally when the user picks "跳过此版本".
Future<void> showUpdateDialog(
  BuildContext context,
  GitHubRelease release, {
  required void Function(String tag) onSkip,
}) async {
  final notes = release.body.trim();
  final action = await showAppDialog<_UpdateAction>(
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
      DialogAction('跳过此版本', DialogActionKind.plain, _UpdateAction.skip),
      DialogAction('以后再说', DialogActionKind.secondary, _UpdateAction.later),
      DialogAction('前往下载', DialogActionKind.primary, _UpdateAction.download),
    ],
  );
  if (action == _UpdateAction.download) {
    await launchUrl(Uri.parse(release.htmlUrl), mode: LaunchMode.externalApplication);
  } else if (action == _UpdateAction.skip) {
    onSkip(release.tagName);
  }
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
