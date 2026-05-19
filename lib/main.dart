import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'recents.dart';
import 'theme.dart';
import 'widgets/editor_pane.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final recents = await RecentsStore.open();
  runApp(MdEditorApp(recents: recents));
}

class MdEditorApp extends StatelessWidget {
  const MdEditorApp({super.key, required this.recents});
  final RecentsStore recents;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Typen',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: EditorHome(recents: recents),
    );
  }
}

enum SaveStatus { idle, dirty, saving, saved, error }

enum _DirtyAction { save, discard, cancel }

class EditorHome extends StatefulWidget {
  const EditorHome({super.key, required this.recents});
  final RecentsStore recents;

  @override
  State<EditorHome> createState() => _EditorHomeState();
}

class _EditorHomeState extends State<EditorHome> {
  static const MethodChannel _fileOpenChannel =
      MethodChannel('typen/file_open');

  final GlobalKey<EditorPaneState> _paneKey = GlobalKey<EditorPaneState>();

  List<RecentFile> _recents = const [];

  /// Incremented when the document on screen genuinely changes (open / new /
  /// after first save-as that adopts a path). Save-into-existing-file does NOT
  /// bump this — preserves cursor + scroll across saves.
  int _docSession = 0;

  String? _activePath;
  String _initialContent = '';
  String _diskContent = '';
  String _currentContent = '';

  SaveStatus _status = SaveStatus.idle;
  String? _errorMsg;
  EditorMode _mode = EditorMode.wysiwyg;

  @override
  void initState() {
    super.initState();
    _recents = widget.recents.load();
    _fileOpenChannel.setMethodCallHandler(_handleNativeOpen);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapInitialDoc());
  }

  Future<void> _bootstrapInitialDoc() async {
    // Drain anything macOS Launch Services queued before we wired the channel.
    List<String> pending = const [];
    try {
      pending = await _fileOpenChannel
              .invokeListMethod<String>('consumePending') ??
          const [];
    } catch (_) {
      // Channel not available (e.g. non-macOS) — ignore.
    }
    if (pending.isNotEmpty) {
      await _openPath(pending.first, skipDirtyCheck: true);
      return;
    }
    if (_recents.isNotEmpty && File(_recents.first.path).existsSync()) {
      await _openPath(_recents.first.path, skipDirtyCheck: true);
    }
  }

  Future<dynamic> _handleNativeOpen(MethodCall call) async {
    if (call.method == 'openFile' && call.arguments is String) {
      await _openPath(call.arguments as String);
    }
    return null;
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ─── File ops ─────────────────────────────────────────────────────────────
  Future<void> _openPicker() async {
    if (!await _confirmSwitchIfDirty()) return;
    const group = XTypeGroup(
      label: 'Markdown',
      extensions: ['md', 'markdown', 'mdown', 'mkd', 'txt'],
    );
    final XFile? file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    await _openPath(file.path, skipDirtyCheck: true);
  }

  Future<void> _openPath(String path, {bool skipDirtyCheck = false}) async {
    if (!skipDirtyCheck && !await _confirmSwitchIfDirty()) return;
    try {
      final content = await File(path).readAsString();
      final updated = await widget.recents.touch(path);
      if (!mounted) return;
      setState(() {
        _docSession++;
        _recents = updated;
        _activePath = path;
        _initialContent = content;
        _diskContent = content;
        _currentContent = content;
        _status = SaveStatus.idle;
        _errorMsg = null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _status = SaveStatus.error;
        _errorMsg = '打开失败：$err';
      });
    }
  }

  Future<void> _saveAs() async {
    const group = XTypeGroup(
      label: 'Markdown',
      extensions: ['md', 'markdown'],
    );
    final loc = await getSaveLocation(
      acceptedTypeGroups: const [group],
      suggestedName: 'untitled.md',
    );
    if (loc == null) return;
    final path = loc.path;
    if (!mounted) return;
    setState(() {
      _status = SaveStatus.saving;
      _errorMsg = null;
    });
    try {
      await File(path).writeAsString(_currentContent);
      final updated = await widget.recents.touch(path);
      if (!mounted) return;
      // Adopt the path WITHOUT bumping _docSession — editor keeps its current
      // EditorState (and cursor position) since the in-memory content already
      // matches what was written.
      setState(() {
        _recents = updated;
        _activePath = path;
        _initialContent = _currentContent;
        _diskContent = _currentContent;
        _status = SaveStatus.saved;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _status = SaveStatus.error;
        _errorMsg = err.toString();
      });
    }
  }

  Future<void> _clearRecents() async {
    await widget.recents.clearAll();
    if (!mounted) return;
    setState(() => _recents = const []);
  }

  void _onEditorChanged(String content) {
    _currentContent = content;
    final isDirty = content != _diskContent;
    if (isDirty && _status != SaveStatus.dirty) {
      setState(() => _status = SaveStatus.dirty);
    } else if (!isDirty && _status == SaveStatus.dirty) {
      setState(() => _status = SaveStatus.idle);
    }
  }

  Future<void> _commit() async {
    final path = _activePath;
    if (path == null) return;
    if (_currentContent == _diskContent) return;
    final text = _currentContent;
    if (!mounted) return;
    setState(() {
      _status = SaveStatus.saving;
      _errorMsg = null;
    });
    try {
      await File(path).writeAsString(text);
      if (!mounted) return;
      _diskContent = text;
      setState(() => _status = SaveStatus.saved);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _status = SaveStatus.error;
        _errorMsg = err.toString();
      });
    }
  }

  /// Asks the user what to do with unsaved changes before switching docs.
  /// Returns true if it's safe to proceed (saved, discarded, or no changes),
  /// false if the user cancels or the save failed.
  Future<bool> _confirmSwitchIfDirty() async {
    if (_currentContent == _diskContent) return true;
    final docName =
        _activePath == null ? 'Untitled' : p.basename(_activePath!);
    final action = await showDialog<_DirtyAction>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text(
          '有未保存的修改',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          '"$docName" 已修改但未保存。要怎么处理？',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _DirtyAction.cancel),
            child: const Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _DirtyAction.discard),
            child: const Text('放弃',
                style: TextStyle(color: AppColors.coral)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _DirtyAction.save),
            child: const Text('保存',
                style: TextStyle(color: AppColors.gold)),
          ),
        ],
      ),
    );
    switch (action) {
      case _DirtyAction.save:
        if (_activePath == null) {
          await _saveAs();
        } else {
          await _commit();
        }
        return _currentContent == _diskContent;
      case _DirtyAction.discard:
        return true;
      case _DirtyAction.cancel:
      case null:
        return false;
    }
  }

  void _saveNow() {
    if (_activePath == null) {
      _saveAs();
    } else {
      _commit();
    }
  }

  void _toggleMode() {
    final next =
        _mode == EditorMode.wysiwyg ? EditorMode.source : EditorMode.wysiwyg;
    _paneKey.currentState?.switchMode(next);
    setState(() => _mode = next);
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: _buildPlatformMenus(),
      child: Scaffold(
        backgroundColor: AppColors.surface0,
        body: Column(
          children: [
            _TitleBar(
              activePath: _activePath,
              status: _status,
              errorMsg: _errorMsg,
              mode: _mode,
              onToggleMode: _toggleMode,
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: EditorPane(
                key: ValueKey(_docSession),
                initialContent: _initialContent,
                mode: _mode,
                onChanged: _onEditorChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PlatformMenuItem> _buildPlatformMenus() {
    // macOS app menu (about / hide / quit), then File / View.
    return [
      const PlatformMenu(
        label: 'Typen',
        menus: [
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.about,
          ),
          PlatformMenuItemGroup(members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.servicesSubmenu,
            ),
          ]),
          PlatformMenuItemGroup(members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hide,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hideOtherApplications,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.showAllApplications,
            ),
          ]),
          PlatformMenuItemGroup(members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.quit,
            ),
          ]),
        ],
      ),
      PlatformMenu(
        label: '文件',
        menus: [
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(
              label: '打开…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
              ),
              onSelected: _openPicker,
            ),
            PlatformMenu(
              label: '打开最近',
              menus: _buildRecentMenuItems(),
            ),
          ]),
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(
              label: _activePath == null ? '保存…' : '保存',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
              ),
              onSelected: _saveNow,
            ),
          ]),
        ],
      ),
      PlatformMenu(
        label: '视图',
        menus: [
          PlatformMenuItem(
            label: _mode == EditorMode.wysiwyg ? '切换到源码模式' : '切换到 WYSIWYG',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.slash,
              meta: true,
            ),
            onSelected: _toggleMode,
          ),
          const PlatformMenuItemGroup(members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.toggleFullScreen,
            ),
          ]),
        ],
      ),
      const PlatformMenu(
        label: '窗口',
        menus: [
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.minimizeWindow,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.zoomWindow,
          ),
        ],
      ),
    ];
  }

  List<PlatformMenuItem> _buildRecentMenuItems() {
    if (_recents.isEmpty) {
      return const [
        PlatformMenuItem(label: '（暂无）', onSelected: null),
      ];
    }
    final items = <PlatformMenuItem>[
      for (final r in _recents)
        PlatformMenuItem(
          label: p.basename(r.path),
          onSelected: () => _openPath(r.path),
        ),
    ];
    return [
      ...items,
      PlatformMenuItemGroup(members: [
        PlatformMenuItem(label: '清空最近列表', onSelected: _clearRecents),
      ]),
    ];
  }
}

