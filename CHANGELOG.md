# CHANGELOG

## [2026-08-12] v0.3.5 —— 独立偏好设置窗口 + 统一弹窗风格

### 偏好设置改成独立原生窗口

原来的"偏好设置"是编辑器窗口里弹出的一个 `AlertDialog`。现在是一个真正独立的 macOS 窗口：侧边栏多分类导航（外观 / 关于）+ 卡片分组的设置项，标题栏做成沉浸式（去掉不透明标题条，红黄绿按钮悬浮在内容之上）——编辑器窗口的标题栏也统一改成了同样的沉浸风格，两种窗口不再一个有一个没有。

**架构上**：这个窗口是同一套"每窗口一个 Flutter 引擎"模型的第三种实例（此前只有编辑器窗口一种），通过 `FlutterDartProject.dartEntrypointArguments` 传 `--preferences` 参数区分——`main(List<String> args)` 据此决定这个引擎该跑 `TypenApp`（编辑器）还是 `PreferencesApp`（偏好设置），而不是给它单独写一个 Dart entrypoint 函数（后者在 release 构建下会被 tree-shaking 摇掉，除非手动打 `@pragma('vm:entry-point')`，属于本可以绕开的坑）。它是单例，生命周期由 `AppDelegate` 管理但不进 `windows` 注册表——不参与去重、Window 菜单、退出确认这些只有"文档窗口"才需要的策略。

**跨窗口设置同步**：每个窗口引擎都有自己独立的 `SharedPreferences` 内存缓存，在偏好设置里改一项设置，不会让已经打开的编辑器窗口自动看到——这是原有 ADR（`docs/adr/0001-per-window-flutter-engine.md`）里写明的已知代价。这次补上了一条广播：偏好设置发生改动后原生层通知每个编辑器窗口的引擎调用 `Settings.refresh()`（`SharedPreferences.reload()` + `notifyListeners()`），一秒内跟着变。

**代价**：标题栏文字隐藏后，原生的"标题栏图标拖拽存到 Finder"和"⌘点击标题弹出路径面包屑"这两个系统级功能在编辑器窗口上跟着没了——文件名现在只在下面 Dart 画的状态条里显示。

**改动/新增文件：**
- `macos/Runner/PreferencesWindow.swift`（新增）—— 独立窗口 + 独立引擎 + 独立 `typen/native` 通道，只处理 `closeWindow`/`settingsChanged`/`consumePendingCheckUpdates` 这几个精简过的方法
- `macos/Runner/AppDelegate.swift` —— `showPreferences()` 单例创建/前置，`settingsChanged()` 广播循环
- `macos/Runner/EditorWindow.swift` —— 沉浸式标题栏（`titlebarAppearsTransparent` + `fullSizeContentView` + 隐藏标题），新增 `openPreferences`/`notifySettingsChanged` 处理
- `lib/widgets/preferences_window.dart`（新增）—— 侧边栏 + 卡片布局的 Dart UI
- `lib/main.dart` —— `main()` 按 entrypoint 参数分流；标题栏 strip 顶部让出沉浸区，补上文件名显示
- `lib/store.dart` —— `Settings.refresh()`

### ⌘W 只关当前窗口，不再误关背景编辑器

菜单栏属于最后一次渲染它的那个编辑器引擎（`PlatformMenuBar` 每次重建都会整个替换 `NSApp.mainMenu`），偏好设置窗口没有自己的菜单栏。如果不处理，偏好设置聚焦时按 ⌘W，会顺着菜单栏残留的绑定误关到背景里的编辑器窗口，而不是关掉眼前这个。`PreferencesWindow` 重写了 `performKeyEquivalent` 拦截 ⌘W 提前处理，实机验证过：偏好设置聚焦按 ⌘W 只关自己，编辑器不受影响；⌘Q 时哪怕偏好设置开着，该走的未保存确认流程照走不误。

### 检查更新统一走偏好设置

"检查更新…"菜单项原来会在编辑器窗口弹一个独立的 `AlertDialog`，和新版偏好设置的视觉体系脱节。现在手动检查、以及启动时的静默自动检查一旦发现新版本，都会打开（或前置）偏好设置窗口，跳到"关于"页面里显示结果——应用里只有一处会画"检查更新"相关的弹窗。静默检查本身仍然只在编辑器引擎里跑（不合并到偏好设置，否则装了新版本没有的情况也会弹窗），确认真有更新才转过去。

注意：这意味着如果启动时自动发现新版本，偏好设置窗口现在会不打招呼地自己弹出来——这是本次统一弹窗风格的直接结果。

**改动文件：**
- `lib/main.dart` —— `_checkForUpdates` 简化成"手动直接转发 / 自动仍先静默探测再决定要不要转发"
- `lib/native.dart` —— `openPreferencesAndCheckUpdates`、`consumePendingCheckUpdates`、`setPreferencesHandlers`
- `macos/Runner/PreferencesWindow.swift` / `EditorWindow.swift` —— 对称的 pending-flag 握手（照抄 `pendingPaths`/`dartReady`/`consumePendingOpens` 那一套，用在"偏好设置窗口还没启动完，检查更新的请求先存起来"这个场景）

