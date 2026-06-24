import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/calendar_service.dart';
import '../../domain/models/item.dart';
import '../app_view.dart';
import '../providers/item_providers.dart';
import '../shared/theme/app_theme.dart';
import '../shared/utils/date_format.dart';
import '../shared/widgets/empty_illustration.dart';
import '../shared/widgets/item_row.dart';
import '../shared/widgets/inline_task_editor.dart';
import '../shared/widgets/magic_plus.dart';
import '../shared/widgets/when_picker_sheet.dart';
import 'project_screen.dart';
import 'task_detail_screen.dart';

/// 任意系统视图（收件箱/今天/计划/随时/将来/日志）的统一渲染器。
/// 通过 switch 处理「今天的今晚分区」「计划时间轴(含死线影子)」「日志按完成日分组」等差异，
/// 并在顶部提供轻量的标签过滤器（含从项目/区域继承的标签）。
class ViewScreen extends ConsumerStatefulWidget {
  final AppView view;

  /// 移动端 push 进来时显示返回箭头。
  final bool showBack;

  const ViewScreen({super.key, required this.view, this.showBack = false});

  @override
  ConsumerState<ViewScreen> createState() => _ViewScreenState();
}

class _ViewScreenState extends ConsumerState<ViewScreen> {
  String? _tagFilter;
  bool _selecting = false;
  final Set<String> _selected = {};

  /// 当前「原地展开」编辑的任务 id（同一时刻只展开一个）。
  String? _expandedId;

  AppView get view => widget.view;
  bool get showBack => widget.showBack;

