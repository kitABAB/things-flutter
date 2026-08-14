# Things 3 Mac 交互基线与 Things Flutter PC 端差距分析

> 文档目的：把 Things 3 Mac 的核心信息架构、功能和交互拆成可验收的产品基线，再对照当前 `things-flutter` 的桌面端实现，形成“无限接近 Things 3”所需的功能清单和实施顺序。
>
> 适用范围：当前项目的 Windows/桌面端（Flutter Desktop）。文档描述的是行为和交互基线，不复制 Things 3 的源代码、品牌资产或专有视觉资源。

## 1. 结论先行

当前项目已经具备 Things 3 的一部分数据骨架：收件箱/今天/计划/随时/将来/日志、项目/领域/标题、任务拖拽、清单、标签、日期/死线/提醒/重复、垃圾桶、搜索、日历事件接口、全局快速捕获和同步。但桌面端目前更像“Flutter 任务列表 + 右侧详情面板”，还不是 Things 3 的“Mac 原生效率工具”。

最影响体感的不是颜色，而是下面六个差距：

1. 桌面工作流没有围绕“选中一行后用键盘完成所有操作”建立。
2. 侧边栏缺少可折叠/可重排的 Areas/Projects、拖入目标和可搜索的隐藏列表。
3. 没有 Things 式底部工具栏、Move 对话框、Duplicate、New Window 和原生菜单命令。
4. 任务/项目没有 Notes 字段，导致截图中的说明、链接和 Markdown 工作流无法成立。
5. 当前 Quick Capture 是“打开 AI 对话”，不是 Things 的普通 Quick Entry；也没有 Autofill。
6. 系统日历目前是空实现，项目虽有 provider/UI 接口，但用户看不到真实日历事件。

建议先完成 P0 的桌面交互和数据模型，再做视觉细节。只做皮肤调整，无法弥补这些结构性差距。

## 2. 参考基线与取证范围

### 2.1 本机 Things 3 Mac 观察结果

已确认 Mac 上存在并运行 `Things3` 进程；开启辅助功能后，能够读取到窗口中的可访问性控件。当前“Things Mac 概览”窗口中识别到的控件包括：

- 新建待办事项
- 新建标题（项目 Heading）
- 快速查找
- 时间（When）
- 移动（Move）
- 新建列表
- 设置
- 打开新窗口

侧边栏当前可见条目：

- 收件箱
- 今天（截图中显示 2 个待办）
- 计划
- 随时
- 某天
- 日志簿
- 废纸篓
- Things Mac 概览
- 工作

用户提供的截图还显示了以下视觉和交互线索：

- 左侧是可调整宽度的浅色侧边栏，系统列表和 Area/Project 分区清晰分隔。
- 主区顶部有项目完成圆环、标题、项目描述和更多菜单。
- 项目内用蓝色 Heading 分组；每个 Heading 右侧有更多菜单。
- 任务行包含复选框、标题，以及 Notes/Checklist/日期等状态图标。
- 窗口底部有固定工具栏，至少包含新建待办、快速捕获、日历/日期、移动和搜索入口。
- 项目内容强调“先读懂信息架构，再按任务完成动作”，而不是把所有编辑项塞进一个详情页。

### 2.2 官方 Mac 行为基线

以下行为以 Cultured Code 的 Things 支持文档为准，并在实现时作为验收参考：

- Mac 版支持完整键盘操作：新建、选择、完成/取消、移动、日期、重复、搜索、导航、标签过滤、窗口控制和 Markdown。
- Quick Entry 可在其他应用中通过全局快捷键打开；Quick Entry with Autofill 可把 Safari/Mail/Finder 当前链接自动写入 Notes，并可直接归档到列表或 Heading。
- Move 对话框支持搜索目标、定位项目 Heading，并可直接创建新项目。
- 拖拽不仅用于列表内排序，也用于把待办/Heading 拖到侧边栏中的 Project/Area。
- 项目支持 Heading；Heading 可以创建、移动、复制、归档，且仅存在于 Project 中。
- Notes 支持 Markdown、任务清单、链接、代码块、查找/替换；标题本身不渲染 Markdown。
- Things 的模板是“可复制的 Project 或带 Checklist 的待办”，而不是单独的模板数据库。
- Today/Upcoming 可显示 Apple Calendar 事件；Apple Reminders 可作为 Inbox 来源。
- 还有 Quick Find 中可搜索进入的 Tomorrow、Deadlines、Repeating、All Projects、Logged Projects 等列表。

