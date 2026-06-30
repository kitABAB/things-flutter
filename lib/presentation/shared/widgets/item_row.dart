import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../../ai/ai_providers.dart';
import '../../../domain/models/item.dart';
import '../../providers/item_providers.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import 'things_checkbox.dart';
import 'progress_pie.dart';
import 'clarify_sheet.dart';
import 'when_picker_sheet.dart';

/// 列表里的一行：任务 / 项目通用。
/// - 任务：复选框 + 标题 + 备注 + 死线红旗 + 计划/今晚指示
/// - 项目：进度圆环 + 标题，点击进入项目详情
class ItemRow extends ConsumerWidget {
  final Item item;

  /// 是否展示「计划日期」chip（计划视图里按日期分组了，就不必再重复）。
  final bool showWhenDate;

  /// 点击任务（编辑）。
  final ValueChanged<Item>? onTapTask;

  /// 点击项目（进入详情）。
  final ValueChanged<Item>? onTapProject;

  /// 在「计划」里作为死线影子出现：用红旗替代复选框，弱化主体。
  final bool deadlineShadow;

  /// 多选模式：禁用滑动/导航，点击切换选中。
  final bool selectionMode;
  final bool selected;
  final ValueChanged<Item>? onToggleSelect;

  const ItemRow({
    super.key,
    required this.item,
    this.showWhenDate = false,
    this.onTapTask,
    this.onTapProject,
    this.deadlineShadow = false,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(itemRepositoryProvider);

    if (selectionMode) return _selectableRow(context);

    // 「理清」仅对任务、且已配置 AI 时出现。
    final showClarify = item.isTask && ref.watch(aiEnabledProvider);

    return Slidable(
      key: ValueKey(item.id),
      startActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.5,
        children: [
          SlidableAction(
            onPressed: (_) =>
                repo.toggleComplete(item.id, !item.isCompleted),
            backgroundColor: const Color(0xFF30A46C),
            foregroundColor: Colors.white,
            icon: item.isCompleted
                ? Icons.remove_done_rounded
                : Icons.check_rounded,
            label: item.isCompleted ? '取消' : '完成',
          ),
          SlidableAction(
            onPressed: (_) => WhenPickerSheet.apply(context, ref, item.id),
            backgroundColor: AppTheme.todayYellow,
            foregroundColor: Colors.white,
            icon: Icons.calendar_today_rounded,
            label: '计划',
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: showClarify ? 0.5 : 0.25,
        dismissible: DismissiblePane(onDismissed: () => repo.moveToTrash(item.id)),
        children: [
          if (showClarify)
            SlidableAction(
              onPressed: (_) => ClarifySheet.show(context, item),
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              icon: Icons.auto_awesome_rounded,
              label: '理清',
            ),
          SlidableAction(
            onPressed: (_) => repo.moveToTrash(item.id),
            backgroundColor: AppTheme.deadlineRed,
            foregroundColor: Colors.white,
            icon: Icons.delete_rounded,
            label: '删除',
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          if (item.isProject) {
            onTapProject?.call(item);
          } else {
            onTapTask?.call(item);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11.0, horizontal: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1.0),
                child: _leading(ref),
              ),
              const SizedBox(width: 13),
              Expanded(child: _content(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectableRow(BuildContext context) {
    return InkWell(
      onTap: () => onToggleSelect?.call(item),
      child: Container(
        color: selected ? AppTheme.primaryBlue.withValues(alpha: 0.08) : null,
        padding: const EdgeInsets.symmetric(vertical: 9.0, horizontal: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1.0),
              child: Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                color: selected ? AppTheme.primaryBlue : Colors.grey.shade400,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _content(context)),
          ],
        ),
      ),
    );
  }

  Widget _leading(WidgetRef ref) {
    if (deadlineShadow) {
      return const Icon(Icons.flag_rounded, size: 20, color: AppTheme.deadlineRed);
    }
    if (item.isProject) {
      final progress = ref.watch(projectProgressProvider(item.id));
      return ProgressPie(
        progress: progress.maybeWhen(
          data: (p) => p.fraction,
          orElse: () => 0.0,
        ),
        size: 22,
        color: AppTheme.primaryBlue,
      );
    }
    return ThingsCheckbox(
      value: item.isCompleted,
      onChanged: (v) =>
          ref.read(itemRepositoryProvider).toggleComplete(item.id, v ?? false),
    );
  }

  Widget _content(BuildContext context) {
    final dim = item.isDone || item.start == WhenStart.someday;
    final titleColor = dim ? AppTheme.textSecondary : AppTheme.textPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (item.isProject)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.folder_rounded,
                    size: 16, color: AppTheme.primaryBlue),
              ),
            Expanded(
              child: Text(
                item.title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: titleColor,
                      decoration:
                          item.isDone ? TextDecoration.lineThrough : null,
                      fontWeight:
                          item.isProject ? FontWeight.w600 : FontWeight.w400,
                    ),
              ),
            ),
          ],
        ),
        _metaRow(context),
      ],
    );
  }

  Widget _metaRow(BuildContext context) {
    final chips = <Widget>[];

    if (item.evening) {
      chips.add(_chip(
        const Icon(Icons.nightlight_round,
            size: 12, color: AppTheme.eveningIndigo),
        '今晚',
        AppTheme.eveningIndigo,
      ));
    }

    if (showWhenDate && item.startDate != null) {
      chips.add(_chip(
        Icon(Icons.calendar_today_rounded,
            size: 11, color: AppTheme.textSecondary),
        DateFmt.groupLabel(item.startDate!),
        AppTheme.textSecondary,
      ));
    }

    if (item.deadline != null && !item.isDone) {
      final overdue = DateFmt.daysFromToday(item.deadline!) < 0;
      final soon = DateFmt.daysFromToday(item.deadline!) <= 2;
      final color = overdue || soon ? AppTheme.deadlineRed : AppTheme.somedayGrey;
      chips.add(_chip(
        Icon(Icons.flag_rounded, size: 12, color: color),
        DateFmt.deadlineLabel(item.deadline!),
        color,
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 5.0),
      child: Wrap(spacing: 10, runSpacing: 4, children: chips),
    );
  }

  Widget _chip(Widget icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