  void _toggleSelect(Item item) {
    setState(() {
      if (!_selected.add(item.id)) _selected.remove(item.id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _batch(Future<void> Function(String id) action) async {
    final ids = _selected.toList();
    for (final id in ids) {
      await action(id);
    }
    _exitSelection();
  }

  /// 点任务：原地展开 / 收起编辑卡片（不再跳详情页）。
  void _toggleExpand(Item item) {
    setState(() => _expandedId = _expandedId == item.id ? null : item.id);
  }

  void _collapse() {
    if (_expandedId != null) setState(() => _expandedId = null);
  }

  /// 进入完整详情页（处理检查项 / 重复 / 提醒 / 移动等高级项）。
  void _openTaskDetail(BuildContext context, Item item) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TaskDetailScreen(initial: item),
    ));
  }

  /// 任务行：展开态渲染原地编辑器，否则渲染普通行。返回的 widget 带有 [ValueKey]。
  Widget _taskRowKeyed(BuildContext context, Item item,
      {bool showWhenDate = false}) {
    if (!_selecting && _expandedId == item.id && !item.isProject) {
      return InlineTaskEditor(
        key: ValueKey(item.id),
        item: item,
        onCollapse: _collapse,
        onOpenDetail: () {
          _collapse();
          _openTaskDetail(context, item);
        },
      );
    }
    return ItemRow(
      key: ValueKey(item.id),
      item: item,
      showWhenDate: showWhenDate,
      onTapTask: _toggleExpand,
      onTapProject: (i) => _openProject(context, i),
      selectionMode: _selecting,
      selected: _selected.contains(item.id),
      onToggleSelect: _toggleSelect,
    );
  }

  void _openProject(BuildContext context, Item item) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProjectScreen(projectId: item.id, projectTitle: item.title),
    ));
  }

  /// 该视图下「魔法加号」默认新建到哪个时间桶。
  MagicCreateContext get _magicContext {
    switch (view) {
      case AppView.today:
        return MagicCreateContext(defaultWhen: WhenChoice.today);
      case AppView.someday:
        return const MagicCreateContext(defaultWhen: WhenChoice.someday);
      case AppView.anytime:
      case AppView.upcoming:
        return const MagicCreateContext(defaultWhen: WhenChoice.anytime);
      case AppView.inbox:
      case AppView.logbook:
        return const MagicCreateContext(defaultWhen: WhenChoice.inbox);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MagicCreateScope(
      context: _magicContext,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    // 计划视图走「占格」流；其余视图走普通条目流。
    if (view == AppView.upcoming) return _buildUpcoming(context);

    final async = ref.watch(view.provider);
    final allTags = ref.watch(tagsProvider).value ?? const [];
    final links = ref.watch(effectiveItemTagLinksProvider).value ?? const {};

    return Scaffold(
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('出错了：$e')),
          data: (rawItems) {
            final presentTagIds = <String>{};
            for (final it in rawItems) {
              presentTagIds.addAll(links[it.id] ?? const <String>{});
            }
            final presentTags =
                allTags.where((t) => presentTagIds.contains(t.id)).toList();

            final activeFilter =
                (_tagFilter != null && presentTagIds.contains(_tagFilter))
                    ? _tagFilter
                    : null;
            final items = activeFilter == null
                ? rawItems
                : rawItems
                    .where((it) =>
                        (links[it.id] ?? const <String>{}).contains(activeFilter))
                    .toList();

            return Scaffold(
              bottomNavigationBar: _selecting ? _selectionBar(context) : null,
              body: CustomScrollView(
                slivers: [
                  _header(context, canSelect: rawItems.isNotEmpty),
                  if (!_selecting && presentTags.isNotEmpty)
                    _tagBar(context, presentTags, activeFilter),
                  if (rawItems.isEmpty)
                    _emptySliver(context)
                  else if (_selecting)
                    _flatList(context, items)
                  else if (items.isEmpty)
                    _filteredEmptySliver(context)
                  else
                    ..._buildBody(context, items),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _selectionBar(BuildContext context) {
    final repo = ref.read(itemRepositoryProvider);
    Widget action(IconData icon, String label, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          onTap: _selected.isEmpty ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    color: _selected.isEmpty
                        ? AppTheme.textSecondary
                        : AppTheme.primaryBlue),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        color: _selected.isEmpty
                            ? AppTheme.textSecondary
                            : AppTheme.primaryBlue)),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.dividerColor)),
        ),
        child: Row(
          children: [
            action(Icons.check_circle_outline, '完成',
                () => _batch((id) => repo.toggleComplete(id, true))),
            action(Icons.calendar_today_rounded, '计划', () async {
              final choice = await WhenPickerSheet.showChoice(context);
              if (choice == null) return;
              await _batch((id) => repo.setWhen(id,
                  start: choice.start,
                  startDate: choice.startDate,
                  evening: choice.evening));
            }),
            action(Icons.delete_outline, '删除',
                () => _batch((id) => repo.moveToTrash(id))),
          ],
        ),
      ),
    );
  }

  // ---------------- 计划：时间轴 + 死线影子 ----------------
  Widget _buildUpcoming(BuildContext context) {
    final async = ref.watch(upcomingEntriesProvider);
    return Scaffold(
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('出错了：$e')),
          data: (entries) {
            if (entries.isEmpty) {
              return CustomScrollView(
                slivers: [_header(context), _emptySliver(context)],
              );
            }
            // 按日期分组（任务条目 + 系统日历事件）
            final groups = <String, List<ScheduleEntry>>{};
            final labels = <String, String>{};
            final dates = <String, DateTime>{};
            for (final e in entries) {
              final d = e.date;
              final key = '${d.year}-${d.month}-${d.day}';
              groups.putIfAbsent(key, () => []).add(e);
              labels[key] = DateFmt.groupLabel(d);
              dates[key] = DateTime(d.year, d.month, d.day);
            }
            final calEvents = ref.watch(upcomingCalendarProvider).value ?? const [];
            final eventGroups = <String, List<CalEvent>>{};
            for (final ev in calEvents) {
              final d = ev.start;
              final key = '${d.year}-${d.month}-${d.day}';
              eventGroups.putIfAbsent(key, () => []).add(ev);
              labels.putIfAbsent(key, () => DateFmt.groupLabel(d));
              dates.putIfAbsent(key, () => DateTime(d.year, d.month, d.day));
            }
            final allKeys = {...groups.keys, ...eventGroups.keys}.toList()
              ..sort((a, b) => dates[a]!.compareTo(dates[b]!));
            final slivers = <Widget>[_header(context)];
            for (final key in allKeys) {
              slivers.add(SliverToBoxAdapter(
                  child: _upcomingGroupHeader(
                      context, labels[key]!, dates[key]!)));
              final evs = eventGroups[key];
              if (evs != null) {
                slivers.add(SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _calendarEventTile(context, evs[i]),
                    childCount: evs.length,
                  ),
                ));
              }
              final ents = groups[key];
              if (ents != null) slivers.add(_entryList(context, ents));
            }
            slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 96)));
            return CustomScrollView(slivers: slivers);
          },
        ),
      ),
    );
  }

  /// 计划视图的日期分组头：兼作拖拽改期的放置目标。
  Widget _upcomingGroupHeader(BuildContext context, String label, DateTime date) {
    final repo = ref.read(itemRepositoryProvider);
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) {
        repo.setWhen(d.data, start: WhenStart.anytime, startDate: date);
      },
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: active
                ? AppTheme.primaryBlue.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _groupHeader(context, label),
        );
      },
    );
  }

  Widget _entryList(BuildContext context, List<ScheduleEntry> entries) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final e = entries[index];
            // 展开态：原地编辑器（仅对真实可编辑的计划条目）。
            if (!_selecting &&
                !e.isShadow &&
                !e.isDeadline &&
                !e.item.isProject &&
                _expandedId == e.item.id) {
              return _taskRowKeyed(context, e.item);
            }
            final row = ItemRow(
              item: e.item,
              deadlineShadow: e.isDeadline,
              onTapTask: _toggleExpand,
              onTapProject: (i) => _openProject(context, i),
            );
            // 真实的「计划」条目可长按拖到别的日期分组改期。
            final draggable = !e.isShadow && !e.isDeadline;
            if (draggable) {
              return LongPressDraggable<String>(
                data: e.item.id,
                feedback: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: MediaQuery.of(context).size.width - 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: row,
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.3, child: row),
                child: row
                    .animate()
                    .fadeIn(duration: 220.ms, delay: (index * 18).ms)
                    .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
              );
            }
            if (e.isShadow) {
              // 重复任务的未来影子：半透明、不可交互、带循环图标。
              return IgnorePointer(
                child: Opacity(
                  opacity: 0.45,
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(Icons.repeat_rounded,
                          size: 16, color: AppTheme.textSecondary),
                      Expanded(child: row),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 220.ms, delay: (index * 18).ms);
            }
            return row
                .animate()
                .fadeIn(duration: 220.ms, delay: (index * 18).ms)
                .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic);
          },
          childCount: entries.length,
        ),
      ),
    );
  }

  Widget _header(BuildContext context, {bool canSelect = false}) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            if (showBack && !_selecting)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  color: AppTheme.textSecondary,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            Icon(view.icon, color: view.color, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                  _selecting ? '已选 ${_selected.length} 项' : view.title,
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            if (canSelect && !_selecting)
              IconButton(
                tooltip: '多选',
                icon: Icon(Icons.checklist_rounded,
                    color: AppTheme.textSecondary),
                onPressed: () => setState(() => _selecting = true),
              ),
            if (_selecting)
              TextButton(onPressed: _exitSelection, child: const Text('完成')),
          ],
        ).animate().fadeIn(duration: 250.ms).slideX(begin: -0.05, end: 0),
      ),
    );
  }

  Widget _tagBar(BuildContext context, List<Tag> tags, String? active) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final tag in tags)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: FilterChip(
                  label: Text('# ${tag.title}'),
                  selected: active == tag.id,
                  showCheckmark: false,
                  selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                  onSelected: (sel) =>
                      setState(() => _tagFilter = sel ? tag.id : null),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptySliver(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 40, 40, 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            EmptyIllustration(view: view)
                .animate()
                .fadeIn(duration: 500.ms)
                .scaleXY(
                    begin: 0.9,
                    end: 1,
                    curve: Curves.easeOutBack,
                    duration: 600.ms),
            const SizedBox(height: 22),
            Text(view.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(view.emptyHint,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center),
          ],
        ).animate().fadeIn(duration: 400.ms),
      ),
    );
  }

  Widget _filteredEmptySliver(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 60.0),
        child: Text('该标签下没有任务',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center),
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context, List<Item> items) {
    switch (view) {
      case AppView.today:
        return _todayBody(context, items);
      case AppView.logbook:
        return _groupedByDate(context, items, (i) => i.completedAt, DateFmt.logLabel);
      case AppView.inbox:
      case AppView.anytime:
      case AppView.someday:
        // 这些是「整段单列」视图，支持长按拖拽排序。
        return [_reorderableList(context, items)];
      default:
        return [_flatList(context, items)];
    }
  }

  Widget _reorderableList(BuildContext context, List<Item> items,
      {bool todayOrder = false}) {
    final repo = ref.read(itemRepositoryProvider);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: SliverReorderableList(
        itemCount: items.length,
        onReorderItem: (oldIndex, newIndex) {
          final reordered = [...items];
          final moved = reordered.removeAt(oldIndex);
          reordered.insert(newIndex, moved);
          repo.reorder(reordered.map((e) => e.id).toList(),
              todayOrder: todayOrder);
        },
        itemBuilder: (context, index) {
          final it = items[index];
          if (!_selecting && _expandedId == it.id && !it.isProject) {
            return _taskRowKeyed(context, it,
                showWhenDate: view == AppView.anytime);
          }
          return ReorderableDelayedDragStartListener(
            key: ValueKey(it.id),
            index: index,
            child: ItemRow(
              item: it,
              showWhenDate: view == AppView.anytime,
              onTapTask: _toggleExpand,
              onTapProject: (i) => _openProject(context, i),
            ),
          );
        },
      ),
    );
  }

  Widget _calendarEventTile(BuildContext context, CalEvent e) {
    final timeLabel = e.allDay
        ? '全天'
        : '${e.start.hour.toString().padLeft(2, '0')}:${e.start.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.event_rounded, size: 16, color: AppTheme.primaryBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(e.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge),
          ),
          Text(timeLabel,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  // 今天：系统日历事件 + 白天任务 + 常驻的「今晚」分隔线 + 夜晚任务。
  List<Widget> _todayBody(BuildContext context, List<Item> items) {
    final day = items.where((i) => !i.evening).toList();
    final evening = items.where((i) => i.evening).toList();
    final events = ref.watch(todayCalendarProvider).value ?? const [];
    return [
      if (events.isNotEmpty)
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _calendarEventTile(context, events[i]),
            childCount: events.length,
          ),
        ),
      if (events.isNotEmpty)
        const SliverToBoxAdapter(child: Divider(indent: 16, endIndent: 16)),
      if (day.isNotEmpty)
        if (_selecting) _flatList(context, day) else _reorderableList(context, day, todayOrder: true),
      SliverToBoxAdapter(child: _eveningDivider(context)),
      if (evening.isNotEmpty)
        if (_selecting) _flatList(context, evening) else _reorderableList(context, evening, todayOrder: true)
      else
        SliverToBoxAdapter(child: _eveningHint(context)),
    ];
  }

  Widget _eveningHint(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
      child: Text('把任务的「计划」设为今晚，它会出现在这里',
          style: Theme.of(context).textTheme.bodyMedium),
    );
  }

  Widget _eveningDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          const Icon(Icons.nightlight_round, size: 16, color: AppTheme.eveningIndigo),
          const SizedBox(width: 8),
          Text('今晚',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.eveningIndigo, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  List<Widget> _groupedByDate(
    BuildContext context,
    List<Item> items,
    DateTime? Function(Item) keyOf,
    String Function(DateTime) labelOf,
  ) {
    final groups = <String, List<Item>>{};
    final labels = <String, String>{};
    for (final item in items) {
      final d = keyOf(item);
      if (d == null) continue;
      final key = '${d.year}-${d.month}-${d.day}';
      groups.putIfAbsent(key, () => []).add(item);
      labels[key] = labelOf(d);
    }
    final slivers = <Widget>[];
    for (final entry in groups.entries) {
      slivers.add(SliverToBoxAdapter(child: _groupHeader(context, labels[entry.key]!)));
      slivers.add(_flatList(context, entry.value));
    }
    return slivers;
  }

  Widget _groupHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 2),
      child: Text(label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
    );
  }

  Widget _flatList(BuildContext context, List<Item> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final it = items[index];
            final row = _taskRowKeyed(context, it,
                showWhenDate: view == AppView.anytime);
            if (_selecting || _expandedId == it.id) return row;
            return row
                .animate()
                .fadeIn(duration: 200.ms, delay: (index * 16).ms)
                .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic);
          },
          childCount: items.length,
        ),
      ),
    );
  }
}