### 所有确认弹窗换了一套统一样式

有未保存的修改 / 文件被其他程序修改 / 文件在别处被修改 / 检查更新结果，这几个原来各写各的 `AlertDialog`，现在共用一套卡片：无边框+阴影，标题加大加粗，按钮分三种——填充色的主操作、描边的次要操作、纯文字的破坏性操作单独挪到最左边和其余按钮拉开距离（不会因为手滑点错挨在一起的按钮），主按钮的文字颜色按当前是深色还是浅色主题取黑或取白，保证金色底色上的对比度。

**新增文件：**
- `lib/widgets/dialog_shell.dart` —— `showAppDialog` + `DialogAction`/`DialogActionKind`，全应用弹窗共用

**改动文件：**
- `lib/main.dart` —— 删掉本地的 `_dialog<T>` helper，三处调用改走共享的 `showAppDialog`
- `lib/widgets/update_dialog.dart` —— 同样改走共享 helper，删掉不再需要的 `_UpdateDialog` 类

### 验证

- `flutter analyze` 0 issue，`flutter test` 72 个测试全过（新增一个用真实 `SharedPreferences` 存储验证 `settingsChanged` 广播确实触发了 reload，而不是碰巧通过）
- 实机验证：偏好设置开关/单例/跨窗口设置同步（拖动字号滑块后编辑器窗口跟着变）、⌘W 只关偏好设置、⌘Q 在偏好设置开着时仍能正确走完未保存确认再退出、"检查更新…"菜单项正确跳转到偏好设置"关于"页并显示"已是最新版本"、三种按钮样式的确认弹窗实际显示效果

## [2026-08-12] v0.3.4 —— 修复预览滚动条真正的抖动根因

v0.3.3 修的是源码视图在触控板回弹（overscroll）时的滚动条抖动——这个是真的，但不是用户实际看到的那个。用真实的 scroll metrics 打日志实测后发现：**预览**模式下滚动混合内容（标题/代码块/列表穿插的文档），`maxScrollExtent` 在滚动过程中持续跳动（同一份文档反复在 5071~5615 之间变化），滑块长度跟着抖——这才是"滚动条长度随滚动变化"的真正来源。

### 根因

`flutter_markdown_plus` 的 `Markdown` 组件把每个块渲染进一个 `ListView`——sliver 机制只测量视口附近的条目，`maxScrollExtent` 在还没量完全部条目之前是按"已量部分的平均高度"外推的估计值。文档里标题、代码块、列表、段落的高度差异越大，这个估计值滚动时跳动得越明显。

### 改动文件

- `lib/widgets/editor_pane.dart` —— 预览改用 `MarkdownBody`（纯 `Column`，一次性量出所有块的精确高度，没有懒加载）套一层自己的 `SingleChildScrollView`，`maxScrollExtent` 从第一帧起就是精确值，不再是滚动时不断修正的估计值
- `test/editor_home_test.dart` —— 随之把测试里定位预览滚动控制器的方式从 `find.byType(Markdown)` 换成 `find.byType(SingleChildScrollView)`

### 验证

- 打临时日志实测：同一份混合内容文档，修复前 `max` 在滚动全程反复跳动（5071~5615），修复后 150 次通知全部是同一个值（5237），零抖动
- 跨段落选中（v0.3.3 修的那个）在换成 `MarkdownBody` 后重新验证：拖选跨越三个独立段落，⌘C 剪贴板内容确认连续，没有回归
- `flutter analyze` 0 issue，`flutter test` 71 个测试全过

### 已知问题，未能复现

用户还报告了"H1 标题作为文档首行时顶部被裁切"的现象。尝试了多种路径复现（默认字号、24pt 大字号、滚动后回到顶部、模拟恢复历史滚动位置重新打开文件）均未能重现，也顺带发现"重新打开文件恢复滚动位置"这条路径在 `_sourceScroll.hasClients` 为 false 时会静默跳过恢复——这是另一个待观察的点，但和标题裁切没有确认的因果关系。这个问题本次没有改动代码，需要更具体的复现步骤（或录屏）才能继续排查。

## [2026-08-12] v0.3.3 —— 修复滚动条闪动 + 预览跨段落选中

### 源码视图滚动时滚动条高度闪动

macOS 触控板的两指滚动会经过 drag/ballistic 手势管线，而不是离散滚轮走的那条被夹住范围的路径，所以滚到文档顶部/底部触发回弹（rubber-band）时，`pixels` 会有几帧短暂越出 `[minScrollExtent, maxScrollExtent]`。`Scrollbar` 每一帧都直接按当前 `ScrollMetrics` 重新计算滚动条滑块长度、不做平滑处理，回弹期间的越界让滑块长度跟着每帧抖动——看起来就是"高度闪动"。

