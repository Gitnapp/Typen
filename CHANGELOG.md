# CHANGELOG

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
