import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../update_checker.dart';

enum _UpdateAction { download, skip, later }

/// Shows the "a new version is available" dialog. Returns once the user has
/// dismissed it; the caller doesn't need the result — [skippedUpdateTag] is
/// persisted internally when the user picks "跳过此版本".
Future<void> showUpdateDialog(
  BuildContext context,
  GitHubRelease release, {
  required void Function(String tag) onSkip,
}) async {
  final action = await showDialog<_UpdateAction>(
    context: context,
    barrierColor: Colors.black38,
    builder: (_) => _UpdateDialog(release: release),
  );
  if (action == _UpdateAction.download) {
    await launchUrl(Uri.parse(release.htmlUrl), mode: LaunchMode.externalApplication);
  } else if (action == _UpdateAction.skip) {
    onSkip(release.tagName);
  }
}

/// Shows the "you're up to date" / "check failed" result of a manual check.
Future<void> showUpToDateDialog(BuildContext context, {required bool failed}) {
  return showDialog(
    context: context,
    barrierColor: Colors.black38,
    builder: (context) {
      final p = context.palette;
      return AlertDialog(
        backgroundColor: p.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.border),
        ),
        title: Text(
          failed ? '检查更新失败' : '已是最新版本',
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          failed ? '无法连接到 GitHub，请稍后再试。' : 'Typen 当前已经是最新版本。',
          style: TextStyle(color: p.textSecondary, fontSize: 12.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('好', style: TextStyle(color: p.gold)),
          ),
        ],
      );
    },
  );
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.release});
  final GitHubRelease release;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final notes = release.body.trim();

    return AlertDialog(
      backgroundColor: p.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.border),
      ),
      contentPadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
      title: Text(
        '发现新版本',
        style: TextStyle(
          color: p.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
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
            const SizedBox(height: 4),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, _UpdateAction.skip),
          child: Text('跳过此版本', style: TextStyle(color: p.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _UpdateAction.later),
          child: Text('以后再说', style: TextStyle(color: p.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _UpdateAction.download),
          child: Text('前往下载', style: TextStyle(color: p.gold)),
        ),
      ],
    );
  }
}
