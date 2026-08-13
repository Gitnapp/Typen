import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../native.dart';
import '../store.dart';
import '../theme.dart';
import '../update_checker.dart';
import '../updater.dart';
import 'settings_controls.dart';
import 'update_dialog.dart';

/// The Preferences window's engine boots straight into this — see `main()`
/// and `docs/adr/0001-per-window-flutter-engine.md`. It runs independently
/// of every Editor Window's engine, so a change made here is pushed out via
/// `Native.notifySettingsChanged()` rather than being visible on its own.
class PreferencesApp extends StatelessWidget {
  const PreferencesApp({super.key, required this.stores});
  final Stores stores;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: stores.settings,
      builder: (context, _) => MaterialApp(
        title: '偏好设置',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(AppPalette.light),
        darkTheme: buildAppTheme(AppPalette.dark),
        themeMode: stores.settings.themeMode,
        home: PreferencesHome(settings: stores.settings),
      ),
    );
  }
}

enum _Category { appearance, about }

class PreferencesHome extends StatefulWidget {
  const PreferencesHome({super.key, required this.settings});
  final Settings settings;

  @override
  State<PreferencesHome> createState() => _PreferencesHomeState();
}

class _PreferencesHomeState extends State<PreferencesHome> {
  _Category _category = _Category.appearance;
  final _aboutKey = GlobalKey<_AboutPageState>();

  @override
  void initState() {
    super.initState();
    // Handlers must be registered before consuming the pending flag, the
    // same ordering `Native.setHandlers` documents for the Editor Window.
    Native.setPreferencesHandlers(onCheckUpdates: _runUpdateCheck);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await Native.consumePendingCheckUpdates()) _runUpdateCheck();
    });
  }

  /// Jumps to 关于 and runs its check — the target of both a fresh Window's
  /// pending flag and an already-open one's native-initiated `checkUpdates`
  /// call.
  void _runUpdateCheck() {
    setState(() => _category = _Category.about);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _aboutKey.currentState?.runCheck();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.surface2,
      body: Row(
        children: [
          _Sidebar(
            selected: _category,
            onSelect: (c) => setState(() => _category = c),
          ),
          Container(width: 1, color: p.border),
          Expanded(
            child: switch (_category) {
              _Category.appearance =>
                _AppearancePage(settings: widget.settings),
              _Category.about =>
                _AboutPage(key: _aboutKey, settings: widget.settings),
            },
          ),
        ],
      ),
    );
  }
}

// ─── Sidebar ────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect});
  final _Category selected;
  final ValueChanged<_Category> onSelect;

  static const _items = [
    (_Category.appearance, CupertinoIcons.paintbrush, '外观'),
    (_Category.about, CupertinoIcons.info, '关于'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 190,
      color: p.surface1,
      // The traffic lights sit over this column — the transparent titlebar
      // means nothing pushes content below them on its own.
      padding: const EdgeInsets.fromLTRB(10, 36, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (cat, icon, label) in _items)
            _SidebarItem(
              icon: icon,
              label: label,
              selected: cat == selected,
              onTap: () => onSelect(cat),
            ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final Color background;
    if (widget.selected) {
      background = p.surface3;
    } else if (_hovered) {
      background = p.surface2;
    } else {
      background = Colors.transparent;
    }
    // MouseRegion has to be the outermost widget, not wrapped inside this
    // padding — otherwise the 1.5px gap between adjacent items is a dead
    // zone neither item's MouseRegion covers, and ordinary mouse jitter
    // crossing it (adjacent rows are only ~3px apart) reads as the hover
    // colour flickering on and off instead of just... hovering.
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(kRadiusControl),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 15,
                  color: widget.selected ? p.textPrimary : p.textSecondary,
                ),
                const SizedBox(width: 9),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: widget.selected ? p.textPrimary : p.textSecondary,
                    fontWeight:
                        widget.selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Shared page chrome ─────────────────────────────────────────────────────

class _PageScaffold extends StatelessWidget {
  const _PageScaffold({required this.title, required this.sections});
  final String title;
  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 34, 28, 30),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            for (final section in sections) ...[
              section,
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.heading, required this.rows});
  final String heading;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            heading.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: p.textMuted,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: p.surface0,
            borderRadius: BorderRadius.circular(kRadiusSurface),
            border: Border.all(color: p.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: p.border,
                    indent: 14,
                    endIndent: 14,
                  ),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: p.textPrimary),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ─── 外观 ────────────────────────────────────────────────────────────────────

class _AppearancePage extends StatefulWidget {
  const _AppearancePage({required this.settings});
  final Settings settings;

