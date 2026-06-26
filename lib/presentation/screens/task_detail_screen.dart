import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/item.dart';
import '../../data/repositories/item_repository.dart';
import '../providers/item_providers.dart';
import '../shared/theme/app_theme.dart';
import '../shared/utils/date_format.dart';
import '../shared/widgets/things_checkbox.dart';
import '../shared/widgets/when_picker_sheet.dart';
import '../shared/widgets/move_target_sheet.dart';
import '../shared/widgets/tag_picker_sheet.dart';

/// 任务详情页：完整编辑一个任务的所有元数据。
class TaskDetailScreen extends ConsumerStatefulWidget {
  final Item initial;
  const TaskDetailScreen({super.key, required this.initial});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  late final TextEditingController _titleController;
  final _checklistController = TextEditingController();

  String get _id => widget.initial.id;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initial.title);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _checklistController.dispose();
    super.dispose();
  }

  void _persistContent() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    ref.read(itemRepositoryProvider).updateContent(_id, title: title);
  }

  String _whenLabel(Item item) {
    switch (item.start) {
      case WhenStart.inbox:
        return '收件箱';
      case WhenStart.someday:
        return '将来';
      case WhenStart.anytime:
        if (item.startDate == null) return '随时';
        if (item.evening) return '今晚';
        return DateFmt.groupLabel(item.startDate!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(itemProvider(_id)).value ?? widget.initial;
    final checklist = ref.watch(checklistProvider(_id)).value ?? [];
    final tags = ref.watch(itemTagsProvider(_id)).value ?? [];
    final inherited = ref.watch(inheritedTagsProvider(_id)).value ?? [];
    final repo = ref.read(itemRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: AppTheme.textSecondary,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, color: AppTheme.textSecondary),
            onSelected: (v) {
              if (v == 'cancel') {
                repo.setStatus(_id, ItemStatus.canceled);
                Navigator.of(context).maybePop();
              } else if (v == 'trash') {
                repo.moveToTrash(_id);
                Navigator.of(context).maybePop();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'cancel', child: Text('取消任务（划掉）')),
              PopupMenuItem(value: 'trash', child: Text('删除到垃圾桶')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ThingsCheckbox(
                  value: item.isCompleted,
                  onChanged: (v) => repo.toggleComplete(_id, v ?? false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _titleController,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: null,
                  decoration: const InputDecoration(
                    hintText: '标题',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: (_) => _persistContent(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // When + 死线
          _metaTile(
            icon: Icons.calendar_today_rounded,
            color: AppTheme.todayYellow,
            label: '计划',
            value: _whenLabel(item),
            onTap: () async {
              final c = await WhenPickerSheet.showChoice(context);
              if (c != null) {
                await repo.setWhen(_id,
                    start: c.start, startDate: c.startDate, evening: c.evening);
              }
            },
          ),
          _metaTile(
            icon: Icons.flag_rounded,
            color: AppTheme.deadlineRed,
            label: '死线',
            value: item.deadline == null
                ? '无'
                : DateFmt.deadlineLabel(item.deadline!),
            onClear: item.deadline == null ? null : () => repo.setDeadline(_id, null),
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: item.deadline ?? now,
                firstDate: now.subtract(const Duration(days: 1)),
                lastDate: now.add(const Duration(days: 365 * 5)),
              );
              if (picked != null) repo.setDeadline(_id, picked);
            },
          ),
          _metaTile(
            icon: Icons.alarm_rounded,
            color: AppTheme.eveningIndigo,
            label: '提醒',
            value: item.reminderTime ?? '无',
            onClear:
                item.reminderTime == null ? null : () => repo.setReminder(_id, null),
            onTap: () => _pickReminder(repo, item),
          ),
          _metaTile(
            icon: Icons.repeat_rounded,
            color: const Color(0xFF30A46C),
            label: '重复',
            value: item.repeat.label,
            onClear: item.isRepeating
                ? () => repo.setRepeat(_id, RepeatRule.none)
                : null,
            onTap: () => _pickRepeat(repo, item),
          ),
          _metaTile(
            icon: Icons.folder_rounded,
            color: AppTheme.primaryBlue,
            label: '移动到',
            value: _parentLabel(item),
            onTap: () async {
              final t = await MoveTargetSheet.show(context);
              if (t != null) {
                await repo.assignParent(
                  _id,
                  areaId: t.areaId,
                  projectId: t.projectId,
                  toInbox: t.inbox,
                  currentStart: item.start,
                );
              }
            },
          ),
          if (item.projectId != null)
            _metaTile(
              icon: Icons.segment_rounded,
              color: AppTheme.primaryBlue,
              label: '标题',
              value: _headingLabel(item),
              onClear: item.headingId == null
                  ? null
                  : () => repo.assignHeading(_id, null),
              onTap: () => _pickHeading(repo, item),
            ),

          const SizedBox(height: 24),
          _sectionTitle(context, '标签'),
          _tagsWrap(tags, inherited),

          const SizedBox(height: 24),
          _sectionTitle(context, '清单'),
          ...checklist.map((c) => _checklistRow(repo, c)),
          _addChecklistRow(repo),
        ],
      ),
    );
  }

  String _parentLabel(Item item) {
    if (item.projectId != null) {
      final projects = ref.watch(projectsProvider).value ?? [];
      final match = projects.where((p) => p.id == item.projectId);
      if (match.isNotEmpty) return match.first.title;
      return '项目';
    }
    if (item.areaId != null) {
      final areas = ref.watch(areasProvider).value ?? [];
      final match = areas.where((a) => a.id == item.areaId);
      if (match.isNotEmpty) return match.first.title;
      return '领域';
    }
    return item.start == WhenStart.inbox ? '收件箱' : '无';
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
    );
  }

  Widget _metaTile({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: AppTheme.textPrimary)),
            const Spacer(),
            Text(value, style: TextStyle(color: AppTheme.textSecondary)),
            if (onClear != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                color: AppTheme.textSecondary,
                onPressed: onClear,
              )
            else
              Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _tagsWrap(List<Tag> tags, List<Tag> inherited) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in tags)
          Chip(
            label: Text('# ${t.title}'),
            onDeleted: () =>
                ref.read(itemRepositoryProvider).detachTag(_id, t.id),
            backgroundColor: AppTheme.backgroundLight,
            side: BorderSide.none,
          ),
        // 继承自项目 / 区域的标签：只读，弱化展示
        for (final t in inherited)
          Chip(
            avatar: Icon(Icons.subdirectory_arrow_right_rounded,
                size: 14, color: AppTheme.textSecondary),
            label: Text('# ${t.title}',
                style: TextStyle(color: AppTheme.textSecondary)),
            backgroundColor: AppTheme.backgroundLight.withValues(alpha: 0.5),
            side: BorderSide.none,
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: const Text('标签'),
          onPressed: () => TagPickerSheet.show(context, _id),
        ),
      ],
    );
  }

  Future<void> _pickReminder(ItemRepository repo, Item item) async {
    if (item.startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先把「计划」设为某一天，才能设置提醒时刻')),
      );
      return;
    }
    final initial = _parseTimeOfDay(item.reminderTime) ??
        const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final hhmm =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      await repo.setReminder(_id, hhmm);
    }
  }

  TimeOfDay? _parseTimeOfDay(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0);
  }

  String _headingLabel(Item item) {
    if (item.headingId == null) return '无';
    final items = ref.watch(projectItemsProvider(item.projectId!)).value ?? [];
    final match = items.where((i) => i.isHeading && i.id == item.headingId);
    return match.isNotEmpty ? match.first.title : '标题';
  }

  Future<void> _pickHeading(ItemRepository repo, Item item) async {
    final items = ref.read(projectItemsProvider(item.projectId!)).value ?? [];
    final headings = items.where((i) => i.isHeading).toList();
    if (headings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该项目还没有标题，先在项目页新建一个')),
      );
      return;
    }
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('无标题'),
              trailing: item.headingId == null
                  ? const Icon(Icons.check, color: AppTheme.primaryBlue)
                  : null,
              onTap: () => Navigator.of(ctx).pop('__none__'),
            ),
            for (final h in headings)
              ListTile(
                title: Text(h.title),
                trailing: item.headingId == h.id
                    ? const Icon(Icons.check, color: AppTheme.primaryBlue)
                    : null,
                onTap: () => Navigator.of(ctx).pop(h.id),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) {
      await repo.assignHeading(_id, chosen == '__none__' ? null : chosen);
    }
  }

  Future<void> _pickRepeat(ItemRepository repo, Item item) async {
    final rule = await showModalBottomSheet<RepeatRule>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in RepeatRule.values)
              ListTile(
                title: Text(r.label),
                trailing: item.repeat == r
                    ? const Icon(Icons.check, color: AppTheme.primaryBlue)
                    : null,
                onTap: () => Navigator.of(ctx).pop(r),
              ),
          ],
        ),
      ),
    );
    if (rule != null) await repo.setRepeat(_id, rule);
  }

  Widget _checklistRow(ItemRepository repo, ChecklistItem c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ThingsCheckbox(
            value: c.isCompleted,
            onChanged: (v) => repo.toggleChecklistItem(c.id, v ?? false),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              c.title,
              style: TextStyle(
                decoration: c.isCompleted ? TextDecoration.lineThrough : null,
                color: c.isCompleted ? AppTheme.textSecondary : AppTheme.textPrimary,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: AppTheme.textSecondary,
            onPressed: () => repo.deleteChecklistItem(c.id),
          ),
        ],
      ),
    );
  }

  Widget _addChecklistRow(ItemRepository repo) {
    // 支持粘贴多行/项目符号列表，自动拆成多个检查项（对齐 Things）。
    void add() {
      final raw = _checklistController.text;
      if (raw.trim().isEmpty) return;
      final lines = raw
          .split(RegExp(r'[\r\n]+'))
          .map((l) => l.replaceFirst(RegExp(r'^\s*[-*•·]\s*'), '').trim())
          .where((l) => l.isNotEmpty)
          .toList();
      for (final l in lines) {
        repo.addChecklistItem(_id, l);
      }
      _checklistController.clear();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.add, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _checklistController,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: '添加检查项（可粘贴多行列表）',
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (v) {
                // 粘贴进来的多行文本立即转换
                if (v.contains('\n')) add();
              },
              onSubmitted: (_) => add(),
            ),
          ),
        ],
      ),
    );
  }
}
