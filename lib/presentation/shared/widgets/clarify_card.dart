import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/capture/capture_draft.dart';
import '../../../domain/models/item.dart';
import '../../providers/item_providers.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import 'move_target_sheet.dart';
import 'when_picker_sheet.dart';

/// 一条被理清条目的可编辑草稿状态（单条 / 批量理清复用）。
class ClarifyEdit {
  final TextEditingController title;
  ItemType type;
  WhenChoice when;
  DateTime? deadline;
  MoveTarget? list;
  final Set<String> tagIds; // 已有标签
  final List<String> newTagNames; // AI 建议、库里还没有的新标签
  final List<TextEditingController> children;

  ClarifyEdit({
    required String title,
    this.type = ItemType.task,
    WhenChoice? when,
    this.deadline,
    this.list,
    Set<String>? tagIds,
    List<String>? newTagNames,
    List<String>? childTitles,
  })  : title = TextEditingController(text: title),
        when = when ?? WhenChoice.inbox,
        tagIds = tagIds ?? {},
        newTagNames = newTagNames ?? [],
        children = [
          for (final c in (childTitles ?? <String>[]))
            TextEditingController(text: c)
        ];

  /// 从 AI 草稿 + 当前库内项目/领域/标签解析成可编辑状态。
  factory ClarifyEdit.fromDraft(
    DraftItem d, {
    required List<Item> projects,
    required List<Area> areas,
    required List<Tag> tags,
  }) {
    MoveTarget? resolveList(String? name) {
      if (name == null) return null;
      if (name == DraftItem.inboxToken) return const MoveTarget.inbox();
      final p = projects.where((e) => e.title == name);
      if (p.isNotEmpty) return MoveTarget.project(p.first.id, p.first.title);
      final a = areas.where((e) => e.title == name);
      if (a.isNotEmpty) return MoveTarget.area(a.first.id, a.first.title);
      return null;
    }

    final existingIds = <String>{};
    final newNames = <String>[];
    for (final name in d.tagNames) {
      final match = tags.where((t) => t.title.toLowerCase() == name.toLowerCase());
      if (match.isNotEmpty) {
        existingIds.add(match.first.id);
      } else {
        newNames.add(name);
      }
    }

    return ClarifyEdit(
      title: d.title,
      type: d.type,
      when: _toWhenChoice(d.when),
      deadline: d.deadline,
      list: resolveList(d.listName),
      tagIds: existingIds,
      newTagNames: newNames,
      childTitles: d.children.map((c) => c.title).toList(),
    );
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

  void dispose() {
    title.dispose();
    for (final c in children) {
      c.dispose();
    }
  }
}

/// 把一条已理清的草稿应用到既有条目（原地理清）。
/// 返回是否成功。
Future<void> applyClarifyEdit(
  WidgetRef ref, {
  required Item original,
  required ClarifyEdit edit,
}) async {
  final repo = ref.read(itemRepositoryProvider);
  final id = original.id;
  final title = edit.title.text.trim();
  if (title.isEmpty) return;

  await repo.updateContent(id, title: title);

  // 归属
  String? areaId;
  String? projectId;
  bool toInbox = false;
  if (edit.list != null) {
    areaId = edit.list!.areaId;
    projectId = edit.list!.projectId;
    toInbox = edit.list!.inbox;
  }
  // 项目不能再嵌进另一个项目里。
  if (edit.type == ItemType.project) projectId = null;

  await repo.assignParent(
    id,
    areaId: areaId,
    projectId: projectId,
    toInbox: toInbox,
    currentStart: original.start,
  );

  // 类型（任务 ⇄ 项目）。
  await repo.setType(id, edit.type);

  // When：归入容器或转为项目后，inbox 提升为随时。
  var start = edit.when.start;
  final hasParent = projectId != null || areaId != null;
  if (start == WhenStart.inbox &&
      ((hasParent && !toInbox) || edit.type == ItemType.project)) {
    start = WhenStart.anytime;
  }
  await repo.setWhen(id,
      start: start, startDate: edit.when.startDate, evening: edit.when.evening);
  await repo.setDeadline(id, edit.deadline);

  // 标签：已有的关联，新的先建后关联。
  final tagIds = <String>{...edit.tagIds};
  for (final name in edit.newTagNames) {
    tagIds.add(await repo.createTag(name));
  }
  for (final tagId in tagIds) {
    await repo.attachTag(id, tagId);
  }

  // 子步骤：项目→任务；任务→检查项。
  for (final c in edit.children) {
    final ct = c.text.trim();
    if (ct.isEmpty) continue;
    if (edit.type == ItemType.project) {
      await repo.createTask(title: ct, start: WhenStart.anytime, projectId: id);
    } else {
      await repo.addChecklistItem(id, ct);
    }
  }
}

/// 可编辑的「理清卡片」。自身可变 [edit]，每次修改后回调 [onChanged] 触发父级重建。
class ClarifyCard extends ConsumerWidget {
  final ClarifyEdit edit;
  final VoidCallback onChanged;
  final String? note;
  final String? outcome;