// ─── Slim title bar ─────────────────────────────────────────────────────────

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.activePath,
    required this.status,
    required this.errorMsg,
    required this.mode,
    required this.onToggleMode,
  });

  final String? activePath;
  final SaveStatus status;
  final String? errorMsg;
  final EditorMode mode;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    final isUntitled = activePath == null;
    final filename = isUntitled ? 'Untitled' : p.basename(activePath!);

    return Container(
      height: 38,
      color: AppColors.surface0,
      padding: const EdgeInsets.fromLTRB(96, 0, 14, 0),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: Text(
                filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isUntitled
                      ? AppColors.textMuted
                      : AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          _StatusChip(status: status, errorMsg: errorMsg),
          const SizedBox(width: 10),
          _ModePill(mode: mode, onTap: onToggleMode),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.errorMsg});
  final SaveStatus status;
  final String? errorMsg;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (status) {
      SaveStatus.idle => ('', AppColors.textMuted),
      SaveStatus.dirty => ('●', AppColors.gold),
      SaveStatus.saving => ('保存中', AppColors.textMuted),
      SaveStatus.saved => ('✓', AppColors.emerald),
      SaveStatus.error => ('!', AppColors.coral),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: switch (status) {
        SaveStatus.dirty => '未保存（⌘S 保存）',
        SaveStatus.saving => '保存中',
        SaveStatus.saved => '已保存',
        SaveStatus.error => errorMsg ?? '保存失败',
        _ => '',
      },
      child: Container(
        constraints: const BoxConstraints(minWidth: 22),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({required this.mode, required this.onTap});
  final EditorMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSource = mode == EditorMode.source;
    return Tooltip(
      message: '切换模式（⌘/）',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: kAppEase,
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isSource
                  ? AppColors.surface3
                  : AppColors.surface2,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              isSource ? '源码' : 'WYSIWYG',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