**改动文件：**
- `lib/widgets/editor_pane.dart` —— 源码编辑器的 `TextField` 显式指定 `scrollPhysics: const ClampingScrollPhysics()`，不再用 macOS 默认的 `BouncingScrollPhysics`，`pixels` 全程留在合法范围内，滑块长度就只是 `viewportDimension`/`maxScrollExtent` 的稳定函数

### 预览模式无法跨段落拖选文字

`flutter_markdown_plus` 的 `selectable: true`会给每个块级元素（段落、标题、列表项……）各自套一个独立的 `SelectableText`，互相之间没有共享选区，拖选天然出不了当前块。

**改动文件：**
- `lib/widgets/editor_pane.dart` —— 预览的 `Markdown` 改成 `selectable: false`，外层套 Flutter 自带的 `SelectionArea`，所有渲染出来的 `Text.rich` 就共享同一个连续选区；链接点击不受影响（`TapGestureRecognizer` 挂在 `TextSpan` 上，和 `SelectionArea` 互不冲突）

**验证：**
- `flutter analyze` 0 issue，`flutter test` 71 个测试全过
- 实机验证：预览里拖选跨越两个段落，⌘C 复制出的剪贴板内容确认连续；源码视图滚动到长文档顶部，滑块渲染正常、位置和长度符合预期

## [2026-08-12] v0.3.2 —— Developer ID 签名 + 公证

发布版本现在用 Developer ID Application 证书签名并提交 Apple 公证，下载后的 `Typen.app` 不再被 Gatekeeper 拦截。

**新增文件：**
- `scripts/notarize.sh` —— 一条命令跑完 `flutter build macos --release` → codesign（Hardened Runtime）→ 提交公证 → staple → 校验
- `docs/notarization.md` —— 公证原理、新机器一次性配置步骤（证书、notarytool 凭证）

**改动文件：**
- `README.md` —— 新增 Release 小节，去掉过时的"Unsigned"说明

## [2026-08-11] v0.3.1 —— 修 issue #3 / #4

### ⌘W 关闭窗口快捷键无效（#3）

菜单栏完全由 Dart 的 `PlatformMenuBar` 构建，之前的文件/窗口菜单没有任何一项挂 ⌘W 的 key equivalent——macOS 的快捷键只来自菜单项，窗口不会自动获得 ⌘W，按键被直接丢弃。关闭确认链路本身是通的（`EditorWindow.windowShouldClose` → `confirmClose` → `close()`），只是没有入口到达它。

**改动文件：**
- `lib/main.dart` —— 文件菜单新增"关闭窗口"，`shortcut = ⌘W`，`onSelected: Native.closeWindow`
- `lib/native.dart` —— 新增 `closeWindow()` 包装
- `macos/Runner/EditorWindow.swift` —— `closeWindow` 调用 `performClose(nil)`，走既有的 `windowShouldClose` → `confirmClose` 确认链路，而不是绕过确认直接 `close()`

顺带在 release build 上实测确认了 v0.3.0 那次没能自动化验证的一条：⌘W 关掉最后一个窗口后 App 确实保活，Dock 图标重新打开确实补一个新窗口，复用同一个进程。

### ⌘/ 切换源码/预览视图时滚动位置跳变（#4）

`_toggleMode()`（`lib/main.dart`）原来只是切换 `_mode` 再把焦点交出去。源码 `TextField` 靠 `Offstage` 保持挂载，滚动位置本该没丢；但预览子树只在 `mode == preview` 时才挂载——每次进入预览都是全新的 `Markdown`/`ListView`，`PageStorage` 恢复的是"上一次预览会话"的偏移，跟源码当前位置毫无关系。切回源码时 `_editorFocus.requestFocus()` 又会触发 `EditableText` 的 scroll-to-caret，把视图拉回光标处，而不是刚才阅读的位置。

**改动文件：**
- `lib/main.dart` —— `_toggleMode()` 切换前先记录当前侧的滚动位置为**自身可滚动范围的分数**（不是像素值，因为两侧内容高度不同）；进入预览后在 `addPostFrameCallback` 里按同一分数定位；切回源码则先把光标移到大致对应分数的字符位置，再 `requestFocus()`——EditableText 自带的 scroll-to-caret 这时候会带着视图去到我们想要的地方，而不是回到旧光标位置，绕开了"焦点触发的滚动会覆盖手动设置的偏移"这个根因，而不是在它触发之后再补救（补救过的做法试了一版，会被同一机制反复拉回去，测试能复现）

**新增测试：**
- `test/editor_home_test.dart` —— 200 段长文档滚动到中间，切预览再切回源码，两个方向都断言分数偏移在 5% 容差内

**已知限制（未解决，非本次范围）：**
- 这是"比例映射"，不是内容级映射——源码里图片、代码块等高度差异较大的区块会让两侧的"视觉对应内容"有轻微偏差，Typora 那种精确的逐行映射需要在渲染时给每个 block 打锚点，留到以后再做

