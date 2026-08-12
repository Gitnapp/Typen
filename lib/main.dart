import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'document_file.dart';
import 'find.dart';
import 'native.dart';
import 'store.dart';
import 'theme.dart';
import 'update_checker.dart';
import 'widgets/dialog_shell.dart';
import 'widgets/editor_pane.dart';
import 'widgets/find_bar.dart';
import 'widgets/markdown_highlighter.dart';
import 'widgets/preferences_window.dart';

/// Every Window boots its own engine from scratch (see
/// `docs/adr/0001-per-window-flutter-engine.md`), so which UI it shows is
/// decided here, from the entrypoint arguments `PreferencesWindow.swift`
/// sets on its `FlutterDartProject` — there is no shared router.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final stores = await Stores.open();
  if (args.contains('--preferences')) {
    runApp(PreferencesApp(stores: stores));
  } else {
    runApp(TypenApp(stores: stores));
  }
}

class TypenApp extends StatelessWidget {
  const TypenApp({super.key, required this.stores});
  final Stores stores;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: stores.settings,
      builder: (context, _) => MaterialApp(
        title: 'Typen',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(AppPalette.light),
        darkTheme: buildAppTheme(AppPalette.dark),
        themeMode: stores.settings.themeMode,
        home: EditorHome(stores: stores),
      ),
    );
  }
}

enum SaveStatus { clean, dirty, saving, saved, error }

enum _DirtyAction { save, discard, cancel }

class EditorHome extends StatefulWidget {
  const EditorHome({super.key, required this.stores});
  final Stores stores;

  @override
  State<EditorHome> createState() => _EditorHomeState();
}

class _EditorHomeState extends State<EditorHome> with WidgetsBindingObserver {
  // ─── The document ─────────────────────────────────────────────────────────
  // `_controller.text` IS the document. Nothing derives it, nothing rewrites
  // it behind the user's back, and it is exactly what reaches the disk.
  late final MarkdownHighlightingController _controller;
  final _undo = UndoHistoryController();
  final _editorFocus = FocusNode(debugLabel: 'editor');
  final _sourceScroll = ScrollController();
  final _previewScroll = ScrollController();
  final _previewFocus = FocusNode(debugLabel: 'preview');

  String? _activePath;
  String _diskText = '';
  DocumentEncoding _encoding = const DocumentEncoding();
  FileStamp? _diskStamp;

  SaveStatus _status = SaveStatus.clean;
  String? _errorMsg;
  EditorMode _mode = EditorMode.source;
  List<RecentFile> _recents = const [];

  /// Every open Window, pushed down by the native side — which owns the list.
  /// Held only to draw the Window menu: `PlatformMenuBar` rewrites the whole
  /// menu bar from Dart on every rebuild, so a native NSMenu cannot survive
  /// there.
  List<WindowInfo> _windows = const [];

  /// True while a modal owned by this state is on screen, so overlapping
  /// triggers (quit + activation check) cannot stack dialogs.
  bool _modalOpen = false;

  // ─── Find & replace ───────────────────────────────────────────────────────
  final _find = FindController();
  final _findQuery = TextEditingController();
  final _findReplace = TextEditingController();
  final _findFocus = FocusNode(debugLabel: 'find');
  bool _findVisible = false;
  bool _showReplace = false;

  bool get _isDirty => _controller.text != _diskText;

