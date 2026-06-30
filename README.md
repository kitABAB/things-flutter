# Things Flutter

> 用 Flutter 复刻的 **Things 3** 风格任务管理 App —— 一套代码，覆盖 Android / Windows（桌面），并内置 **AI 智能捕获**、**端到端多端同步** 与 **主屏小组件**。

<p>
  <a href="https://github.com/kitABAB/things-flutter/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/kitABAB/things-flutter?sort=semver"></a>
  <a href="https://github.com/kitABAB/things-flutter/actions/workflows/release.yml"><img alt="Build" src="https://github.com/kitABAB/things-flutter/actions/workflows/release.yml/badge.svg"></a>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.12%2B-02569B?logo=flutter">
  <img alt="Platforms" src="https://img.shields.io/badge/platform-Android%20%7C%20Windows-555">
</p>

> ⚠️ 这是一个**学习/兴趣性质的非官方复刻**，与 Cultured Code 及其产品 Things 3 没有任何关联。请勿用于商业用途。

---

## 📖 文档

- [**操作文档（使用指南）**](docs/USAGE.md) —— 从捕获 → 理清 → 组织 → 回顾 → 执行的完整上手教程，含界面图。
- [v0.3 需求文档（PRD）](docs/PRD-0.3.md) —— AI 理清与一键回顾的产品设计。

---

## 功能特性

### 任务管理（对齐 Things 3 心智模型）
- **三大固定视图**：收件箱 / 今天 / 计划 / 随时 / 将来 / 日志。
- **双轴模型**：调度意图（`inbox / anytime / someday` + 起始日期）与生命周期（`open / completed / canceled`）解耦；`今天 / 计划 / 随时` 由起始日期派生，不冗余入库。
- **「今晚」分段**：今天视图分「白天 / 今晚」两段，可**跨段拖拽**移动任务。
- **项目 / 领域 / 标题** 三级组织，项目带进度圆环。
- **死线、提醒、重复**：支持每天 / 工作日 / 每周 / 每月 / 每月最后一天 / 每月第 N 个周几 / 每年等重复规则。
- **标签**：支持层级标签，并可在列表与小组件中**就地筛选**（如「在电脑前」场景）。
- **检查项清单**：单个任务下挂轻量子清单，支持多行粘贴一次性导入。
- **Markdown 备注**，可实时预览。
- **垃圾桶 / 回收**、搜索、深色模式、响应式布局（手机 / 桌面双布局，`> 600px` 切换）。

### 手势与交互
- **魔法加号（Magic Plus）**：悬浮按钮长按可拖拽，投放到「今天 / 今晚 / ……」直接定调度。
- **行内右滑**：快捷「完成 / 取消完成」与「计划」。
- **可拖拽重排**：列表内长按拖动排序，今天视图跨白天/今晚拖拽。
- **自然语言日期**：输入「明天 晚上8点」「下周一」等自动解析。

### AI 智能捕获与理清
- **智能捕获**：把一段自由文本「草拟」成结构化任务草稿（标题 / 调度 / 死线 / 标签 / 子清单），**始终由你确认后再落库**——AI 只做建议，不替你做决定。
- **AI 理清（单条 + 批量）**：收件箱里模糊的念头，由一个很懂 GTD 的「理清教练」对话式追问、整理成可执行的下一步，单条左滑即理清，积压可批量过一遍（支持自动应用高置信度建议）。
- **一键回顾报告**：秒级扫描全库，按「待整理收件箱 / 孵化到期 / 项目缺下一步 / 停滞任务」四维度生成报告并就地处理，附 AI 本周聚焦建议。
- **统一接入层**：所有厂商都走 **OpenAI 兼容的 Chat Completions 协议**，换厂商 = 换 `baseUrl / model / apiKey` 三个值，业务代码零改动。
- **多连接 / 多模型**：可保存多把 Key（多厂商），每把 Key 下挂多个模型，随时切换当前使用的模型；支持一键 `GET /models` 拉取该 Key 支持的模型列表。
- 内置预设：**Gemini / OpenAI / DeepSeek / 自定义**（Kimi、OpenRouter、Groq 等同样兼容）。
- 错误码统一翻译成可操作的中文提示（401/403/404/429/5xx/超时/断网）。
- API Key 通过 `shared_preferences` **本地持久化**，无需每次启动重填。

### 多端同步（可选，默认纯本地）
- 默认全离线，**不配置同步也能完整使用**。
- 两条同步路线任选：
  - **自托管轻量后端**（`server/`，单文件 Node 服务，时间戳 LWW + 增量 seq + 删除墓碑）。
  - **PowerSync + Supabase**（云端实时双向同步，按 `user_id` 行级隔离）。

---

## 下载

