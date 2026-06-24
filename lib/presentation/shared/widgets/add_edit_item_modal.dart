import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/models/item.dart';
import '../../providers/item_providers.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import 'when_picker_sheet.dart';
import 'move_target_sheet.dart';

/// 新建 / 编辑任务的居中模态框（白纸优先，高度随内容自适应）。
///
/// 设计要点：
///   - 打开只有标题输入 + 一条安静的工具条（白纸）；
///   - GTD 元素按需点亮：清单归属 / 何时 / 死线 / 标签，不填不显示；
///   - 高度随内容自适应，超过上限才滚动；顶部标题、底部工具条固定；
///   - 没有备注（备注不是 GTD 概念，已移除）。
class AddEditItemModal extends ConsumerStatefulWidget {
  final Item? existing;
  final WhenChoice? defaultWhen;
  final String? projectId;
  final String? headingId;

  const AddEditItemModal({
    super.key,
    this.existing,
    this.defaultWhen,
    this.projectId,
    this.headingId,
  });

  /// 以居中模态框打开。
  static Future<void> show(
    BuildContext context, {
    Item? existing,
    WhenChoice? defaultWhen,
    String? projectId,
    String? headingId,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AddEditItemModal(
        existing: existing,
        defaultWhen: defaultWhen,
        projectId: projectId,
        headingId: headingId,
      ),
    );
  }

  @override
  ConsumerState<AddEditItemModal> createState() => _AddEditItemModalState();
}

class _AddEditItemModalState extends ConsumerState<AddEditItemModal> {
  late final TextEditingController _titleController;
  final _focusNode = FocusNode();

  late WhenChoice _when;
  DateTime? _deadline;

  /// 清单归属（null 表示沿用打开时的语境，见 [_contextProjectId]）。
  MoveTarget? _list;

  /// 待附加的标签（新建场景暂存，保存后一次性 attach）。
  final Set<String> _tagIds = {};