  @override
  void initState() {
    super.initState();
    _controller = MarkdownHighlightingController(
      config: HighlightConfig(
        palette: AppPalette.dark,
        fontSize: widget.stores.settings.fontSize,
        monoFamily: EditorPane.monoFamily,
        proportional: widget.stores.settings.proportionalEditorFont,
      ),
    );
    _controller.addListener(_onBufferChanged);
    _recents = widget.stores.recents.load();
    WidgetsBinding.instance.addObserver(this);
    Native.setHandlers(
      onOpenFile: (path) => _openPath(path),
      onConfirmClose: _confirmClose,
      onActivated: _checkExternalChange,
      onWindowsChanged: (windows) {
        if (mounted) setState(() => _windows = windows);
      },
      onSettingsChanged: () => widget.stores.settings.refresh(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onBufferChanged);
    _controller.dispose();
    _undo.dispose();
    _editorFocus.dispose();
    _sourceScroll.dispose();
    _previewScroll.dispose();
    _previewFocus.dispose();
    _find.dispose();
    _findQuery.dispose();
    _findReplace.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  /// A Window either opens the document it was created for, or stays Untitled.
  /// Reopening the last file would make every new Window a duplicate of an
  /// existing one, and would leave no Window Empty for the native open policy
  /// to reuse.
  Future<void> _bootstrap() async {
    final pending = await Native.consumePendingOpens();
    if (pending.isNotEmpty) {
      await _openPath(pending.first, skipDirtyCheck: true);
      return;
    }
    _syncWindow();
  }

  // ─── Buffer <-> chrome ────────────────────────────────────────────────────

  void _onBufferChanged() {
    final next = _isDirty ? SaveStatus.dirty : SaveStatus.clean;
    if (_status != next &&
        _status != SaveStatus.saving &&
        !(_status == SaveStatus.error && next == SaveStatus.dirty)) {
      setState(() => _status = next);
      _syncWindow();
    }
    if (_findVisible) {
      _find.refresh(_controller.text);
      _pushMatches();
    }
  }

  void _syncWindow() => Native.setDocument(path: _activePath, edited: _isDirty);

  String? get _documentDir =>
      _activePath == null ? null : p.dirname(_activePath!);

  // ─── File operations ──────────────────────────────────────────────────────

  Future<void> _newDocument() async {
    if (!await _confirmDiscard()) return;
    _rememberPosition();
    setState(() {
      _activePath = null;
      _encoding = const DocumentEncoding();
      _diskStamp = null;
      _diskText = '';
      _controller.value = const TextEditingValue(text: '');
      _status = SaveStatus.clean;
      _errorMsg = null;
    });
    _syncWindow();
    _editorFocus.requestFocus();
  }

  /// Only the picker is ours — where the chosen path lands (this Window, a
  /// Window already showing it, or a new one) is the native side's call.
  Future<void> _openPicker() async {
    const group = XTypeGroup(
      label: 'Markdown',
      extensions: ['md', 'markdown', 'mdown', 'mkd', 'mkdn', 'txt'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    await Native.openPath(file.path);
  }

  Future<void> _openRecent(RecentFile recent) async {
    // Resolving first is what regains sandbox access, and gives the path the
    // file actually lives at now.
    final path = await widget.stores.recents.resolve(recent);
    if (path == null) {
      setState(() {
        _status = SaveStatus.error;
        _errorMsg = '无法访问「${p.basename(recent.path)}」——沙盒授权已失效，请重新用「打开…」选择它。';
      });
      return;
    }
    await Native.openPath(path);
  }

  Future<void> _openPath(String path, {bool skipDirtyCheck = false}) async {
    if (!skipDirtyCheck && !await _confirmDiscard()) return;
    _rememberPosition();
    final previous = _activePath;
    try {
      final doc = await DocumentFile.read(path);
      if (previous != null && previous != path) {
        // Balance the security-scoped access we took when opening it.
        await Native.bookmarkRelease(previous);
      }
      final recents = await widget.stores.recents.touch(path);
      if (!mounted) return;
      final pos = widget.stores.cursors.get(path);
      final offset = (pos?.offset ?? 0).clamp(0, doc.text.length);
      setState(() {
        _recents = recents;
        _activePath = path;
        _encoding = doc.encoding;
        _diskStamp = doc.stamp;
        _diskText = doc.text;
        _controller.value = TextEditingValue(
          text: doc.text,
          selection: TextSelection.collapsed(offset: offset),
        );
        _status = SaveStatus.clean;
        _errorMsg = null;
      });
      _syncWindow();
      if (pos != null && _sourceScroll.hasClients) {
        _sourceScroll.jumpTo(
          pos.scroll.clamp(0, _sourceScroll.position.maxScrollExtent),
        );
      }
      _editorFocus.requestFocus();
    } on UnsupportedDocumentException catch (err) {
      _reportError(err.message);
    } catch (err) {
      _reportError('打开失败：$err');
    }
  }

  void _reportError(String message) {
    if (!mounted) return;
    setState(() {
      _status = SaveStatus.error;
      _errorMsg = message;
    });
  }

  void _rememberPosition() {
    final path = _activePath;
    if (path == null) return;
    widget.stores.cursors.put(
      path,
      DocumentPosition(
        _controller.selection.baseOffset.clamp(0, _controller.text.length),
        _sourceScroll.hasClients ? _sourceScroll.offset : 0,
      ),
    );
  }

  Future<void> _save() async {
    if (_activePath == null) return _saveAs();
    if (!_isDirty) return;
    if (!await _confirmOverwriteIfChangedOnDisk()) return;
    await _writeTo(_activePath!);
  }

  Future<void> _saveAs() async {
    final loc = await getSaveLocation(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Markdown', extensions: ['md', 'markdown']),
      ],
      suggestedName: _activePath == null
          ? 'untitled.md'
          : p.basename(_activePath!),
    );
    if (loc == null) return;
    var path = loc.path;
    if (p.extension(path).isEmpty) path = '$path.md';
    if (await Native.pathOpenElsewhere(path)) {
      _reportError('该文件已经在另一个窗口中打开，无法另存为同一路径。');
      return;
    }
    await _writeTo(path, adoptPath: true);
  }

  Future<void> _writeTo(String path, {bool adoptPath = false}) async {
    final text = _controller.text;
    setState(() {
      _status = SaveStatus.saving;
      _errorMsg = null;
    });
    try {
      final (stamp, used) = await DocumentFile.write(path, text, _encoding);
      final recents = adoptPath
          ? await widget.stores.recents.touch(path)
          : _recents;
      if (!mounted) return;
      setState(() {
        _recents = recents;
        _activePath = path;
        _encoding = used;
        _diskStamp = stamp;
        _diskText = text;
        // The buffer may have moved on while the write was in flight — never
        // claim "saved" for content that is no longer on screen.
        _status = _isDirty ? SaveStatus.dirty : SaveStatus.saved;
      });
      _syncWindow();
    } catch (err) {
      _reportError('保存失败：$err');
    }
  }

  // ─── Guarding against loss ────────────────────────────────────────────────

  /// True when it is safe to replace what is on screen.
  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final action = await _askDirty();
    switch (action) {
      case _DirtyAction.save:
        await _save();
        return !_isDirty;
      case _DirtyAction.discard:
        return true;
      case _DirtyAction.cancel:
      case null:
        return false;
    }
  }

  /// Called by AppKit before the app quits or the window closes.
  Future<bool> _confirmClose() async {
    final ok = await _confirmDiscard();
    if (ok) _rememberPosition();
    return ok;
  }

  Future<_DirtyAction?> _askDirty() async {
    if (_modalOpen) return _DirtyAction.cancel;
    _modalOpen = true;
    try {
      final name = _activePath == null ? 'Untitled' : p.basename(_activePath!);
      return await showAppDialog<_DirtyAction>(
        context,
        title: '有未保存的修改',
        body: '「$name」已修改但未保存。要怎么处理？',
        actions: const [
          DialogAction('取消', DialogActionKind.secondary, _DirtyAction.cancel),
          DialogAction('放弃', DialogActionKind.destructive, _DirtyAction.discard),
          DialogAction('保存', DialogActionKind.primary, _DirtyAction.save),
        ],
      );
    } finally {
      _modalOpen = false;
    }
  }

  /// Refuses to blow away edits another program made since we last read.
  Future<bool> _confirmOverwriteIfChangedOnDisk() async {
    final path = _activePath;
    if (path == null) return true;
    final now = await FileStamp.of(path);
    if (now == null || _diskStamp == null || _diskStamp!.matches(now)) {
      return true;
    }
    if (_modalOpen || !mounted) return false;
    _modalOpen = true;
    try {
      final choice = await showAppDialog<bool>(
        context,
        title: '文件已被其他程序修改',
        body: '「${p.basename(path)}」在磁盘上的内容比你打开时更新。继续保存会覆盖那些修改。',
        actions: const [
          DialogAction('取消', DialogActionKind.secondary, false),
          DialogAction('仍然覆盖', DialogActionKind.destructive, true),
        ],
      );
      return choice ?? false;
    } finally {
      _modalOpen = false;
    }
  }

  /// The file may have changed while we were in the background.
  Future<void> _checkExternalChange() async {
    final path = _activePath;
    if (path == null || _modalOpen) return;
    final now = await FileStamp.of(path);
    if (now == null || _diskStamp == null || _diskStamp!.matches(now)) return;

    if (!_isDirty) {
      // Nothing of the user's to lose — quietly show the newer content.
      await _reload(path);
      return;
    }
    if (!mounted) return;
    _modalOpen = true;
    try {
      final reload = await showAppDialog<bool>(
        context,
        title: '文件已在别处被修改',
        body: '「${p.basename(path)}」的磁盘内容变了，而你这里也有未保存的修改。',
        actions: const [
          DialogAction('保留我的修改', DialogActionKind.secondary, false),
          DialogAction('放弃并重新载入', DialogActionKind.destructive, true),
        ],
      );
      if (reload == true) await _reload(path);
    } finally {
      _modalOpen = false;
    }
  }

  // ─── Update check ───────────────────────────────────────────────────────
  // Every open Window runs its own engine and its own copy of this state, so
  // an automatic check on launch is throttled through Settings — otherwise
  // opening several Windows at once would fire one GitHub request each. All
  // of the *showing* — the found/up-to-date/failed dialogs — happens in the
  // Preferences window's 关于 page instead of here, so there is exactly one
  // place in the app that draws an update dialog. A manual check just
  // redirects there; the automatic one still runs its own silent probe
  // first, so a launch with nothing new never pops a window open.
  static const _autoCheckInterval = Duration(hours: 20);

  Future<void> _checkForUpdates({bool manual = false}) async {
    if (manual) {
      Native.openPreferencesAndCheckUpdates();
      return;
    }

    final settings = widget.stores.settings;
    final last = settings.lastUpdateCheckAt;
    if (last != null && DateTime.now().difference(last) < _autoCheckInterval) {
      return;
    }

    settings.lastUpdateCheckAt = DateTime.now();
    final release = await const UpdateChecker().fetchLatest();
    if (release == null || !mounted) return;

    final currentVersion = (await PackageInfo.fromPlatform()).version;
    if (!mounted || !isNewerVersion(release.tagName, currentVersion)) return;
    if (release.tagName == settings.skippedUpdateTag) return;

    Native.openPreferencesAndCheckUpdates();
  }

  Future<void> _reload(String path) async {
    try {
      final doc = await DocumentFile.read(path);
      if (!mounted) return;
      final offset = _controller.selection.baseOffset.clamp(0, doc.text.length);
      setState(() {
        _encoding = doc.encoding;
        _diskStamp = doc.stamp;
        _diskText = doc.text;
        _controller.value = TextEditingValue(
          text: doc.text,
          selection: TextSelection.collapsed(offset: offset),
        );
        _status = SaveStatus.clean;
      });
      _syncWindow();
    } catch (err) {
      _reportError('重新载入失败：$err');
    }
  }

  // ─── Find & replace ───────────────────────────────────────────────────────

  void _openFind({bool replace = false}) {
    final selection = _controller.selection;
    final seed = selection.isValid && !selection.isCollapsed
        ? _controller.text.substring(selection.start, selection.end)
        : _findQuery.text;
    setState(() {
      _findVisible = true;
      _showReplace = replace || _showReplace;
      _findQuery.text = seed;
      _findQuery.selection = TextSelection(
        baseOffset: 0,
        extentOffset: seed.length,
      );
    });
    _find.update(_controller.text, query: seed, anchor: selection.baseOffset);
    _pushMatches();
    // `autofocus` is a no-op while another node in the scope already has
    // focus, which the editor always does — so take focus after the bar is
    // actually in the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _findFocus.requestFocus();
      _findQuery.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _findQuery.text.length,
      );
    });
  }

  void _closeFind() {
    setState(() => _findVisible = false);
    _find.clear();
    _controller.setMatches(const [], -1);
    _editorFocus.requestFocus();
  }

  void _pushMatches() => _controller.setMatches(_find.matches, _find.current);

  void _onQueryChanged(String q) {
    _find.update(
      _controller.text,
      query: q,
      anchor: _controller.selection.baseOffset,
    );
    _pushMatches();
    _revealCurrent(focusEditor: false);
  }

  void _stepFind(int delta) {
    if (!_findVisible) {
      _openFind();
      return;
    }
    if (_find.step(delta) == null) return;
    _pushMatches();
    _revealCurrent();
  }

  void _revealCurrent({bool focusEditor = true}) {
    final range = _find.currentRange;
    if (range == null) return;
    _controller.selection = TextSelection(
      baseOffset: range.start,
      extentOffset: range.end,
    );
    if (focusEditor) _editorFocus.requestFocus();
  }

  void _replaceCurrent() {
    _find.replacement = _findReplace.text;
    final result = _find.replaceCurrent(_controller.text);
    if (result == null) return;
    final (text, caret) = result;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );
    _find.refresh(text, anchor: caret);
    _pushMatches();
    _revealCurrent(focusEditor: false);
  }

  void _replaceAll() {
    _find.replacement = _findReplace.text;
    final result = _find.replaceAll(_controller.text);
    if (result == null) return;
    final (text, caret) = result;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );
    _find.refresh(text);
    _pushMatches();
  }

  // ─── View ─────────────────────────────────────────────────────────────────

  void _toggleMode() {
    final next = _mode == EditorMode.source
        ? EditorMode.preview
        : EditorMode.source;
    // Neither pane maps a scroll offset to the other's content, so position
    // is carried across as a fraction of each side's own scroll extent —
    // close enough for continuous prose, and exact for "leave, come back".
    final fraction = _scrollFraction(
      _mode == EditorMode.source ? _sourceScroll : _previewScroll,
    );
    setState(() => _mode = next);
    if (next == EditorMode.preview) {
      // The offstage field must not keep the keyboard — and handing focus to
      // the preview is what makes the arrow and page keys scroll it. The
      // preview only just mounted, so its scroll metrics aren't laid out
      // until the next frame.
      _previewFocus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _settleFraction(_previewScroll, fraction);
      });
    } else {
      // EditableText keeps the caret on screen for as long as it holds
      // focus, so restoring the scroll offset *after* focusing is a fight
      // it always wins — every correction gets scrolled right back to the
      // caret. Placing the caret at roughly the same fraction first means
      // that built-in scroll-into-view already lands where we want it.
      final text = _controller.text;
      final approx = (text.length * fraction).round().clamp(0, text.length);
      _controller.selection = TextSelection.collapsed(offset: approx);
      _editorFocus.requestFocus();
    }
  }

  double _scrollFraction(ScrollController controller) {
    if (!controller.hasClients) return 0;
    final max = controller.position.maxScrollExtent;
    return max <= 0 ? 0 : (controller.offset / max).clamp(0.0, 1.0);
  }

  void _jumpToFraction(ScrollController controller, double fraction) {
    if (!controller.hasClients) return;
    controller.jumpTo(fraction * controller.position.maxScrollExtent);
  }

  /// Re-applies [_jumpToFraction] across a few more frames — local images in
  /// the preview lay out at zero height until decoded, so `maxScrollExtent`
  /// on the jump's first frame can still be short of its settled value.
  /// Stops as soon as `maxScrollExtent` stops changing between frames.
  void _settleFraction(
    ScrollController controller,
    double fraction, {
    int passesLeft = 4,
  }) {
    if (!controller.hasClients) return;
    final before = controller.position.maxScrollExtent;
    _jumpToFraction(controller, fraction);
    if (passesLeft <= 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients ||
          controller.position.maxScrollExtent == before) {
        return;
      }
      _settleFraction(controller, fraction, passesLeft: passesLeft - 1);
    });
  }

  void _dispatch(Intent intent) {
    final ctx = primaryFocus?.context;
    if (ctx != null) Actions.maybeInvoke(ctx, intent);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PlatformMenuBar(
      menus: _menus(),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_findVisible) _closeFind();
          },
        },
        child: Scaffold(
          backgroundColor: palette.surface0,
          body: Column(
            children: [
              _TitleBar(
                title: _activePath == null ? 'Untitled' : p.basename(_activePath!),
                status: _status,
                errorMsg: _errorMsg,
                encoding: _encoding,
                mode: _mode,
                onToggleMode: _toggleMode,
              ),
              Divider(height: 1, color: palette.border),
              if (_findVisible)
                ListenableBuilder(
                  listenable: _find,
                  builder: (context, _) => FindBar(
                    controller: _find,
                    queryFocus: _findFocus,
                    queryController: _findQuery,
                    replaceController: _findReplace,
                    showReplace: _showReplace,
                    onQueryChanged: _onQueryChanged,
                    onToggleOption: ({caseSensitive, useRegex}) {
                      _find.update(
                        _controller.text,
                        caseSensitive: caseSensitive,
                        useRegex: useRegex,
                      );
                      _pushMatches();
                    },
                    onStep: _stepFind,
                    onReplace: _replaceCurrent,
                    onReplaceAll: _replaceAll,
                    onToggleReplace: () =>
                        setState(() => _showReplace = !_showReplace),
                    onClose: _closeFind,
                  ),
                ),
              Expanded(
                child: EditorPane(
                  controller: _controller,
                  undoController: _undo,
                  focusNode: _editorFocus,
                  scrollController: _sourceScroll,
                  previewScrollController: _previewScroll,
                  previewFocusNode: _previewFocus,
                  mode: _mode,
                  settings: widget.stores.settings,
                  documentDir: _documentDir,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Menu bar ─────────────────────────────────────────────────────────────

  List<PlatformMenuItem> _menus() => [
    PlatformMenu(
      label: 'Typen',
      menus: [
        const PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.about,
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: '检查更新…',
              onSelected: () => _checkForUpdates(manual: true),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: '偏好设置…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.comma,
                meta: true,
              ),
              onSelected: Native.openPreferences,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.servicesSubmenu,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hideOtherApplications,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.showAllApplications,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: '文件',
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: '新建',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
              ),
              onSelected: _newDocument,
            ),
            PlatformMenuItem(
              label: '新建窗口',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
                shift: true,
              ),
              onSelected: Native.newWindow,
            ),
            PlatformMenuItem(
              label: '打开…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
              ),
              onSelected: _openPicker,
            ),
            PlatformMenu(label: '打开最近', menus: _recentMenuItems()),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: '关闭窗口',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyW,
                meta: true,
              ),
              onSelected: Native.closeWindow,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: '保存',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
              ),
              onSelected: _save,
            ),
            PlatformMenuItem(
              label: '另存为…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
                shift: true,
              ),
              onSelected: _saveAs,
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: '编辑',
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: '撤销',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
              ),
              onSelected: () => _dispatch(
                const UndoTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
            PlatformMenuItem(
              label: '重做',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ),
              onSelected: () => _dispatch(
                const RedoTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: '剪切',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyX,
                meta: true,
              ),
              onSelected: () => _dispatch(
                const CopySelectionTextIntent.cut(
                  SelectionChangedCause.keyboard,
                ),
              ),
            ),
            PlatformMenuItem(
              label: '拷贝',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyC,
                meta: true,
              ),
              onSelected: () => _dispatch(CopySelectionTextIntent.copy),
            ),
            PlatformMenuItem(
              label: '粘贴',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyV,
                meta: true,
              ),
              onSelected: () => _dispatch(
                const PasteTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
            PlatformMenuItem(
              label: '全选',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyA,
                meta: true,
              ),
              onSelected: () => _dispatch(
                const SelectAllTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: '查找…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyF,
                meta: true,
              ),
              onSelected: _openFind,
            ),
            PlatformMenuItem(
              label: '查找与替换…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyF,
                meta: true,
                alt: true,
              ),
              onSelected: () => _openFind(replace: true),
            ),
            PlatformMenuItem(
              label: '查找下一个',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyG,
                meta: true,
              ),
              onSelected: () => _stepFind(1),
            ),
            PlatformMenuItem(
              label: '查找上一个',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyG,
                meta: true,
                shift: true,
              ),
              onSelected: () => _stepFind(-1),
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: '视图',
      menus: [
        PlatformMenuItem(
          label: _mode == EditorMode.source ? '预览' : '回到源码',
          shortcut: const SingleActivator(LogicalKeyboardKey.slash, meta: true),
          onSelected: _toggleMode,
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.toggleFullScreen,
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: '窗口',
      menus: [
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
          ],
        ),
        if (_windows.isNotEmpty)
          PlatformMenuItemGroup(
            members: [
              // No checkmark exists on PlatformMenuItem, so the key window is
              // marked in the label.
              for (final w in _windows)
                PlatformMenuItem(
                  label: w.isKey ? '✓ ${w.title}' : w.title,
                  onSelected: () => Native.focusWindow(w.id),
                ),
            ],
          ),
      ],
    ),
  ];

  List<PlatformMenuItem> _recentMenuItems() {
    if (_recents.isEmpty) {
      return const [PlatformMenuItem(label: '（暂无）', onSelected: null)];
    }
    // Disambiguate same-named files by showing the parent directory.
    final names = <String, int>{};
    for (final r in _recents) {
      names.update(p.basename(r.path), (v) => v + 1, ifAbsent: () => 1);
    }
    return [
      for (final r in _recents)
        PlatformMenuItem(
          label: (names[p.basename(r.path)] ?? 0) > 1
              ? '${p.basename(r.path)} — ${p.basename(p.dirname(r.path))}'
              : p.basename(r.path),
          onSelected: () => _openRecent(r),
        ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: '清空最近列表',
            onSelected: () async {
              await widget.stores.recents.clearAll();
              if (mounted) setState(() => _recents = const []);
            },
          ),
        ],
      ),
    ];
  }
}