## 3. Things 3 Mac 功能与交互清单

### 3.1 桌面窗口、导航和布局

| 能力 | 目标行为 | 交互验收 |
|---|---|---|
| 单窗口工作台 | Sidebar + 主列表 + 底部 Toolbar，内容区域可连续滚动 | 主要操作不依赖跳转到另一页 |
| 侧边栏宽度 | 拖动分隔线改变宽度；可隐藏/显示 | 宽度变化不导致列表布局破坏 |
| 新窗口 | 当前列表、项目或搜索结果可在新窗口打开 | `Cmd/Ctrl + 点击`、快捷键和工具栏均可打开 |
| 系统列表 | Inbox、Today、Upcoming、Anytime、Someday、Logbook、Trash | 侧边栏可直接进入，显示待处理数量 |
| 隐藏列表 | Tomorrow、Deadlines、Repeating、All Projects、Logged Projects | 通过 Quick Find/Type Travel 进入，不强行挤占侧栏 |
| Area/Project 树 | Area 可展开/收起，Project 归属于 Area；支持排序 | `Cmd/Ctrl + 点击` 可展开/收起全部或只聚焦一个 Area |
| 底部 Toolbar | 新建待办、Quick Entry、When、Move、Search 等常用动作常驻 | 选中一行后工具栏动作作用于当前选择 |
| 菜单栏 | File/Edit/View/Window/Help 中的命令可被键盘触发 | 所有重要命令都能从菜单或快捷键找到 |
| Type Travel | 不先点击搜索框，直接输入列表/标签名并回车跳转 | 输入“today”“work”“dead…”可定位目标 |

### 3.2 项目、Area 和 Heading

| 能力 | 目标行为 | 交互验收 |
|---|---|---|
| Project 标题 | 标题可直接编辑；顶部显示完成进度圆环 | 编辑后立即保存，支持撤销/取消 |
| Project Notes | 项目标题下可写说明、链接和 Markdown | Notes 与任务 Notes 的编辑体验一致 |
| Heading | 仅能创建在 Project 中；用于分组里程碑/阶段 | `Shift + Cmd/Ctrl + N` 创建；可将选中待办直接归入 Heading |
| Heading 折叠 | 点击 Heading 收起/展开其下任务 | 状态持久化，切换列表后保持 |
| Heading 菜单 | 新建待办、移动、复制、归档、删除、转 Project | 菜单动作不需要进入单独详情页 |
| Project/Area 排序 | 列表和侧边栏都可拖拽重排 | 顺序跨重启、同步保持 |
| 拖到 Sidebar | 待办拖到 Project/Area；Project 可拖入/移出 Area | 拖拽时显示有效目标与落点反馈 |
| 归档 | Project/Heading 可从当前工作列表隐藏，但数据保留 | 可从搜索/专门列表恢复 |
| 模板 | 通过 Duplicate 复制 Project 或带 Checklist 的待办 | 复制后日期不隐式继承，用户可重新安排 |

### 3.3 待办、Checklist、Notes 和元数据