  @override
  State<_AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<_AppearancePage> {
  void _commit(VoidCallback change) {
    setState(change);
    Native.notifySettingsChanged();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return _PageScaffold(
      title: '外观',
      sections: [
        _Section(
          heading: '显示',
          rows: [
            _SectionRow(
              label: '主题',
              child: SettingsSegmented<ThemeMode>(
                value: s.themeMode,
                options: const {
                  ThemeMode.system: '跟随系统',
                  ThemeMode.light: '浅色',
                  ThemeMode.dark: '深色',
                },
                onChanged: (v) => _commit(() => s.themeMode = v),
              ),
            ),
          ],
        ),
        _Section(
          heading: '编辑器',
          rows: [
            _SectionRow(
              label: '字号',
              child: SettingsSlider(
                value: s.fontSize,
                min: Settings.minFontSize,
                max: Settings.maxFontSize,
                display: s.fontSize.toStringAsFixed(0),
                onChanged: (v) => setState(() => s.fontSize = v),
                onChangeEnd: (_) => Native.notifySettingsChanged(),
              ),
            ),
            _SectionRow(
              label: '列宽',
              child: SettingsSlider(
                value: s.columnWidth,
                min: Settings.minColumnWidth,
                max: Settings.maxColumnWidth,
                display: s.columnWidth.toStringAsFixed(0),
                onChanged: (v) => setState(() => s.columnWidth = v),
                onChangeEnd: (_) => Native.notifySettingsChanged(),
              ),
            ),
            _SectionRow(
              label: '字体',
              child: SettingsSegmented<bool>(
                value: s.proportionalEditorFont,
                options: const {false: '等宽', true: '比例'},
                onChanged: (v) => _commit(() => s.proportionalEditorFont = v),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── 关于 ────────────────────────────────────────────────────────────────────

class _AboutPage extends StatefulWidget {
  const _AboutPage({super.key, required this.settings});
  final Settings settings;

  @override
  State<_AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<_AboutPage> {
  String _version = '';
  bool _checking = false;
  UpdateProgress? _updateProgress;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  /// Runs a check and shows its result — triggered either by the button
  /// below or, via `PreferencesHome`, by the native side (the manual
  /// "检查更新…" menu item, or an auto-discovered release on launch).
  Future<void> runCheck() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      if (_version.isEmpty) {
        final info = await PackageInfo.fromPlatform();
        if (!mounted) return;
        setState(() => _version = info.version);
      }
      final release = await const UpdateChecker().fetchLatest();
      if (!mounted) return;
      if (release == null) {
        await showUpToDateDialog(context, failed: true);
        return;
      }
      final isNewer = isNewerVersion(release.tagName, _version);
      if (!mounted) return;
      if (!isNewer) {
        await showUpToDateDialog(context, failed: false);
        return;
      }
      final action = await showUpdateDialog(context, release);
      if (!mounted) return;
      if (action == UpdateDialogAction.skip) {
        widget.settings.skippedUpdateTag = release.tagName;
      } else if (action == UpdateDialogAction.install) {
        await _install(release);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// Downloads, verifies, and installs in place, showing progress inline in
  /// the card below rather than inside a dialog — the dialog is already
  /// dismissed by the time this runs. Ends with the app quitting to relaunch
  /// at the new copy; if it returns instead, the user cancelled the install
  /// folder picker or the unsaved-work prompt during quit.
  Future<void> _install(GitHubRelease release) async {
    setState(
      () => _updateProgress = const UpdateProgress(
        UpdateStage.downloading,
        fraction: 0,
      ),
    );
    try {
      await const Updater().run(
        release,
        onProgress: (progress) {
          if (mounted) setState(() => _updateProgress = progress);
        },
      );
    } on UpdateFailure catch (e) {
      if (mounted) await showUpdateFailedDialog(context, e.message);
    } finally {
      if (mounted) setState(() => _updateProgress = null);
    }
  }

  String _progressLabel(UpdateProgress progress) {
    switch (progress.stage) {
      case UpdateStage.downloading:
        final fraction = progress.fraction;
        final pct = fraction == null ? '' : ' ${(fraction * 100).round()}%';
        return '下载中…$pct';
      case UpdateStage.extracting:
        return '解压中…';
      case UpdateStage.verifying:
        return '校验签名…';
      case UpdateStage.installing:
        return '安装中…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _PageScaffold(
      title: '关于',
      sections: [
        _Section(
          heading: 'Typen',
          rows: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: p.surface2,
                      borderRadius: BorderRadius.circular(kRadiusControl),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'T',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: p.gold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Typen',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: p.textPrimary,
                          ),
                        ),
                        Text(
                          _version.isEmpty ? ' ' : 'v$_version',
                          style: TextStyle(fontSize: 11.5, color: p.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (_updateProgress != null)
                    Text(
                      _progressLabel(_updateProgress!),
                      style: TextStyle(color: p.textMuted, fontSize: 12),
                    )
                  else
                    TextButton(
                      onPressed: _checking ? null : runCheck,
                      style: TextButton.styleFrom(
                        foregroundColor: p.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kRadiusControl),
                        ),
                      ),
                      child: Text(
                        _checking ? '检查中…' : '检查更新…',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        _Section(
          heading: '链接',
          rows: [
            _SectionRow(
              label: 'GitHub',
              child: GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse('https://github.com/Gitnapp/Typen'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(
                  'Gitnapp/Typen',
                  style: TextStyle(fontSize: 12.5, color: p.textPrimary),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