  bool get _isEdit => widget.existing != null;
  String? get _contextProjectId => widget.projectId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleController = TextEditingController(text: e?.title ?? '');
    _deadline = e?.deadline;
    if (e != null) {
      _when = WhenChoice(e.start, startDate: e.startDate, evening: e.evening);
    } else {
      _when = widget.defaultWhen ?? WhenChoice.inbox;
    }
    if (!_isEdit) {
      Future.delayed(const Duration(milliseconds: 120), _focusNode.requestFocus);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _whenLabel() {
    switch (_when.start) {
      case WhenStart.inbox:
        return '何时';
      case WhenStart.someday:
        return '将来';
      case WhenStart.anytime:
        if (_when.startDate == null) return '随时';
        if (_when.evening) return '今晚';
        final diff = DateFmt.daysFromToday(_when.startDate!);
        if (diff == 0) return '今天';
        return DateFmt.groupLabel(_when.startDate!);
    }
  }

  bool get _whenActive => _when.start != WhenStart.inbox;

  /// 当前清单归属的展示标签。
  String _listLabel() {
    final t = _list;
    if (t != null) {
      if (t.inbox) return '收件箱';
      return t.projectTitle ?? t.areaTitle ?? '收件箱';
    }
    if (_contextProjectId != null) {
      final projects = ref.watch(projectsProvider).value ?? [];
      final match = projects.where((p) => p.id == _contextProjectId);
      if (match.isNotEmpty) return match.first.title;
    }
    return '收件箱';
  }

  Future<void> _pickList() async {
    final t = await MoveTargetSheet.show(context);
    if (t != null) setState(() => _list = t);
  }

  Future<void> _pickWhen() async {
    final choice = await WhenPickerSheet.showChoice(context);
    if (choice != null) setState(() => _when = choice);
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _pickTags() async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _TagSelectDialog(initial: _tagIds),
    );
    if (result != null) {
      setState(() => _tagIds
        ..clear()
        ..addAll(result));
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final repo = ref.read(itemRepositoryProvider);

    // 计算归属
    String? areaId;
    String? projectId;
    bool toInbox = false;
    if (_list != null) {
      areaId = _list!.areaId;
      projectId = _list!.projectId;
      toInbox = _list!.inbox;
    } else {
      projectId = _contextProjectId;
    }

    // 归入项目/领域而 When 仍是收件箱时，提升为「随时」（对齐 Things）。
    var start = _when.start;
    final hasParent = projectId != null || areaId != null;
    if (hasParent && start == WhenStart.inbox) start = WhenStart.anytime;

    if (_isEdit) {
      final id = widget.existing!.id;
      await repo.updateContent(id, title: title);
      await repo.setWhen(id,
          start: start, startDate: _when.startDate, evening: _when.evening);
      await repo.setDeadline(id, _deadline);
      if (_when.reminderTime != null) {
        await repo.setReminder(id, _when.reminderTime);
      }
      if (_list != null) {
        await repo.assignParent(
          id,
          areaId: areaId,
          projectId: projectId,
          toInbox: toInbox,
          currentStart: widget.existing!.start,
        );
      }
    } else {
      final newId = await repo.createTask(
        title: title,
        start: start,
        startDate: _when.startDate,
        evening: _when.evening,
        deadline: _deadline,
        reminderTime: _when.reminderTime,
        areaId: areaId,
        projectId: projectId,
        headingId: widget.headingId,
      );
      for (final tagId in _tagIds) {
        await repo.attachTag(newId, tagId);
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxH = math.min(560.0, mq.size.height * 0.82);
    final tags = ref.watch(tagsProvider).value ?? [];
    final tagTitleById = {for (final t in tags) t.id: t.title};

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
            // —— 顶部标题（固定）——
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: Colors.grey.shade400, width: 1.6),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      focusNode: _focusNode,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: null,
                      decoration: const InputDecoration(
                        hintText: '新建任务',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _save(),
                    ),
                  ),
                ],
              ),
            ),

            // —— 中部 chips（自适应，超出滚动）——
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(62, 4, 24, 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_whenActive)
                      _chip(
                        icon: Icons.calendar_today_rounded,
                        color: AppTheme.todayYellow,
                        label: _whenLabel(),
                        onClear: () =>
                            setState(() => _when = WhenChoice.inbox),
                      ),
                    if (_deadline != null)
                      _chip(
                        icon: Icons.flag_rounded,
                        color: AppTheme.deadlineRed,
                        label: DateFmt.deadlineLabel(_deadline!),
                        onClear: () => setState(() => _deadline = null),
                      ),
                    for (final id in _tagIds)
                      _chip(
                        icon: Icons.label_outline_rounded,
                        color: AppTheme.primaryBlue,
                        label: tagTitleById[id] ?? '标签',
                        onClear: () => setState(() => _tagIds.remove(id)),
                      ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1),

            // —— 底部工具条（固定）——
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 14, 10),
              child: Row(
                children: [
                  _tool(
                    icon: Icons.inbox_rounded,
                    label: _listLabel(),
                    highlighted: true,
                    onTap: _pickList,
                  ),
                  _tool(
                    icon: Icons.calendar_today_rounded,
                    onTap: _pickWhen,
                  ),
                  _tool(
                    icon: Icons.flag_rounded,
                    onTap: _pickDeadline,
                  ),
                  if (!_isEdit)
                    _tool(
                      icon: Icons.label_outline_rounded,
                      onTap: _pickTags,
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed:
                        _titleController.text.trim().isEmpty ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                    ),
                    child: Text(_isEdit ? '完成' : '保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 工具条按钮：无 label 时为纯图标。
  Widget _tool({
    required IconData icon,
    String? label,
    bool highlighted = false,
    required VoidCallback onTap,
  }) {
    final color = highlighted ? AppTheme.primaryBlue : AppTheme.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: EdgeInsets.symmetric(
            horizontal: label == null ? 10 : 11, vertical: 9),
        decoration: BoxDecoration(
          color: highlighted
              ? AppTheme.primaryBlue.withValues(alpha: 0.10)
              : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: color),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13.5,
                      color: color,
                      fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onClear,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: color, fontWeight: FontWeight.w600)),
          GestureDetector(
            onTap: onClear,
            child: Padding(
              padding: const EdgeInsets.only(left: 5),
              child: Icon(Icons.close, size: 14, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 新建任务时的标签多选对话框：勾选已有标签或新建后选中，返回选中集合。
class _TagSelectDialog extends ConsumerStatefulWidget {
  final Set<String> initial;
  const _TagSelectDialog({required this.initial});

  @override
  ConsumerState<_TagSelectDialog> createState() => _TagSelectDialogState();
}

class _TagSelectDialogState extends ConsumerState<_TagSelectDialog> {
  late final Set<String> _selected = {...widget.initial};
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _createAndSelect() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    final id = await ref.read(itemRepositoryProvider).createTag(title);
    setState(() {
      _selected.add(id);
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final allTags = ref.watch(tagsProvider).value ?? [];

    return AlertDialog(
      title: const Text('标签'),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (allTags.isNotEmpty)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final tag in allTags)
                      CheckboxListTile(
                        value: _selected.contains(tag.id),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppTheme.primaryBlue,
                        title: Text('# ${tag.title}'),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(tag.id);
                          } else {
                            _selected.remove(tag.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: '新建标签',
                        prefixText: '# ',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _createAndSelect(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle,
                        color: AppTheme.primaryBlue),
                    onPressed: _createAndSelect,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