| 能力 | 目标行为 | 交互验收 |
|---|---|---|
| 待办标题 | 列表内点击/回车展开编辑；再次回车保存并收起 | 不必打开全屏详情页完成普通编辑 |
| 完成/取消 | 点击复选框完成；按住 Option/Alt 可取消 | 完成进入 Logbook，取消保留取消状态 |
| Checklist | 待办内部的轻量步骤清单，可排序、粘贴多行 | `Shift + Cmd/Ctrl + C` 在打开任务中新增清单 |
| Notes | 多行文本、链接、Markdown、代码块、任务清单 | Notes 可搜索；链接可打开；支持查找/替换 |
| When | Inbox、Today、This Evening、指定日期、Anytime、Someday | 通过自然语言或快捷键设置，清除操作明确 |
| Reminder | 绑定 When 的具体时间，支持自然语言输入 | 设提醒前必须有日期；通知可取消/重排 |
| Deadline | 独立于 When，可显示逾期/临近状态 | 支持快捷键按天/周平移 |
| Repeating | 每天、工作日、每周、每月、每年等 | 完成当前实例后生成下一实例，历史可追溯 |
| Tags | 可给任务、Project、Area 添加标签；可继承 | 标签管理、快捷键、单标签/多标签过滤完整 |
| 来源链接 | 从其他应用捕获链接写入 Notes | 打开链接不丢失原始 URL |

### 3.4 批量操作、移动和搜索

| 能力 | 目标行为 | 交互验收 |
|---|---|---|
| 键盘选择 | 上下移动、Shift 扩展、Option/Alt 到首尾、Cmd/Ctrl+A 全选 | 选择态有清晰高亮，不抢占输入框焦点 |
| 批量完成/取消 | 对多个待办一次完成、取消或移入日志 | 操作可撤销或有明确反馈 |
| Move 对话框 | 根据对象类型列出合法目标 | 可搜索 Area/Project/Heading，并可即时新建 Project |
| 复制/粘贴 | 复制待办/Project 后可粘贴为副本或移动到当前位置 | 多行剪贴板可拆成多个待办 |
| 拖拽排序 | 列表内、Heading 内、Sidebar 之间都可拖拽 | 拖拽时目标和落点可预测 |
| Quick Find | 标题、Notes、标签、列表均可搜索 | 结果可回车打开；Cmd/Ctrl+Return 新窗口打开 |
| Notes 内搜索 | 只在当前 Notes 查找；Mac 支持查找/替换 | 光标定位到匹配文本 |
| 多标签过滤 | Cmd/Ctrl 点击多个标签，结果取交集 | Esc 清除过滤态 |

### 3.5 外部捕获、系统整合和自动化

| 能力 | 目标行为 |
|---|---|
| Quick Entry | 在任何应用中用全局快捷键弹出轻量捕获框，保存到 Inbox 或指定目标 |
| Autofill | 从浏览器、邮件、文件管理器读取当前链接/文件并写入 Notes |
| Apple Calendar/系统日历 | Today/Upcoming 中混排日历事件，事件只读、任务可编辑 |
| Apple Reminders Inbox | 指定 Reminders 列表导入 Inbox |
| URL Scheme | 支持 add、show、update、complete、search 等自动化命令 |
| Apple Shortcuts/脚本 | 可创建待办、Project、Heading，查找并展示条目，运行 URL |
| Siri/语音 | 通过系统语音或外部自动化捕获 |
| 同步 | 变更在设备间可靠合并，不因打开/切换窗口丢失 |

## 4. 当前 Things Flutter PC 端盘点

### 4.1 已有能力

当前桌面入口在 `lib/presentation/desktop/layouts/desktop_main_layout.dart`：

