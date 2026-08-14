import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/item.dart';
import '../providers/item_providers.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/item_row.dart';
import '../shared/widgets/progress_pie.dart';
import '../shared/utils/date_format.dart';
import '../shared/widgets/add_edit_item_modal.dart';
import '../shared/widgets/magic_plus.dart';
import '../shared/widgets/name_dialog.dart';
import '../shared/widgets/when_picker_sheet.dart';
import '../shared/widgets/tag_picker_sheet.dart';
import 'task_detail_screen.dart';

/// 项目详情页：进度圆环 + 标题 + 按 Heading 分组的任务清单。
/// 支持任务拖拽排序、标题归档、Magic Plus 新建任务/标题。
class ProjectScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String projectTitle;
  final ValueChanged<Item>? onInspectItem;
  final String? inspectedItemId;
  final bool desktopMode;

  const ProjectScreen({
    super.key,
    required this.projectId,
    required this.projectTitle,
    this.onInspectItem,
    this.inspectedItemId,
    this.desktopMode = false,
  });

  @override
  ConsumerState<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends ConsumerState<ProjectScreen> {
  final Set<String> _collapsedHeadings = <String>{};

  String get projectId => widget.projectId;
  String get projectTitle => widget.projectTitle;
  ValueChanged<Item>? get onInspectItem => widget.onInspectItem;
  String? get inspectedItemId => widget.inspectedItemId;
  bool get desktopMode => widget.desktopMode;

  void _openTask(BuildContext context, Item i) {
    if (onInspectItem != null) {
      onInspectItem!(i);
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(initial: i)));
  }

  Future<void> _addHeading(BuildContext context, WidgetRef ref) async {
    final name = await NameDialog.show(
      context,
      title: '新建标题',
      hint: '标题名称（如：前端 UI）',
    );
    if (name != null && name.isNotEmpty) {
      await ref
          .read(itemRepositoryProvider)
          .createHeading(title: name, projectId: projectId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(projectItemsProvider(projectId));
    final progress = ref.watch(projectProgressProvider(projectId));
    final repo = ref.read(itemRepositoryProvider);

    return MagicCreateScope(
      context: MagicCreateContext(projectId: projectId),
      child: Scaffold(
        backgroundColor: desktopMode ? Colors.transparent : null,
        body: SafeArea(
          top: !desktopMode,
          child: itemsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('出错了：$e')),
            data: (items) {
              final headings = items.where((i) => i.isHeading).toList();
              final looseTasks = items
                  .where((i) => i.isTask && i.headingId == null)
                  .toList();

              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      desktopMode ? 28 : 16,
                      desktopMode ? 20 : 12,
                      desktopMode ? 28 : 16,
                      8,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          if (!desktopMode)
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new,
                                size: 18,
                              ),
                              color: AppTheme.textSecondary,
                              onPressed: () => Navigator.of(context).maybePop(),
                            ),
                          ProgressPie(
                            progress: progress.maybeWhen(
                              data: (p) => p.fraction,
                              orElse: () => 0.0,
                            ),
                            size: desktopMode ? 26 : 24,
                            color: AppTheme.primaryBlue,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              projectTitle,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: '新建标题',
                            icon: Icon(
                              Icons.segment_rounded,
                              color: AppTheme.textSecondary,
                            ),
                            onPressed: () => _addHeading(context, ref),
                          ),
                          _projectMenu(context, ref, repo),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: _projectMeta(context, ref, repo)),
                  _reorderableTasks(context, repo, looseTasks),
                  for (final h in headings) ...[
                    SliverToBoxAdapter(
                      child: _headingTile(
                        context,
                        repo,
                        h,
                        headings,
                        collapsed: _collapsedHeadings.contains(h.id),
                        onToggle: () => setState(() {
                          if (!_collapsedHeadings.add(h.id)) {
                            _collapsedHeadings.remove(h.id);
                          }
                        }),
                      ),
                    ),
                    if (!_collapsedHeadings.contains(h.id))
                      _reorderableTasks(
                        context,
                        repo,
                        items
                            .where((i) => i.isTask && i.headingId == h.id)
                            .toList(),
                      ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _projectMenu(BuildContext context, WidgetRef ref, repo) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, color: AppTheme.textSecondary),
      onSelected: (v) async {
        switch (v) {
          case 'complete':
            await repo.toggleComplete(projectId, true);
            if (context.mounted) Navigator.of(context).maybePop();
            break;
          case 'when':
            await WhenPickerSheet.apply(context, ref, projectId);
            break;
          case 'deadline':
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: now,
              firstDate: now.subtract(const Duration(days: 1)),
              lastDate: now.add(const Duration(days: 365 * 5)),
            );
            if (picked != null) await repo.setDeadline(projectId, picked);
            break;
          case 'tags':
            TagPickerSheet.show(context, projectId);
            break;
          case 'duplicate':
            final newId = await repo.duplicateItem(projectId);
            if (context.mounted && newId != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('项目已复制')),
              );
            }
            break;
          case 'trash':
            await repo.moveToTrash(projectId);
            if (context.mounted) Navigator.of(context).maybePop();
            break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'complete', child: Text('完成项目')),
        PopupMenuItem(value: 'when', child: Text('计划（何时做）')),
        PopupMenuItem(value: 'deadline', child: Text('设置死线')),
        PopupMenuItem(value: 'tags', child: Text('标签')),
        PopupMenuItem(value: 'duplicate', child: Text('复制项目')),
        PopupMenuItem(value: 'trash', child: Text('删除项目')),
      ],
    );
  }

  Widget _projectMeta(BuildContext context, WidgetRef ref, repo) {
    final project = ref.watch(itemProvider(projectId)).value;
    if (project == null) return const SizedBox.shrink();
    final chips = <Widget>[];
    if (project.start == WhenStart.someday) {
      chips.add(_metaChip(Icons.archive_rounded, '将来', AppTheme.somedayGrey));
    } else if (project.startDate != null) {
      chips.add(
        _metaChip(
          Icons.calendar_today_rounded,
          DateFmt.groupLabel(project.startDate!),
          AppTheme.todayYellow,
        ),
      );
    }
    if (project.deadline != null) {
      chips.add(
        _metaChip(
          Icons.flag_rounded,
          DateFmt.deadlineLabel(project.deadline!),
          AppTheme.deadlineRed,
        ),
      );
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(desktopMode ? 32 : 20, 0, desktopMode ? 28 : 16, 8),
      child: Wrap(spacing: 12, children: chips),
    );
  }

  Widget _metaChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _headingTile(
    BuildContext context,
    repo,
    Item heading,
    List<Item> headings, {
      required bool collapsed,
      required VoidCallback onToggle,
    }) {
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      color: collapsed
          ? AppTheme.primaryBlue.withValues(alpha: 0.035)
          : Colors.transparent,
      padding: EdgeInsets.fromLTRB(
        desktopMode ? 28 : 16,
        desktopMode ? 16 : 20,
        desktopMode ? 28 : 16,
        4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!desktopMode) ...[
                Icon(
                  Icons.drag_indicator_rounded,
                  size: 18,
                  color: AppTheme.dividerColor,
                ),
                const SizedBox(width: 4),
              ],
              AnimatedRotation(
                turns: collapsed ? -0.25 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: IconButton(
                  tooltip: collapsed ? '展开标题' : '折叠标题',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: onToggle,
                ),
              ),
              Expanded(
                child: Text(
                  heading.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: desktopMode ? 16.5 : null,
                    color: desktopMode ? AppTheme.primaryBlue : null,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz, color: AppTheme.textSecondary),
                onSelected: (v) async {
                  if (v == 'add') {
                    AddEditItemModal.pushCreate(
                      context,
                      projectId: projectId,
                      headingId: heading.id,
                    );
                  }
                  if (v == 'archive') repo.setHeadingArchived(heading.id, true);
                  if (v == 'duplicate') {
                    await repo.duplicateItem(heading.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('标题及任务已复制')),
                      );
                    }
                  }
                  if (v == 'trash') repo.moveToTrash(heading.id);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'add', child: Text('在此标题下添加任务')),
                  PopupMenuItem(value: 'duplicate', child: Text('复制标题及任务')),
                  PopupMenuItem(value: 'archive', child: Text('归档标题')),
                  PopupMenuItem(value: 'trash', child: Text('删除标题')),
                ],
              ),
            ],
          ),
          const Divider(),
        ],
      ),
    );

    // 整组标题长按可拖动，落到另一个标题上即交换顺序（带动其下任务）。
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != heading.id,
      onAcceptWithDetails: (d) {
        final ids = headings.map((e) => e.id).toList();
        final from = ids.indexOf(d.data);
        final to = ids.indexOf(heading.id);
        if (from < 0 || to < 0) return;
        final moved = ids.removeAt(from);
        ids.insert(to, moved);
        repo.reorder(ids);
      },
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        return LongPressDraggable<String>(
          data: heading.id,
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width - 32,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: tile,
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: tile),
          child: Container(
            color: active
                ? AppTheme.primaryBlue.withValues(alpha: 0.08)
                : Colors.transparent,
            child: tile,
          ),
        );
      },
    );
  }

  /// 任务清单（同组内长按拖拽排序）。
  Widget _reorderableTasks(BuildContext context, repo, List<Item> tasks) {
    if (tasks.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: SliverReorderableList(
        itemCount: tasks.length,
        onReorderItem: (oldIndex, newIndex) {
          final reordered = [...tasks];
          final moved = reordered.removeAt(oldIndex);
          reordered.insert(newIndex, moved);
          repo.reorder(reordered.map((e) => e.id).toList());
        },
        itemBuilder: (context, index) {
          final task = tasks[index];
          return ReorderableDelayedDragStartListener(
            key: ValueKey(task.id),
            index: index,
            child: _desktopSelectionWrap(
              ItemRow(
                item: task,
                desktopMode: desktopMode,
                onTapTask: (i) => _openTask(context, i),
              ),
              task,
            )
                .animate(delay: (index * 12).ms)
                .fadeIn(duration: 150.ms)
                .slideX(begin: 0.018, end: 0, curve: Curves.easeOutCubic),
          );
        },
      ),
    );
  }

  Widget _desktopSelectionWrap(Widget child, Item item) {
    final selected =
        desktopMode && inspectedItemId != null && inspectedItemId == item.id;
    if (!selected) return child;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.07),
        border: const Border(
          left: BorderSide(color: AppTheme.primaryBlue, width: 3),
        ),
      ),
      child: child,
    );
  }
}