## [2026-08-11] v0.3.0 —— 多窗口：一个 Window 一个独立 Document

### 设计

对齐 Typora 的差距分析之外单独立项，走了一遍完整的 grilling + domain-modeling 设计会话（见 `CONTEXT.md`），逐条敲定：Window 与 Document 一一对应；⌘N 保留同窗口新建，⇧⌘N 新增"新建窗口"；Settings/Recents 是全局共享的 Workspace state，但 v1 只做"读取时生效"，不做实时跨窗口推送；同一文件不允许被两个窗口同时打开；关闭所有窗口 App 不退出，只有显式 ⌘Q 才退出；零窗口时点 Dock 图标自动开新窗口；不做"上次退出前开着哪些文件"的会话恢复。

**引擎架构（见 `docs/adr/0001-per-window-flutter-engine.md`）：** 考察了三条路径——Flutter 官方原生多视图 API（`RegularWindowController`，单 isolate 共享状态，代码最干净，但截至 Flutter 3.44 仍是 master channel + `--enable-windowing` 下的实验特性，缺初始背景色、缺首帧信号，不可用于发布）、`desktop_multi_window` 第三方包（成熟度存疑，9 个月未更新，文档建议用 patched fork）、手写多引擎（每个 Window 独立 `FlutterEngine`/`FlutterViewController`/`typen/native` channel 实例）。选了手写多引擎——不可发布的方案和维护存疑的依赖都被排除，符合"选择成熟且维护良好的库，不接受临时权宜方案"的原则。代价：跨窗口没有共享的 Dart 堆，Settings/Recents 的"共享"退化为"每次开窗口时重新读一次"，不是实时推送。

### 实现

**改动文件：**
- `macos/Runner/EditorWindow.swift`（新增，由 `MainFlutterWindow.swift` 重构而来）—— 一个 Window 同时是它自己的注册表条目：自带 `FlutterViewController`（连带自己的 engine）、自己的 `typen/native` channel、`path`/`edited`/`dartReady`/`pendingPaths`。`isEmpty`/`holds(path)` 供去重和复用判断；窗口位置沿用同一个 autosave name，在持有者关闭时交接给下一个窗口
- `macos/Runner/AppDelegate.swift`（重写）—— app 级窗口注册表 + 策略：`newWindow()` 总是开全新窗口；`openPath(path)` 按"已开则前置 → 当前是空白窗口则复用 → 否则新开"的顺序处理，⌘O / Finder 双击 / Recents 菜单统一走这一条；`applicationShouldTerminateAfterLastWindowClosed` 改为 `false`；`applicationShouldHandleReopen` 在零窗口时补一个新窗口；`applicationShouldTerminate` 依次询问每个有未保存修改的窗口，任意一个取消就整体放弃退出
- `macos/Runner/Base.lproj/MainMenu.xib` —— 去掉 nib 里绑定的单例窗口对象，窗口现在完全在代码里创建
- `lib/native.dart` —— 新增 `newWindow()`、`openPath(path)`、`focusWindow(id)`、`pathOpenElsewhere(path)`；新增 `windowsChanged` 原生推送的处理（`WindowInfo` 列表）
- `lib/main.dart` —— 新增"新建窗口"菜单项（⇧⌘N）；⌘O / 打开最近 改为把选中路径交给 `Native.openPath`，不再本地直接加载；新增窗口菜单（Dart 侧渲染，逐窗口 `focusWindow`）；启动时不再自动重开最近文件——否则"新建窗口"每次都会加载最近文件，导致 Empty-window 复用规则永远不生效
- `test/editor_home_test.dart` —— 新增窗口菜单渲染的测试

**验证方式：** release build 上做了大量实测——冷启动单窗口、⇧⌘N 独立开窗、打开已开着的文件自动前置现有窗口、打开另一个文件级联开新窗口、关闭所有窗口 App 存活（pid 确认）、Dock 点击零窗口重开、⌘Q 未保存时阻塞退出并弹提示（截图确认）、窗口位置记忆跨窗口交接。设计合规审查逐条核对 10 项决策，9 项直接通过；抓到一处偏差并修掉——见下。

### 修的一个真 bug：Save As 没走去重

`openPath` 的去重只覆盖"打开"路径，"另存为"到一个别的窗口正开着的路径会绕过去——两个窗口最终指向同一个文件。修法：新增 `AppDelegate.pathOpenElsewhere(path, excluding:)`，Dart 在真正写盘前先查一次，撞了就报错拦下（`该文件已经在另一个窗口中打开，无法另存为同一路径。`），不再静默覆盖。

### 顺带的两处视觉细节

- 编辑区/预览区内容贴着标题栏下沿，看着像被裁切——`contentPadding`/`Markdown.padding` 补回一个 24px 的顶部间距（底部仍然贴边，v0.2.0 那次"去掉固定留白"的改动不受影响）
- 光标（caret）之前跟着 `height: 1.6` 的段落行高走，看起来比字符高一大截——`TextField.cursorHeight` 显式设为 `fontSize * 1.2`，跟段落行高脱钩