- 268px 固定侧边栏，可通过按钮或 `Cmd/Ctrl + \` 隐藏。
- 顶部工具栏提供搜索、AI 理清和“新建”按钮。
- 右侧有任务 Inspector，可直接编辑标题、计划、截止日期、标签，并跳转完整详情。
- `Cmd/Ctrl + N` 新建任务、`Cmd/Ctrl + F` 搜索；直接输入字符会进入搜索。
- 支持响应式手机/桌面布局、暗色主题和全局 Magic Plus。

当前数据层在 `lib/domain/models/item.dart`、`lib/data/database/schema.dart` 和 `lib/data/repositories/item_repository.dart` 中已经有：

- task / project / heading 三种条目类型。
- Inbox / Today / Upcoming / Anytime / Someday / Logbook / Trash 的查询。
- start date、evening、deadline、repeat、reminder_time。
- checklist_items、tags、item_tags、项目/领域继承标签。
- 本地通知、PowerSync/Supabase 或自托管同步、桌面全局快捷捕获。

当前 `ProjectScreen` 已实现进度圆环、Heading 分组、任务和 Heading 的部分拖拽排序、Heading 归档/删除；`TaskDetailScreen` 已实现计划、死线、提醒、重复、移动、标签、Checklist。

### 4.2 差距矩阵

标记：✅ 已有；△ 部分已有但行为/入口不足；❌ 缺失或当前为空实现。

| 功能域 | Things 3 目标 | 当前 PC 端 | 差距判断 |
|---|---|---|---|
| 系统列表 | 7 个固定列表 + 隐藏列表 | 6 个系统视图 + Trash | ✅ 基础；❌ Tomorrow/Deadlines/Repeating/All Projects/Logged Projects |
| Sidebar | 可调整宽度、Area 折叠、排序、拖入 | 固定 268px、隐藏按钮、Area 全展开 | △ 视觉接近但桌面操作不足 |
| Project 描述 | 标题下有 Notes/描述 | 只有标题和进度 | ❌ 数据字段和编辑器都缺 |
| Heading | 创建、移动、复制、归档、折叠 | 创建、部分排序、归档、删除 | △ 缺折叠/复制/跨 Project 移动 |
| 待办 Notes | Markdown、链接、搜索/替换 | `Item` 无 notes 字段 | ❌ 结构性缺口 |
| Checklist | 任务内清单 | 已有增删改和勾选 | ✅ 需要补键盘/排序体验 |
| 日期 | When、Tonight、Deadline、Repeat | 数据和 picker 基本齐 | ✅ 功能基础；△ 缺 Mac 快捷操作和统一弹窗 |
| Reminder | 绑定日期、通知 | 本地通知已接入 | ✅ |
| Tags | 管理器、快捷键、多标签交集过滤 | Picker、层级字段、单标签过滤 | △ 缺管理、快捷键、多选交集 |
| Move | 搜索目标、Heading、即时新建 Project | 只展示 Inbox/Area/Project 列表 | △ 目标搜索与 Heading 缺失 |
| Duplicate/Template | 复制待办、Checklist、Project | 无通用 Duplicate API/入口 | ❌ |
| 拖拽 | 列表/Heading/Sidebar/Area 全链路 | 主要是 Today 和 Project 内排序 | △ |
| 键盘 | 完整选择、移动、日期、导航、Markdown 快捷键 | N/F/侧栏切换 + 全局捕获快捷键 | ❌ 这是最大体感缺口之一 |
| 底部 Toolbar | New/Quick Entry/When/Move/Search | 顶部 New/Search/AI | ❌ |
| 新窗口 | 列表/Project/Search 可新开 | 无 | ❌ |
| Quick Entry | 普通全局捕获 + Autofill | 全局捕获打开 AI 对话 | △ 适合 AI，不等价于 Quick Entry |
| 日历 | 显示系统日历事件 | `CalendarService` 明确返回空列表 | ❌ 当前为 stub |
| Reminders Inbox | 从系统提醒导入 | 无 | ❌ |
| URL/脚本 | 完整 Things URL/Shortcuts/AppleScript | 只有 `things://add` 和 `things://capture` | △ |
| 搜索 | Type Travel、Notes、标签、隐藏列表 | 标题搜索 + 标签提示 | △ |
| 首次教学 | 自带 Things Mac 概览项目 | 未发现默认种子数据 | ❌ |
| 同步 | 可靠多端同步 | PowerSync/自托管同步已存在 | ✅ 基础；需补用户身份和冲突体验 |
| AI | Things 不内置，但可作为增强 | AI Capture/Clarify/Review 很丰富 | ✅ 差异化能力，不应阻塞基础 parity |

