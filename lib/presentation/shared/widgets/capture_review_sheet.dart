import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/capture/capture_draft.dart';
import '../../../domain/models/item.dart';
import '../../providers/item_providers.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import 'move_target_sheet.dart';
import 'when_picker_sheet.dart';

/// 「一句话拆解捕获」的草稿评审框。
///
/// 设计红线：AI 只产出草稿，这里让用户**逐项可改、可删、可取舍**，确认后才落库，
/// 落库后顶部留一条**可撤销**的提示。复用 When / 清单 / 死线 等既有选择器，零新心智。
class CaptureReviewSheet {
  static Future<bool?> show(
    BuildContext context,
    CaptureDraft draft, {
    String? contextProjectId,
    String? headingId,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _CaptureReviewBody(
        draft: draft,
        contextProjectId: contextProjectId,
        headingId: headingId,
      ),
    );
  }
}

/// 子条目的可编辑状态。
class _ChildEdit {
  final TextEditingController title;
  bool include = true;
  WhenChoice when;
  DateTime? deadline;
  _ChildEdit(String t, {WhenChoice? when, this.deadline})
      : title = TextEditingController(text: t),
        when = when ?? WhenChoice.inbox;
}

/// 顶层条目的可编辑状态。
class _ItemEdit {
  final TextEditingController title;
  ItemType type;
  WhenChoice when;
  DateTime? deadline;
  MoveTarget? list;
  final Set<String> tagIds; // 已有标签
  final List<String> newTagNames; // AI 建议、库里还没有的新标签
  final List<_ChildEdit> children;

  _ItemEdit({
    required String title,
    required this.type,
    required this.when,
    this.deadline,
    this.list,
    Set<String>? tagIds,
    List<String>? newTagNames,
    List<_ChildEdit>? children,
  })  : title = TextEditingController(text: title),
        tagIds = tagIds ?? {},
        newTagNames = newTagNames ?? [],
        children = children ?? [];
}

class _CaptureReviewBody extends ConsumerStatefulWidget {
  final CaptureDraft draft;
  final String? contextProjectId;
  final String? headingId;
  const _CaptureReviewBody({
    required this.draft,
    this.contextProjectId,
    this.headingId,
  });

  @override
  ConsumerState<_CaptureReviewBody> createState() => _CaptureReviewBodyState();
}

class _CaptureReviewBodyState extends ConsumerState<_CaptureReviewBody> {
  bool _initialized = false;
  bool _saving = false;
  final List<_ItemEdit> _items = [];

  /// 首帧根据当前已有项目/领域/标签把 AI 的名字解析成具体 id / MoveTarget。
  void _initFromDraft() {
    final projects = ref.read(projectsProvider).value ?? [];
    final areas = ref.read(areasProvider).value ?? [];
    final tags = ref.read(tagsProvider).value ?? [];

    MoveTarget? resolveList(String? name) {
      if (name == null) return null;
      if (name == DraftItem.inboxToken) return const MoveTarget.inbox();
      final p = projects.where((e) => e.title == name);
      if (p.isNotEmpty) return MoveTarget.project(p.first.id, p.first.title);
      final a = areas.where((e) => e.title == name);
      if (a.isNotEmpty) return MoveTarget.area(a.first.id, a.first.title);
      return null;
    }

    for (final d in widget.draft.items) {
      final existingIds = <String>{};
      final newNames = <String>[];
      for (final name in d.tagNames) {
        final match = tags.where(
            (t) => t.title.toLowerCase() == name.toLowerCase());
        if (match.isNotEmpty) {
          existingIds.add(match.first.id);
        } else {
          newNames.add(name);
        }
      }
      _items.add(_ItemEdit(
        title: d.title,
        type: d.type,
        when: _toWhenChoice(d.when),
        deadline: d.deadline,
        list: resolveList(d.listName),
        tagIds: existingIds,
        newTagNames: newNames,
        children: [
          for (final c in d.children)
            _ChildEdit(c.title, when: _toWhenChoice(c.when), deadline: c.deadline),
        ],
      ));
    }
  }

  static WhenChoice _toWhenChoice(DraftWhen w) {
    switch (w.kind) {
      case DraftWhenKind.today:
        return WhenChoice.today;
      case DraftWhenKind.evening:
        return WhenChoice.thisEvening;
      case DraftWhenKind.someday:
        return WhenChoice.someday;
      case DraftWhenKind.date:
        return WhenChoice.scheduled(w.date!);
      case DraftWhenKind.none:
        return WhenChoice.inbox;
    }
  }

  @override
  void dispose() {
    for (final it in _items) {
      it.title.dispose();
      for (final c in it.children) {
        c.title.dispose();
      }
    }
    super.dispose();
  }