  const ClarifyCard({
    super.key,
    required this.edit,
    required this.onChanged,
    this.note,
    this.outcome,
  });

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
    if (t == null) return '收件箱';
    if (t.inbox) return '收件箱';
    return t.projectTitle ?? t.areaTitle ?? '收件箱';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagTitleById = {
      for (final t in ref.watch(tagsProvider).value ?? <Tag>[]) t.id: t.title
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    size: 15, color: AppTheme.primaryBlue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(note!,
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: AppTheme.textSecondary)),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          // 标题 + 类型切换
          Row(
            children: [
              Icon(
                edit.type == ItemType.project
                    ? Icons.circle_outlined
                    : Icons.check_box_outline_blank_rounded,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: edit.title,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w600),
                  maxLines: null,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              _typeToggle(),
            ],
          ),
          if (outcome != null)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 4),
              child: Text('期望结果：$outcome',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
            ),
          // chips
          Padding(
            padding: const EdgeInsets.only(left: 30, top: 10),
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _miniChip(
                  icon: Icons.calendar_today_rounded,
                  color: AppTheme.todayYellow,
                  label: _whenLabel(edit.when),
                  active: edit.when.start != WhenStart.inbox,
                  onTap: () async {
                    final c = await WhenPickerSheet.showChoice(context);
                    if (c != null) {
                      edit.when = c;
                      onChanged();
                    }
                  },
                  onClear: edit.when.start != WhenStart.inbox
                      ? () {
                          edit.when = WhenChoice.inbox;
                          onChanged();
                        }
                      : null,
                ),
                _miniChip(
                  icon: Icons.flag_rounded,
                  color: AppTheme.deadlineRed,
                  label: edit.deadline == null
                      ? '死线'
                      : DateFmt.deadlineLabel(edit.deadline!),
                  active: edit.deadline != null,
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: edit.deadline ?? now,
                      firstDate: now.subtract(const Duration(days: 1)),
                      lastDate: now.add(const Duration(days: 365 * 5)),
                    );
                    if (picked != null) {
                      edit.deadline = picked;
                      onChanged();
                    }
                  },
                  onClear: edit.deadline != null
                      ? () {
                          edit.deadline = null;
                          onChanged();
                        }
                      : null,
                ),
                _miniChip(
                  icon: Icons.inbox_rounded,
                  color: AppTheme.primaryBlue,
                  label: _listLabel(edit.list),
                  active: edit.list != null && !edit.list!.inbox,
                  onTap: () async {
                    final t = await MoveTargetSheet.show(context);
                    if (t != null) {
                      edit.list = t;
                      onChanged();
                    }
                  },
                ),
                for (final id in edit.tagIds)
                  _miniChip(
                    icon: Icons.label_outline_rounded,
                    color: AppTheme.primaryBlue,
                    label: tagTitleById[id] ?? '标签',
                    active: true,
                    onClear: () {
                      edit.tagIds.remove(id);
                      onChanged();
                    },
                  ),
                for (final name in edit.newTagNames)
                  _miniChip(
                    icon: Icons.add_rounded,
                    color: AppTheme.somedayGrey,
                    label: '$name（新）',
                    active: true,
                    onClear: () {
                      edit.newTagNames.remove(name);
                      onChanged();
                    },
                  ),
              ],
            ),
          ),
          // 子步骤
          if (edit.children.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 12, bottom: 2),
              child: Text(
                edit.type == ItemType.project ? '项目下的任务' : '检查项',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary),
              ),
            ),
            for (final c in edit.children) _childRow(c),
          ],
        ],
      ),
    );
  }

  Widget _typeToggle() {
    return GestureDetector(
      onTap: () {
        edit.type =
            edit.type == ItemType.project ? ItemType.task : ItemType.project;
        onChanged();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          edit.type == ItemType.project ? '项目' : '任务',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryBlue),
        ),
      ),
    );
  }

  Widget _childRow(TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(left: 26, top: 2),
      child: Row(
        children: [
          Icon(
            edit.type == ItemType.project
                ? Icons.check_box_outline_blank_rounded
                : Icons.radio_button_unchecked,
            size: 16,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: c,
              style: const TextStyle(fontSize: 14),
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
            onPressed: () {
              edit.children.remove(c);
              onChanged();
            },
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