## 5. 需要新增或重做的功能

### P0：先让 PC 端“用起来像 Things”

#### P0.1 桌面工作台重构

- 将当前顶部工具栏改为“窗口标题区 + 底部 Toolbar”的双层结构。
- Sidebar 增加可拖动 resize handle、Area 折叠/展开、Project/Area 拖拽排序。
- 引入统一 `DesktopCommandRegistry`，所有命令同时接入菜单、快捷键、右键菜单和 Toolbar。
- 引入 `SelectionController`：维护焦点行、单选/多选、键盘范围选择和 Inspector 状态。
- 支持同一列表打开新窗口；至少先实现“打开当前列表新窗口”和“打开 Project 新窗口”。

验收：只用键盘完成“进入 Inbox → 新建任务 → 设 Today → 移动到 Project → 完成 → 打开 Logbook”，不需要点击顶部按钮或跳详情页。

#### P0.2 补齐 Notes 数据模型

建议给 `items` 增加：

```text
notes TEXT NOT NULL DEFAULT ''
is_collapsed INTEGER NOT NULL DEFAULT 0
```

Notes 可先复用现有 `flutter_markdown_plus` 做预览，编辑状态保留原始 Markdown。Project 和 Task 共用同一 Notes 编辑器；Heading 不需要 Notes。

必须同时补齐：

- `Item.notes`、`Item.isCollapsed`。
- `createTask/createProject/updateContent` 的 Notes 参数。
- `watch/search` 把 Notes 纳入全文搜索。
- Notes 内查找、Markdown 快捷键、链接打开。
- 数据库 schema/远程同步字段和迁移。

#### P0.3 实现 Things 式 Item 行和上下文菜单

桌面端不要把移动端 `Slidable` 作为主要交互。每一行应具备：

- hover 显示操作 affordance；
- 复选框、标题、Notes/Checklist/When/Deadline/Repeat/Tag 图标；
- 单击选中，Return 或双击展开；
- 右键菜单：完成、取消、When、Deadline、Repeat、Move、Duplicate、Copy Link、Trash；
- 多选后 Toolbar/右键菜单作用于全部选择。

#### P0.4 完整 Move 与 Duplicate

新增 `MoveItemsDialog`：

- 搜索 Area、Project、Heading；
- 根据条目类型过滤合法目标；
- 支持从对话框直接新建 Project；
- 支持“移出项目/移到 Inbox”；
- 完成后保留 When/Deadline/Tags/Checklist/Notes。

新增 `duplicateItem`：

- Task：复制标题、Notes、Checklist、Tags、重复规则（日期按产品规则清除或显式询问）；
- Project：复制项目 Notes、Headings、Tasks、Checklist、Tags；
- Heading：复制 Heading 及其任务或作为跨项目移动入口。

#### P0.5 默认教学项目

首次启动创建一个可跳过/可删除的“Things Mac 概览”示例 Project，内容至少包含：

- 了解基础知识：点击待办、创建待办、将待办加入今天；
- 新建标题：创建标题、创建项目、组织领域、完成任务、计划任务；
- 调整设置：日历事件、桌面小组件、快捷键、同步和 AI 设置。

这不是装饰，而是产品的第一条 onboarding 路径；必须能通过真实 UI 操作完成所有示例任务。

### P1：补齐效率能力

#### P1.1 普通 Quick Entry 与 AI Capture 分离

当前全局捕获直接进入 AI 对话，建议拆成两层：

1. `QuickEntryOverlay`：毫秒级写入 Inbox，支持标题、Notes、When、Tag、Move、Checklist。
2. `AICapture`：作为 Quick Entry 中的“AI 整理”按钮或独立快捷键，不阻塞普通捕获。

桌面端要求：