**已知限制：**
- Settings / Recents 跨窗口没有实时同步（只在开新窗口时重新读一次），留到下个版本
- 没有 ⌘W 对应的原生"关闭窗口"入口——红色按钮是目前唯一的关闭路径
- 关闭所有窗口后 App 保活 + Dock 重开这条，代码审查确认逻辑正确，但受限于 Flutter 渲染层暴露的无障碍树为空（合成点击/AX 事件都打不到 Flutter 自己画的弹窗和控件），没能用自动化脚本端到端跑通，是人工验证的

## [2026-08-11] v0.2.0 —— 文本即真相：修复会破坏用户文件的编辑模型 + 补齐 macOS 公民身份

### 起因

对照 Typora 做差距分析时，实测发现 v0.1.0 的 ⌘S 会破坏用户文件。用项目自己的 README 片段做往返：

    376 bytes in → 300 bytes out

`` ```bash `` 代码块被整块删除。28 个常见 Markdown 结构里只有 4 个字节一致。

根因有三层：
1. `appflowy_editor` 的 `markdownToDocument` 默认 parser 列表里**没有 code block、没有 HTML**（`document_markdown.dart`），这些块在解析阶段就没了。
2. `DocumentMarkdownEncoder.convert` 对没有对应 parser 的节点**静默丢弃**（`document_markdown_encoder.dart:20` 的 `if (parser != null)`，没有 else）。
3. `documentToMarkdown` 默认 `lineBreak: ''`，块之间不插空行，段落结构整体塌掉。

架构层面的根因：source of truth 是 appflowy 的 `Document`，磁盘上的 markdown 只是它的**有损投影**。对基于文件的编辑器，这个方向是反的。

附带发现：`appflowy_editor` 6.2.0（2025-12-08，最新版）在 Flutter 3.44 上编译失败——`DeltaTextInputService` 未实现 `TextInputClient.onFocusReceived`。仓库当时在最新 stable 上根本 clone 不下来就跑不起来。

### L1 正确性

**改动文件：**
- `pubspec.yaml` — 移除 `appflowy_editor`；包名 `proper_md_editor` → `typen`
- `lib/document_file.dart`（新增）— `DocumentCodec` 纯字节 ↔ 文本转换：BOM / CRLF / 编码全部记录并在写回时还原；UTF-8 解码失败回退 Latin-1（逐字节可逆）而不是报"打开失败"；UTF-16 明确拒绝打开而非静默损坏；`FileStamp` 承担外部变更检测
- `lib/widgets/editor_pane.dart` — WYSIWYG 编辑删除；源码模式成为唯一可编辑模式，预览用已有依赖 `flutter_markdown_plus` 只读渲染
- `lib/widgets/markdown_highlighter.dart`（新增）— `TextEditingController.buildTextSpan` 覆写，在纯文本上画出 Markdown 结构。不变量：painted text ≡ buffer
- `macos/Runner/AppDelegate.swift` — `applicationShouldTerminate` 走 `.terminateLater` + `reply(toApplicationShouldTerminate:)`，先问 Dart；`Data.write(options: .atomic)` 做原子写（沙盒安全、保留原文件属性）；security-scoped bookmark 的创建/解析/释放
- `macos/Runner/MainFlutterWindow.swift` — `windowShouldClose` 同样的确认流程
- `lib/main.dart` — `_writeTo` 写完后重新计算 dirty（原来在 await 期间用户继续输入会导致状态谎报"已保存"）

**解决的问题：**
- ⌘S 不再改动用户没碰过的任何字节
- ⌘Q / ⌘W 有未保存修改时不再静默丢数据
- 写盘不再是 truncate-then-write（崩溃不会留下半个文件）
- 换行符 / BOM / 编码 / 结尾换行全部保留；符号链接写目标而不是替换链接本身
- 别的程序改了同一个文件时提示而不是覆盖；缓冲区干净时自动重载
- `files.bookmarks.app-scope` entitlement 从"声明了但代码里 0 处使用"变成真的用上——此前签名沙盒构建里"打开最近"和"启动恢复上次文件"必然失效

### L2 macOS 公民身份

**改动文件：**
- `macos/Runner/AppDelegate.swift` — 新增 `application(_:open:)`。**这是一个真实 bug**：`FlutterAppDelegate` 实现了 `application:openURLs:`，AppKit 只在 delegate 不响应它时才回退到 `openFile:`/`openFiles:`。所以 v0.1.0 的"注册为 Markdown 文档打开器"从来没有生效过
- `macos/Runner/AppDelegate.swift` — `setDocument` 驱动真实 NSWindow 的 title / representedURL（标题栏文件代理图标）/ isDocumentEdited（关闭按钮上的小圆点）
- `macos/Runner/MainFlutterWindow.swift` — `setFrameAutosaveName` + `setFrameUsingName` 记住窗口位置
- `lib/main.dart` — 补齐「编辑」菜单（撤销/重做/剪切/拷贝/粘贴/全选，通过向 primaryFocus 派发 Flutter Intent 实现）；⌘F / ⌥⌘F / ⌘G / ⇧⌘G 查找替换；⌘N 新建；⇧⌘S 另存为；⌘, 偏好设置；最近文件同名时显示父目录
- `lib/find.dart` + `lib/widgets/find_bar.dart`（新增）— 查找替换（字面/正则、区分大小写、全部高亮、当前项高亮、替换/全部替换）
- `lib/theme.dart` — 重写为 `AppPalette` ThemeExtension，新增浅色配色，跟随系统外观
- `lib/widgets/settings_sheet.dart`（新增）— 主题 / 字号 / 列宽 / 编辑器字体
- `lib/store.dart`（新增，取代 `lib/recents.dart`）— recents（含 bookmark）、按文件的光标与滚动位置、settings
- `lib/main.dart` — 顶部状态条不再重复画文件名（真实标题栏已经有了），改为显示 CRLF / Latin-1 / BOM / 换行符不一致 徽章

**滚动条与留白：**
滚动视口改为占满整个窗口宽度，阅读列靠 `contentPadding` / ListView padding 把内容推进来——所以滚动条贴窗口边，而不是紧贴 760px 内容列。`TextField` 会给每个多行输入强塞一个滚动条且不暴露开关，但它是向环境 `ScrollBehavior` 要的，所以用一个"什么都不画"的 behavior 把它顶掉，再由 pane 自己画一条。预览侧原本**根本没有滚动条**（ListView 没有 controller，MaterialApp 只在移动端装 `PrimaryScrollController`），一并补上。编辑区上下的固定留白去掉。

顺带修掉预览只能用鼠标滚的问题：`ScrollAction` 是从焦点**向上**找 Scrollable 或 `PrimaryScrollController`，所以 focus node 必须在 `PrimaryScrollController` 内侧才能让方向键 / PageUp / PageDown 生效。

**顺带修掉的排版问题：**
v0.1.0 为了让 cursor 和 line box 对齐，全局用了 `lineHeight: 1.0`。对拉丁文只是难看，对中日韩是**字形碰撞**（PingFang SC 的 ascent+descent ≈ 1.34em，强制行盒 1.0em 会让折行时上下行笔画叠在一起）。换成原生 TextField 后这个约束不存在了，正文行高 1.6。

### 测试与 CI

**新增文件：**
- `test/document_codec_test.dart` — 24 个结构的字节级往返 + 磁盘往返、原子写无残留、符号链接、mtime 检测、Latin-1 提升、UTF-16 拒绝
- `test/highlighter_test.dart` — 高亮不改一个字符（含 20 个对抗性输入）、span 连续无重叠
- `test/find_test.dart` — 查找替换逻辑
- `test/editor_home_test.dart` — 端到端：模拟原生侧 `openFile` / `confirmClose`，验证 保存/放弃/取消 三条路径、CRLF+BOM 保留、外部变更拦截
- `.github/workflows/ci.yml` — analyze + test + release build

共 56 个测试。

### 已知未做

- 仍是单窗口。⌘N 在当前窗口开新缓冲区，不是新窗口——真正的多窗口要等 Flutter 的 multi-view
- 未签名 / 未公证 / 无 DMG / 无自动更新（需要 Apple Developer 凭据）
- 混合换行符文件是唯一记录在案的保真例外：保存时统一为主导换行符，标题栏会标出

### 影响范围

编辑模型、文件 IO、原生集成全部重写。没有保留兼容层。

## [2026-05-19] 修复空段落 line-height 不一致 — 给 placeholder 一个 anchor 字符

**改动文件：**
- `lib/widgets/editor_pane.dart` — `placeholderText: (_) => ''` 改成 `' '`（一个空格）；新增 `placeholderTextStyle` 镜像 body TextStyle 的 height/leadingDistribution

**根因：**
`AppFlowyRichText` 渲染段落时有两个 track —— 正文 track（由 delta 内容渲染）和 placeholder track（由 `placeholderText` 渲染）。当段落为空时，正文 track 的 TextSpan 是空的（无 glyph）→ 无法推断 line metrics；placeholder track 用 `placeholderText` 的字符串渲染。如果 placeholderText 是 `''`，placeholder track 也没字符 → 整个 block 的 line box 高度退化（无 glyph 决定 ascent/descent）→ 比有内容的段落 line 矮一截甚至消失。

修复：placeholderText 给一个空格（看不见但有 glyph），加 placeholderTextStyle 用和 body 一样的 16px/1.55/even → 空段落和有内容段落 line metrics 一致。

借助 codex-rescue 确认了 hypothesis 2（placeholder=空字符串导致 metrics 推断失败），sandbox 限制下我手动应用 diff。

**影响范围：**
仅 WYSIWYG 渲染。

## [2026-05-19] 修复 cursor 与文字垂直错位 — 在 TextStyleConfiguration 上配置 lineHeight

**改动文件：**
- `lib/widgets/editor_pane.dart` — `TextStyleConfiguration` 直接配置 `lineHeight: 1.55`, `applyHeightToFirstAscent: true`, `applyHeightToLastDescent: true`, `leadingDistribution: even`；移除内部 `text.height = 1.55`（无效）

**根因：**
1. appflowy_editor 内部在 `rich_text/appflowy_rich_text.dart:557-559` 强制把 `textStyleConfiguration.text.height` 覆盖为 `textStyleConfiguration.lineHeight`（default 1.5）。所以在内部 TextStyle 上设 height 完全无效。
2. `TextStyleConfiguration` 默认 `applyHeightToFirstAscent: false, applyHeightToLastDescent: false`，单行段落的 line box 不应用 height 倍率到首行 ascent 和末行 descent，line box 高度 ≈ 字号自然高度。但 cursor 通过 `RenderParagraph.getFullHeightForCaret()` 计算，包含 leading → cursor 比 line box 高 → 视觉上 cursor 突出。

把 applyHeight* 改成 true 后，line box 也吸收 leading，cursor 和文字 line box 同高。再加上 `leadingDistribution: even`，glyph 居中分布于 line box 中央 → cursor 和文字在同一垂直区间内对齐。

借助了 codex-rescue 定位到 `RenderParagraph.getFullHeightForCaret` 是 cursor 高度的来源，然后我读了 `TextStyleConfiguration` / `appflowy_rich_text.dart` 的实现，确认正确的配置入口在 TextStyleConfiguration 而不是内部 TextStyle。

**影响范围：**
仅 WYSIWYG 编辑器文字渲染。

## [2026-05-19] 修复行距巨大的根因 — EditorStyle.padding 是 per-block 不是 per-editor

**改动文件：**
- `lib/widgets/editor_pane.dart` — `EditorStyle.padding` 从 `fromLTRB(40, 24, 40, 80)` 改为 `symmetric(horizontal: 40)`；外边距改用 `AppFlowyEditor.header/footer` 的 `SizedBox(height: 24/80)` 实现

**根因：**
appflowy_editor 6.x 在 `page_block_component.dart:124-130` 中把 `editorStyle.padding` 应用到 **每一个 block** 而不是编辑器整体。我设的 vertical 24/80 → 每个段落 +104px 死空白。3 个段落就是 312px 空白，所以 "44" 和 "45" 之间看上去隔着无尽虚空。

该库 desktop 默认值 `EdgeInsets.symmetric(horizontal: 100)` 就是这个约定的体现 — 永远不带 vertical。

**影响范围：**
仅 WYSIWYG 排版，但这是前几次"调字号、调行距"调不下去的真凶。

## [2026-05-19] 排版收紧 — 对标 Typora/iA Writer/GitHub-MD 的典型行距

**改动文件：**
- `lib/widgets/editor_pane.dart` — 字号 / 行距 / margin 全面下调（详见下方对比）；标题改用 appflowy_editor 的 `HeadingBlockComponentBuilder.textStyleBuilder`（前一版误用 `configuration.textStyle`，对 heading 不生效，所以"44"看起来还是默认 28px h1）；段落改成 bottom-only margin，避免 margin-collapse 怪行为；占位符 "写下你的想法…" 去掉（聚焦时显示反而干扰）

**对比表（旧 → 新）：**
- 正文 line-height：1.75 → **1.55**
- 段落 padding：vertical 4 → **bottom-only 8**
- 编辑区外 padding：56/48/56/96 → **40/24/40/80**
- 内容列宽：768 → **760**（≈ 65-75ch sweet spot）
- H1：28 / line-height 1.3 / margin 28-top 6-bot → **28 / 1.25 / 28-top 12-bot**
- H2：22 / 1.35 / 24-6 → **22 / 1.3 / 24-10**
- H3：18 / 1.4 / 20-6 → **18 / 1.35 / 20-8**
- 行内代码字号：13.5 → 14

**研究依据：**
横向对比了 Typora（Github / Newsprint / Night）、iA Writer、Bear、Obsidian、github-markdown-css 的实际 CSS。
正文 line-height 共识带是 1.5-1.6，超过 1.65 都"airy"；段落 spacing 共识带 14-24px；
标题 top-margin > bottom-margin，让标题视觉绑到下方内容。

**影响范围：**
仅 WYSIWYG 排版，无功能变化。

## [2026-05-19] 去掉自动保存 — 切文件前问一下

**改动文件：**
- `lib/main.dart` — 删除 800ms debounce Timer 及相关字段；`_onEditorChanged` 只更新 dirty 状态不再写盘；删除 `dart:async` 引入
- `lib/main.dart` — `_flushIfDirty` 重写为 `_confirmSwitchIfDirty`：切换文件/打开新文件前若有未保存修改，弹出 Save/Discard/Cancel 三选一对话框（macOS 标准模式）
- `lib/main.dart` — `_openPath` 加 `skipDirtyCheck` 参数避免 `_openPicker` 重复弹两次确认
- 状态 chip tooltip 文案改为"未保存（⌘S 保存）"，不再说"自动保存中"

**变更说明：**
用户去掉自动保存后，仍要防止"切文件丢数据"这种隐性风险。改成显式三选项对话框 — Save 保存后继续、Discard 丢弃继续、Cancel 留在当前文件。

**影响范围：**
仅交互行为，无 schema/接口变更。

## [2026-05-19] 删除欢迎页 — 启动即编辑器

**改动文件：**
- `lib/main.dart` — 删除 `_WelcomeScreen` / `_OpenButton` / `_RecentRow`（~200 行）；空状态直接渲染空白 `EditorPane`；标题栏文件名为空时显示 "Untitled"（斜体灰色）；模式开关一直可见
- `lib/main.dart` — 新增 `_saveAs()` 用 `getSaveLocation` 选保存位置，无文件时 ⌘S 自动触发"另存为"；保存后采用路径但不重建编辑器（保留光标）
- `lib/main.dart` — 引入 `_docSession` 计数器代替 `ValueKey(_activePath)` 作为 EditorPane 的 key，`_openPath` 时 ++ 强制重建，`_saveAs` 时不变（避免另存为后光标重置）
- 视图菜单的"切换模式"和文件菜单的"保存…"在无文件时也可用

**变更说明：**
欢迎页变成阻塞 — 用户更想要一打开就能写。仿 Typora：默认 "Untitled" 缓冲区，输入后 ⌘S 弹保存对话框。
最近文件仍在系统菜单栏的"打开最近"里。

**影响范围：**
仅 UI 流程。

## [2026-05-19] UI 对标 Typora — 最近文件搬入系统菜单栏

**改动文件：**
- `lib/main.dart` — 删除左侧栏布局；加 `PlatformMenuBar`（文件 / 视图 / 窗口 + 自带 App 菜单），文件菜单含"打开最近"子菜单（动态绑定 _recents）+"清空最近列表"；新增 `_WelcomeScreen` 空状态（图标 + 大按钮 + 居中最近列表）；标题栏从 56px 瘦到 38px；状态用单字符（●/✓/!）；模式开关改成小药丸
- `lib/widgets/editor_pane.dart` — 内容居中限宽 768px（Typora 阅读舒适区）；标题分级（H1 28px / H2 22px / H3 18px）；正文 16px / line-height 1.75；横向 padding 升到 56px
- `lib/recents.dart` — 加 `clearAll()`
- `lib/widgets/sidebar.dart` — 删除（已无侧栏）

**变更说明：**
对标 Typora 的"无侧栏沉浸式"。File → 打开最近 直接放进 macOS 原生菜单栏，符合系统使用习惯；
空状态时把最近列表展示为大卡片，启动即可一键打开。编辑区域居中限宽，标题层级分明，长文阅读舒适。

**已知限制：**
Flutter `PlatformProvidedMenuItemType` 不暴露 cut/copy/paste/undo/redo，所以没有"编辑"菜单 —
键盘快捷键 ⌘C/V/X/Z 仍然有效（Flutter 内部 TextEditingActions 处理）。

**影响范围：**
仅独立项目，UI 重构 + macOS 菜单栏集成。

## [2026-05-19] 项目初始化 — 从 garage-task-dashboard 抽离 Markdown WYSIWYG 组件

**新增文件：**
- `pubspec.yaml` — appflowy_editor / flutter_markdown_plus / markdown / file_selector / shared_preferences
- `lib/theme.dart` — 内联 garage_core 的 Dusk 配色（gold/coral/emerald + surface 0~3）和 `kAppEase`
- `lib/recents.dart` — 基于 SharedPreferences 的最近打开文件存储（最多 30 条）
- `lib/widgets/editor_pane.dart` — 单文档编辑器，WYSIWYG（appflowy_editor）↔ 源码（TextField）切换，无损往返
- `lib/widgets/sidebar.dart` — 左侧 248px 栏，"打开 .md 文件"按钮 + 最近列表（hover 显示移除按钮）
- `lib/main.dart` — App shell：自动打开最近一个文件，⌘O/⌘S/⌘Enter/⌘/ 快捷键，800ms 防抖自动保存
- `macos/Runner/{Debug,Release}.entitlements` — 加 user-selected.read-write + bookmarks.app-scope

**变更说明：**
原 garage-task-dashboard 中 `apps/mobile/lib/src/widgets/daily_note_modal.dart` 把 WYSIWYG 编辑器、
读写状态、日报日期导航绑在一起。把"编辑器 + 防抖保存"内核抽出来，去掉日期导航（替换为基于
文件路径的最近列表），加上一个"源码"模式（直接编辑 markdown 文本），形成独立 macOS 桌面应用。

**影响范围：**
独立项目，对原仓库无影响。