// ─── Slim status strip ──────────────────────────────────────────────────────
// The filename, proxy icon and edited dot now live in the real macOS title
// bar, so this strip only carries what AppKit has no place for.

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.title,
    required this.status,
    required this.errorMsg,
    required this.encoding,
    required this.mode,
    required this.onToggleMode,
  });

  final String title;
  final SaveStatus status;
  final String? errorMsg;
  final DocumentEncoding encoding;
  final EditorMode mode;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 58,
      color: p.surface0,
      // The real title bar is transparent and the traffic lights float over
      // this strip's top ~28px — see `EditorWindow.swift` — so that much is
      // reserved before anything is drawn.
      padding: const EdgeInsets.fromLTRB(14, 28, 14, 0),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 14),
          if (encoding.eol == LineEnding.crlf) const _Badge('CRLF'),
          if (!encoding.isUtf8) const _Badge('Latin-1'),
          if (encoding.hasBom) const _Badge('BOM'),
          if (encoding.mixedEol) const _Badge('换行符不一致', warn: true),
          const Spacer(),
          if (errorMsg != null)
            Flexible(
              child: Text(
                errorMsg!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.coral, fontSize: 11),
              ),
            ),
          const SizedBox(width: 10),
          _StatusChip(status: status),
          const SizedBox(width: 10),
          _ModePill(mode: mode, onTap: onToggleMode),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.warn = false});
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(kRadiusControl),
        border: Border.all(color: warn ? p.coral : p.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: warn ? p.coral : p.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final SaveStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (text, color, tip) = switch (status) {
      SaveStatus.clean => ('', p.textMuted, ''),
      SaveStatus.dirty => ('●', p.gold, '未保存（⌘S 保存）'),
      SaveStatus.saving => ('…', p.textMuted, '保存中'),
      SaveStatus.saved => ('✓', p.emerald, '已保存'),
      SaveStatus.error => ('!', p.coral, '出错了'),
    };
    if (text.isEmpty) return const SizedBox(width: 22);
    return Tooltip(
      message: tip,
      child: SizedBox(
        width: 22,
        child: Text(
          text,
          textAlign: TextAlign.center,
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
    final p = context.palette;
    final isPreview = mode == EditorMode.preview;
    return Tooltip(
      message: '切换模式（⌘/）',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: kAppEase,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: isPreview ? p.surface3 : p.surface2,
              borderRadius: BorderRadius.circular(kRadiusControl),
              border: Border.all(color: p.border),
            ),
            child: Text(
              isPreview ? '预览' : '源码',
              style: TextStyle(
                color: p.textSecondary,
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