- App 未聚焦时仍能通过全局快捷键弹出；
- `Esc` 丢弃，`Cmd/Ctrl + Enter` 保存；
- 保存后不强制打开主窗口；
- 能捕获剪贴板文本和当前选中的 URL（Windows 先做剪贴板/浏览器协议，Mac 再接 Autofill）。

#### P1.2 真实系统日历

`CalendarService` 当前 `isAvailable=false` 且 `eventsBetween` 永远返回空列表。需要：

- Windows：实现系统日历或 ICS/Outlook 只读 provider；
- Mac：实现 EventKit provider；
- 设置页选择启用的日历；
- Today/Upcoming 将事件以不可编辑行插入任务时间轴；
- 权限拒绝时显示可恢复的设置入口。

#### P1.3 Tags 管理和多标签过滤

- 增加 Tags 管理页：重命名、删除、层级移动、排序、快捷键。
- View 顶部支持多个 Tag chip，结果取交集。
- Project/Area 标签继承显示但可区分“直接标签/继承标签”。
- 搜索支持 `#tag`、标签别名和组合过滤。

#### P1.4 Project/Area 结构交互

- Area 展开状态持久化；
- Sidebar 允许拖动 Project 跨 Area；
- Project 内 Heading 可折叠、跨 Project Move、Duplicate、转换为 Project；
- 支持显示/隐藏 Later 项目和已归档 Heading。

#### P1.5 键盘命令覆盖

至少实现下面几组（Windows 使用 Ctrl，Mac 使用 Cmd）：

| 分组 | 快捷键 |
|---|---|
| 创建 | `N` 新建待办、`Alt/Option+Cmd/Ctrl+N` 新建 Project、`Shift+Cmd/Ctrl+N` 新建 Heading |
| 编辑 | `Return` 打开、`Cmd/Ctrl+Return` 保存收起、`Cmd/Ctrl+D` Duplicate、`Cmd/Ctrl+K` 完成 |
| 选择 | `Shift+↑/↓` 扩展、`Cmd/Ctrl+A` 全选、`Esc` 清除 |
| 移动 | `Shift+Cmd/Ctrl+M` Move、`Cmd/Ctrl+↑/↓` 上下移动 |
| 日期 | `Cmd/Ctrl+S` When、`Cmd/Ctrl+T/E/R/O` Today/Evening/Anytime/Someday、`Shift+Cmd/Ctrl+D` Deadline |
| 导航 | `Cmd/Ctrl+1…6` 系统列表、`Cmd/Ctrl+←/→` 返回/进入 Project |
| 搜索 | `Cmd/Ctrl+F` Search、`Shift+Cmd/Ctrl+F` Notes 查找 |
| 视图 | `Cmd/Ctrl+/` Sidebar、`Option/Alt+Cmd/Ctrl+T` Toolbar、新窗口快捷键 |

快捷键必须以命令注册表为源，不要分散在多个 Widget 的 `CallbackShortcuts` 中。

### P2：外部生态与完成度

- 完整 URL Scheme：add/show/update/complete/search，带稳定 item ID。
- Windows 等价自动化：自定义 URI、CLI 或 PowerShell 命令，并提供文档。
- Apple Shortcuts/AppleScript（仅 macOS 构建启用）。
- Apple Reminders/Outlook/ICS 导入。
- Logbook/Trash 的批量恢复、永久删除和筛选。
- 可配置字体大小、行密度、侧边栏显示项和主题色。
- 无障碍语义：每个复选框、行、Toolbar 和拖拽目标都有稳定 label/role。
- 性能 QA：1000/5000 条任务滚动、搜索、同步和批量移动不掉帧。

## 6. 推荐的数据和代码拆分

### 6.1 数据模型

当前 `Item` 同时承担 Task/Project/Heading，短期可继续使用，但建议把桌面 parity 所需字段补齐：

```text
Item.notes
Item.isCollapsed
Item.isArchived       // 不仅是 heading
Item.externalLink     // Quick Entry/Autofill 来源，可选
```

