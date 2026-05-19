# Proper Markdown Editor

macOS Flutter app — 一个文件级 Markdown 编辑器，WYSIWYG 与源码双模式切换。

从 `garage-task-dashboard` 的 mobile 端"每日收获"日报组件抽出内核，去掉日期导航和 API 绑定，
改成基于本地文件路径的最近列表。

## 功能

- **双模式编辑** — WYSIWYG（基于 `appflowy_editor`）↔ 源码（纯 markdown），切换无损往返
- **自动保存** — 编辑后 800ms 防抖写盘，状态栏实时显示（未保存 / 保存中 / 已保存 / 失败）
- **最近文件** — 左侧栏列出最多 30 个最近打开文件，启动时自动恢复上次文件
- **暗色暖色调** — 沿用 Dusk 设计系统（gold/coral/emerald accent）

## 键盘

| 键位 | 作用 |
|---|---|
| `⌘O` | 打开 `.md` 文件 |
| `⌘S` / `⌘Enter` | 立即保存（绕过防抖） |
| `⌘/` | 切换 WYSIWYG / 源码模式 |

## 开发

国内环境需要走镜像：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

flutter pub get
flutter run -d macos
```

## 结构

```
lib/
├── main.dart            # App shell, 文件 I/O, 自动保存, 键盘快捷键
├── theme.dart           # 内联自 garage_core 的 AppColors + kAppEase
├── recents.dart         # 最近文件 SharedPreferences 持久化
└── widgets/
    ├── editor_pane.dart # WYSIWYG ↔ 源码 切换
    └── sidebar.dart     # 左侧最近列表
```