  int get _totalCount {
    var n = 0;
    for (final it in _items) {
      n += 1;
      n += it.children.where((c) => c.include).length;
    }
    return n;
  }

  String _whenLabel(WhenChoice w) {
    switch (w.start) {
      case WhenStart.inbox:
        return '何时';
      case WhenStart.someday:
        return '将来';
      case WhenStart.anytime:
        if (w.startDate == null) return '随时';
        if (w.evening) return '今晚';
        final diff = DateFmt.daysFromToday(w.startDate!);
        if (diff == 0) return '今天';
        return DateFmt.groupLabel(w.startDate!);
    }
  }

  String _listLabel(MoveTarget? t) {
    if (t == null) {
      if (widget.contextProjectId != null) {
        final projects = ref.watch(projectsProvider).value ?? [];
        final m = projects.where((p) => p.id == widget.contextProjectId);
        if (m.isNotEmpty) return m.first.title;
      }
      return '收件箱';
    }
    if (t.inbox) return '收件箱';
    return t.projectTitle ?? t.areaTitle ?? '收件箱';
  }

  // ----------------------------------------------------------------
  // 落库
  // ----------------------------------------------------------------

  Future<void> _commit() async {
    setState(() => _saving = true);
    final repo = ref.read(itemRepositoryProvider);
    final created = <String>[];

    try {
      for (final it in _items) {
        final title = it.title.text.trim();
        if (title.isEmpty) continue;

        // 解析新标签 -> 创建后得到 id
        final tagIds = <String>{...it.tagIds};
        for (final name in it.newTagNames) {
          tagIds.add(await repo.createTag(name));
        }

        // 清单归属
        String? areaId;
        String? projectId;
        bool toInbox = false;
        if (it.list != null) {
          areaId = it.list!.areaId;
          projectId = it.list!.projectId;
          toInbox = it.list!.inbox;
        } else {
          projectId = widget.contextProjectId;
        }

        var start = it.when.start;
        final hasParent = projectId != null || areaId != null;
        if (hasParent && start == WhenStart.inbox && !toInbox) {
          start = WhenStart.anytime;
        }

        if (it.type == ItemType.project) {
          final pid = await repo.createProject(
            title: title,
            areaId: areaId,
            start: start == WhenStart.inbox ? WhenStart.anytime : start,
          );
          created.add(pid);
          if (it.when.startDate != null || it.when.start == WhenStart.someday) {
            await repo.setWhen(pid,
                start: it.when.start == WhenStart.inbox
                    ? WhenStart.anytime
                    : it.when.start,
                startDate: it.when.startDate,
                evening: it.when.evening);
          }
          if (it.deadline != null) await repo.setDeadline(pid, it.deadline);
          for (final tagId in tagIds) {
            await repo.attachTag(pid, tagId);
          }
          // 项目下的任务
          for (final c in it.children.where((c) => c.include)) {
            final ct = c.title.text.trim();
            if (ct.isEmpty) continue;
            final cid = await repo.createTask(
              title: ct,
              start: c.when.start == WhenStart.inbox
                  ? WhenStart.anytime
                  : c.when.start,
              startDate: c.when.startDate,
              evening: c.when.evening,
              deadline: c.deadline,
              projectId: pid,
            );
            created.add(cid);
          }
        } else {
          final tid = await repo.createTask(
            title: title,
            start: start,
            startDate: it.when.startDate,
            evening: it.when.evening,
            deadline: it.deadline,
            areaId: areaId,
            projectId: projectId,
            headingId: widget.headingId,
          );
          created.add(tid);
          for (final tagId in tagIds) {
            await repo.attachTag(tid, tagId);
          }
          // 任务下的检查项（随父任务进垃圾站一并撤销，无需单独追踪）
          for (final c in it.children.where((c) => c.include)) {
            final ct = c.title.text.trim();
            if (ct.isNotEmpty) await repo.addChecklistItem(tid, ct);
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text('已添加 ${created.length} 个条目'),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: '撤销',
        onPressed: () async {
          for (final id in created) {
            await repo.moveToTrash(id);
          }
        },
      ),
    ));
  }

  // ----------------------------------------------------------------
  // 编辑动作
  // ----------------------------------------------------------------

  Future<void> _editWhen(void Function(WhenChoice) set) async {
    final c = await WhenPickerSheet.showChoice(context);
    if (c != null) setState(() => set(c));
  }

  Future<void> _editDeadline(DateTime? current, void Function(DateTime?) set) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => set(picked));
  }

  Future<void> _editList(_ItemEdit it) async {
    final t = await MoveTargetSheet.show(context);
    if (t != null) setState(() => it.list = t);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      _initFromDraft();
      _initialized = true;
    }
    final mq = MediaQuery.of(context);
    final maxH = math.min(620.0, mq.size.height * 0.86);
    final tagTitleById = {
      for (final t in ref.watch(tagsProvider).value ?? <Tag>[]) t.id: t.title
    };

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 600, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // —— 头：原文 + 拆解标识 ——
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 18, 8),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 18, color: AppTheme.primaryBlue),
                  const SizedBox(width: 8),
                  const Text('已拆解',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('返回编辑'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
              child: Text(
                '来自：${widget.draft.source}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
              ),
            ),
            const Divider(height: 16),

            // —— 草稿条目列表（可滚动）——
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                shrinkWrap: true,
                children: [
                  for (final it in _items) _itemCard(it, tagTitleById),
                ],
              ),
            ),

            const Divider(height: 1),

            // —— 底部：保存 ——
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Row(
                children: [
                  Text('共 $_totalCount 项',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving || _totalCount == 0 ? null : _commit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text('保存 $_totalCount 项'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(_ItemEdit it, Map<String, String> tagTitleById) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题 + 类型切换
          Row(
            children: [
              Icon(
                it.type == ItemType.project
                    ? Icons.circle_outlined
                    : Icons.check_box_outline_blank_rounded,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: it.title,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              _typeToggle(it),
            ],
          ),
          // chips：何时 / 死线 / 清单 / 标签
          Padding(
            padding: const EdgeInsets.only(left: 30, top: 8),
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _miniChip(
                  icon: Icons.calendar_today_rounded,
                  color: AppTheme.todayYellow,
                  label: _whenLabel(it.when),
                  active: it.when.start != WhenStart.inbox,
                  onTap: () => _editWhen((c) => it.when = c),
                  onClear: it.when.start != WhenStart.inbox
                      ? () => setState(() => it.when = WhenChoice.inbox)
                      : null,
                ),
                _miniChip(
                  icon: Icons.flag_rounded,
                  color: AppTheme.deadlineRed,
                  label: it.deadline == null
                      ? '死线'
                      : DateFmt.deadlineLabel(it.deadline!),
                  active: it.deadline != null,
                  onTap: () => _editDeadline(it.deadline, (d) => it.deadline = d),
                  onClear: it.deadline != null
                      ? () => setState(() => it.deadline = null)
                      : null,
                ),
                _miniChip(
                  icon: Icons.inbox_rounded,
                  color: AppTheme.primaryBlue,
                  label: _listLabel(it.list),
                  active: it.list != null,
                  onTap: () => _editList(it),
                ),
                for (final id in it.tagIds)
                  _miniChip(
                    icon: Icons.label_outline_rounded,
                    color: AppTheme.primaryBlue,
                    label: tagTitleById[id] ?? '标签',
                    active: true,
                    onClear: () => setState(() => it.tagIds.remove(id)),
                  ),
                for (final name in it.newTagNames)
                  _miniChip(
                    icon: Icons.add_rounded,
                    color: AppTheme.somedayGrey,
                    label: '$name（新）',
                    active: true,
                    onClear: () => setState(() => it.newTagNames.remove(name)),
                  ),
              ],
            ),
          ),
          // 子条目
          if (it.children.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 12, bottom: 2),
              child: Text(
                it.type == ItemType.project ? '项目下的任务' : '检查项',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary),
              ),
            ),
            for (final c in it.children) _childRow(it, c),
          ],
        ],
      ),
    );
  }

  Widget _typeToggle(_ItemEdit it) {
    return GestureDetector(
      onTap: () => setState(() {
        it.type =
            it.type == ItemType.project ? ItemType.task : ItemType.project;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          it.type == ItemType.project ? '项目' : '任务',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryBlue),
        ),
      ),
    );
  }

  Widget _childRow(_ItemEdit parent, _ChildEdit c) {
    return Padding(
      padding: const EdgeInsets.only(left: 26, top: 2),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Checkbox(
              value: c.include,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: AppTheme.primaryBlue,
              onChanged: (v) => setState(() => c.include = v ?? true),
            ),
          ),
          Expanded(
            child: TextField(
              controller: c.title,
              enabled: c.include,
              style: TextStyle(
                fontSize: 14,
                color: c.include ? null : AppTheme.textSecondary,
                decoration:
                    c.include ? null : TextDecoration.lineThrough,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16),
            color: AppTheme.textSecondary,
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => parent.children.remove(c)),
          ),
        ],
      ),
    );
  }

  Widget _miniChip({
    required IconData icon,
    required Color color,
    required String label,
    required bool active,
    VoidCallback? onTap,
    VoidCallback? onClear,
  }) {
    final c = active ? color : AppTheme.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.12)
              : AppTheme.textSecondary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5, color: c, fontWeight: FontWeight.w600)),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 13, color: c),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