如果后续需要真正支持 Things 的多个特殊列表，建议增加只读派生视图 `SmartList`，不要为 Today/Upcoming 复制任务数据：

```text
SmartList.inbox / today / upcoming / anytime / someday / logbook
SmartList.tomorrow / deadlines / repeating / allProjects / loggedProjects
```

### 6.2 桌面 UI 层

建议把当前 `DesktopMainLayout` 拆为：

```text
DesktopShell
├─ DesktopSidebar
├─ DesktopContent
│  ├─ ListHeader
│  ├─ ItemList
│  └─ ProjectView
├─ DesktopInspector
├─ DesktopToolbar
├─ DesktopCommandRegistry
├─ MoveItemsDialog
├─ QuickEntryOverlay
└─ NewWindowCoordinator
```

`ViewScreen` 和 `ProjectScreen` 应只负责数据/列表呈现；选中、快捷键、菜单和窗口协调移到 shell 层，避免每个页面自己实现一套快捷键。

### 6.3 迁移顺序

1. 先加 schema 字段和 repository API，不改变现有 UI。
2. 加默认教学项目和 Notes/Checklist 编辑能力。
3. 引入统一选中模型、桌面 Item 行、右键菜单、Move、Duplicate。
4. 重做 Sidebar/Toolbar/键盘导航。
5. 接入真实日历和 Quick Entry。
6. 最后补自动化、导入、视觉和性能。

## 7. P0 验收场景

以下场景全部通过，才算桌面端进入“Things 交互基线”阶段：

1. 首次启动能看到“Things Mac 概览”项目；点击其中任务可展开并在列表内编辑。
2. `Ctrl/Cmd+N` 在当前列表创建任务；`Return` 打开；`Ctrl/Cmd+Return` 保存并收起。
3. 多选三个任务，使用 `Move` 搜索到某个 Heading，并保留标题、Notes、Checklist、Tags。
4. 右键任务可完成、取消、设置 When、Deadline、Repeat、Duplicate 和 Trash。
5. 拖动 Project 到另一个 Area，刷新/重启后结构和顺序保持。
6. Project Heading 可以折叠；折叠状态在重启后保持。
7. Notes 支持 Markdown、链接和查找；搜索可以命中 Notes 内容。
8. `Ctrl/Cmd+F` 进入搜索；直接输入列表名可以 Type Travel；搜索结果可新窗口打开。
9. 底部 Toolbar 的 New/When/Move/Search 对当前选择生效，不需要跳到详情页。
10. 全局 Quick Entry 能在不打开主窗口的情况下把普通文本保存到 Inbox；AI Capture 是可选增强。
11. Today/Upcoming 能显示真实日历事件；权限拒绝时有明确恢复路径。
12. 1000 条任务下滚动、搜索、多选和批量完成可用，无明显卡顿。

## 8. 参考资料

- [Things Mac 键盘快捷键](https://culturedcode.com/things/support/articles/2785159/)
- [Things Mac Quick Entry / Autofill](https://culturedcode.com/things/support/articles/2249437/)
- [Things 中移动项目和待办](https://culturedcode.com/things/support/articles/9651894/)
- [Things 项目 Heading](https://culturedcode.com/things/support/articles/2803577/)
- [Things Notes 与 Markdown](https://culturedcode.com/things/support/articles/4438545/)
- [Things 模板](https://culturedcode.com/things/support/articles/2693493/)
- [Things 日历事件](https://culturedcode.com/things/support/articles/2803583/)
- [Things Shortcuts Actions](https://culturedcode.com/things/support/articles/9596775/)

## 9. 追踪方式

建议后续每完成一组 P0/P1，就在本文件的差距矩阵中把 `❌/△` 更新为 `✅`，并为每条 P0 验收场景增加一个 Flutter widget/integration test。这样“接近 Things 3”会变成可验证的产品基线，而不是凭感觉调 UI。