前往 [**Releases**](https://github.com/kitABAB/things-flutter/releases/latest) 下载：

| 平台 | 文件 | 说明 |
| --- | --- | --- |
| Android | `things-flutter-<版本>-android.apk` | 直接安装（首次需允许「未知来源」） |
| Windows | `things-flutter-<版本>-windows-x64.zip` | 解压后运行其中的 `.exe` |

> iOS / macOS 见下方[平台支持](#平台支持)。

---

## 从源码构建

### 环境要求
- Flutter SDK `3.12+`（Dart SDK 随附）
- Android：Android SDK + JDK 17
- Windows：Visual Studio 2022，**需勾选「使用 C++ 的桌面开发」并包含 `C++ ATL` 组件**（通知插件依赖）

### 运行
```bash
flutter pub get
flutter run                       # 选择已连接的设备/桌面
```

### 打包
```bash
flutter build apk --release       # Android APK
flutter build windows --release   # Windows 桌面（产物在 build/windows/x64/runner/Release/）
```

### 注入 AI 配置（可选，构建期）
不想在 App 内手填，可在构建时用 `--dart-define` 注入，**绝不写进源码 / git**：
```bash
flutter run \
  --dart-define=AI_API_KEY=你的key \
  --dart-define=AI_PROVIDER=gemini \
  --dart-define=AI_MODEL=gemini-2.5-flash
# 自定义厂商再加：--dart-define=AI_BASE_URL=https://.../v1
```
也可以直接在 App 的「AI 设置」页填写并本地保存。

### 启用云同步（可选，构建期）
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=xxxx \
  --dart-define=POWERSYNC_URL=https://xxxx.powersync.journeyapps.com
```
三者齐全才会进入同步模式，否则保持纯本地。详见 `lib/data/database/sync_config.dart`。

---

## 自托管同步后端

`server/` 提供一个零原生依赖、单文件的同步服务（LWW + 增量 seq + 删除墓碑，持久化到 `data.json`）：

```bash
cd server
npm install
npm start         # 默认 0.0.0.0:4000，可用 PORT 覆盖
npm test          # 端到端测试
```

启动后在 App 的「云同步」页填入 `http://<电脑局域网IP>:4000` 与邮箱即可多端同步（同邮箱视为同账号）。详见 [`server/README.md`](server/README.md)。

---

## 项目结构

```
lib/
├─ main.dart
├─ ai/                      # AI 能力（独立封装，便于扩展厂商）
│  ├─ core/                 #   LLM 客户端接口 / 消息 / 异常
│  ├─ providers/            #   OpenAI 兼容实现
│  ├─ capture/              #   文本 → 任务草稿解析
│  ├─ clarify/              #   AI 理清（GTD 教练式追问 + 结构化建议）
│  ├─ review/               #   一键回顾（全库扫描 + AI 聚焦建议）
│  └─ config/               #   AiConfig / 设置持久化
├─ domain/models/           # 领域模型（Item / Area / Tag / ChecklistItem ...）
├─ data/
│  ├─ database/             # PowerSync schema / 连接器 / 同步配置
│  ├─ repositories/         # 仓储层（CRUD / 重排 / 调度）
│  └─ services/             # 通知 / 日历 / 同步 / 主屏小组件桥接
└─ presentation/
   ├─ layouts/              # 响应式布局入口
   ├─ mobile/ desktop/      # 手机 / 桌面布局
   ├─ screens/              # 各视图与详情页
   ├─ shared/               # 主题 / 复用组件（魔法加号、行、选择器等）
   └─ providers/            # Riverpod 状态

android/                    # 含主屏小组件（4×2 / 2×2）与原生快速捕获 Activity
windows/                    # Windows 桌面工程
server/                     # 可选：自托管同步后端（Node）
design/                     # 高保真设计稿
docs/                       # 操作文档 / PRD / 界面图
.github/workflows/          # 多平台自动发布
```

---

## 技术栈
- **Flutter** + **Riverpod**（状态管理）
- **PowerSync** + **Supabase**（本地 SQLite + 云端同步）
- **home_widget** + 原生 Kotlin（Android 主屏小组件与后台任务）
- **app_links**（深链）、**flutter_local_notifications** + **timezone**（提醒）
- **google_fonts**、**flutter_slidable**、**wolt_modal_sheet**、**flutter_animate**
- AI：自封装 OpenAI 兼容客户端（`http`）

---

## 平台支持

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| Android | ✅ 已发布 | 含主屏小组件、后台完成任务、快速捕获 |
| Windows | ✅ 已发布 | 由 CI 云端构建（自带 ATL 组件） |
| macOS | 🔜 可做 | 需 `flutter create --platforms=macos .` 生成工程，再由 CI（macos runner）出 `.app/.dmg` |
| iOS | 🔜 受限 | 代码可编译，但要让他人安装需 Apple 开发者账号（签名/分发） |

> iOS / macOS 的编译**必须在 macOS 上**，可借助 GitHub Actions 的 `macos-latest` runner 自动化。

---

## 自动发布

仓库配置了 GitHub Actions（[`.github/workflows/release.yml`](.github/workflows/release.yml)）：**推送一个 `v*` 标签即触发**云端编译并把各平台产物上传到对应 Release。

```bash
# 例：发布 0.3
# 1) 在 pubspec.yaml 更新 version
# 2) 打 tag 并推送
git tag v0.3
git push origin v0.3
```

无需本地具备各平台工具链，全部在云端完成。

---

## 致谢与声明

灵感来自 **Things 3**（Cultured Code）。本项目仅用于学习 Flutter 跨平台开发与交互复刻，**非官方、不可商用**，所有商标归各自所有者。
