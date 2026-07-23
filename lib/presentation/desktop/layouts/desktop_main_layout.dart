import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/item.dart';
import '../../app_view.dart';
import '../../providers/item_providers.dart';
import '../../screens/ai_conversation_capture_screen.dart';
import '../../screens/project_screen.dart';
import '../../screens/search_screen.dart';
import '../../screens/task_detail_screen.dart';
import '../../screens/view_screen.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/utils/date_format.dart';
import '../../shared/widgets/add_edit_item_modal.dart';
import '../../shared/widgets/magic_plus.dart';
import '../../shared/widgets/tag_picker_sheet.dart';
import '../../shared/widgets/things_checkbox.dart';
import '../../shared/widgets/when_picker_sheet.dart';
import '../widgets/things_sidebar.dart';

class DesktopMainLayout extends StatefulWidget {
  const DesktopMainLayout({super.key});

  @override
  State<DesktopMainLayout> createState() => _DesktopMainLayoutState();
}

class _DesktopMainLayoutState extends State<DesktopMainLayout> {
  SidebarSelection _selection = const SidebarSelection.system(AppView.today);
  bool _slim = false;
  String? _inspectedItemId;
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  bool get _typingInField {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  String get _title => _selection.isProject
      ? (_selection.projectTitle ?? '项目')
      : (_selection.view ?? AppView.today).title;

  IconData get _icon => _selection.isProject
      ? Icons.folder_rounded
      : (_selection.view ?? AppView.today).icon;

  Color get _accent => _selection.isProject
      ? AppTheme.primaryBlue
      : (_selection.view ?? AppView.today).color;

  void _openSearch({String? initial}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SearchScreen(initialQuery: initial)),
    );
  }

  void _openAiCapture() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(
          name: MagicPlusNavObserver.hidePlusRouteName,
        ),
        builder: (_) => AiConversationCaptureScreen(
          projectId: _selection.isProject ? _selection.projectId : null,
        ),
      ),
    );
  }

  void _select(SidebarSelection selection) {
    setState(() {
      _selection = selection;
      _inspectedItemId = null;
    });
  }

  void _inspect(Item item) {
    if (!item.isTask) return;
    setState(() => _inspectedItemId = item.id);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_typingInField) return KeyEventResult.ignored;
    final ch = event.character;
    if (ch != null &&
        ch.isNotEmpty &&
        ch.trim().isNotEmpty &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        ch.codeUnitAt(0) >= 0x20) {
      _openSearch(initial: ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            AddEditItemModal.pushCreate(context),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            AddEditItemModal.pushCreate(context),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.backslash, meta: true): () =>
            setState(() => _slim = !_slim),
        const SingleActivator(
          LogicalKeyboardKey.backslash,
          control: true,
        ): () =>
            setState(() => _slim = !_slim),
      },
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppTheme.backgroundLight,
          body: Row(
            children: [
              AnimatedContainer(
                width: _slim ? 0 : 268,
                duration: const Duration(milliseconds: 190),
                curve: Curves.easeOutCubic,
                child: _slim
                    ? const SizedBox.shrink()
                    : ThingsSidebar(selection: _selection, onSelect: _select),
              ),
              Expanded(
                child: Column(
                  children: [
                    _topBar(context),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _workspace(context)),
                          _DesktopInspector(
                            itemId: _inspectedItemId,
                            selection: _selection,
                            onClear: () =>
                                setState(() => _inspectedItemId = null),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.dividerColor)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: _slim ? '展开侧栏' : '收起侧栏',
            icon: Icon(
              _slim ? Icons.menu_open_rounded : Icons.menu_rounded,
              size: 21,
            ),
            onPressed: () => setState(() => _slim = !_slim),
          ),
          const SizedBox(width: 6),
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_icon, size: 17, color: _accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          _ToolbarIcon(
            tooltip: '搜索',
            icon: Icons.search_rounded,
            onPressed: _openSearch,
          ),
          _ToolbarIcon(
            tooltip: 'AI 理清',
            icon: Icons.auto_awesome_outlined,
            onPressed: _openAiCapture,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => AddEditItemModal.pushCreate(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('新建'),
          ),
        ],
      ),
    );
  }

  Widget _workspace(BuildContext context) {
    final child = _selection.isProject
        ? ProjectScreen(
            key: ValueKey(_selection.projectId),
            projectId: _selection.projectId!,
            projectTitle: _selection.projectTitle ?? '项目',
            desktopMode: true,
            inspectedItemId: _inspectedItemId,
            onInspectItem: _inspect,
          )
        : ViewScreen(
            key: ValueKey(_selection.view),
            view: _selection.view ?? AppView.today,
            desktopMode: true,
            inspectedItemId: _inspectedItemId,
            onInspectItem: _inspect,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: AppTheme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ToolbarIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _ToolbarIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 21),
      color: AppTheme.textSecondary,
      onPressed: onPressed,
    );
  }
}

class _DesktopInspector extends ConsumerWidget {
  final String? itemId;
  final SidebarSelection selection;
  final VoidCallback onClear;

  const _DesktopInspector({
    required this.itemId,
    required this.selection,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 332,
      margin: const EdgeInsets.fromLTRB(0, 16, 16, 18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppTheme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: itemId == null
          ? _InspectorEmpty(selection: selection)
          : ref
                .watch(itemProvider(itemId!))
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (item) {
                    if (item == null || item.trashed) {
                      return _InspectorEmpty(selection: selection);
                    }
                    return _InspectorDetails(item: item, onClear: onClear);
                  },
                ),
    );
  }
}

class _InspectorEmpty extends ConsumerWidget {
  final SidebarSelection selection;

  const _InspectorEmpty({required this.selection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = selection.isProject
        ? (selection.projectTitle ?? '项目')
        : (selection.view ?? AppView.today).title;
    final icon = selection.isProject
        ? Icons.folder_rounded
        : (selection.view ?? AppView.today).icon;
    final color = selection.isProject
        ? AppTheme.primaryBlue
        : (selection.view ?? AppView.today).color;
    final count = selection.isProject
        ? ref
              .watch(projectItemsProvider(selection.projectId ?? ''))
              .value
              ?.length
        : ref.watch((selection.view ?? AppView.today).provider).value?.length;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            count == null ? '正在载入' : '$count 项',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const Spacer(),
          const Divider(),
          const SizedBox(height: 14),
          Text(
            '未选择任务',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _InspectorDetails extends ConsumerStatefulWidget {
  final Item item;
  final VoidCallback onClear;

  const _InspectorDetails({required this.item, required this.onClear});

  @override
  ConsumerState<_InspectorDetails> createState() => _InspectorDetailsState();
}

class _InspectorDetailsState extends ConsumerState<_InspectorDetails> {
  late final TextEditingController _title;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.item.title);
  }

  @override
  void didUpdateWidget(covariant _InspectorDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _saveTitleFor(oldWidget.item);
      _title.text = widget.item.title;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _saveTitle();
    _title.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _saveTitle);
  }

  void _saveTitle() {
    _saveTitleFor(widget.item);
  }

  void _saveTitleFor(Item item) {
    final next = _title.text.trim();
    if (next.isEmpty || next == item.title) return;
    ref.read(itemRepositoryProvider).updateContent(item.id, title: next);
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
    final item = widget.item;
    final repo = ref.read(itemRepositoryProvider);
    final tags = ref.watch(itemTagsProvider(item.id)).value ?? const [];
    final inherited =
        ref.watch(inheritedTagsProvider(item.id)).value ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
      children: [
        Row(
          children: [
            ThingsCheckbox(
              value: item.isCompleted,
              onChanged: (v) => repo.toggleComplete(item.id, v ?? false),
            ),
            const Spacer(),
            IconButton(
              tooltip: '收起',
              onPressed: widget.onClear,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        TextField(
          controller: _title,
          onChanged: (_) => _scheduleSave(),
          onSubmitted: (_) => _saveTitle(),
          maxLines: null,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
          decoration: const InputDecoration(
            hintText: '任务标题',
            border: InputBorder.none,
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        const Divider(),
        _InspectorTile(
          icon: Icons.calendar_today_rounded,
          color: AppTheme.todayYellow,
          label: '计划',
          value: _whenLabel(item),
          onTap: () => WhenPickerSheet.apply(context, ref, item.id),
        ),
        _InspectorTile(
          icon: Icons.flag_rounded,
          color: AppTheme.deadlineRed,
          label: '截止',
          value: item.deadline == null
              ? '无'
              : DateFmt.deadlineLabel(item.deadline!),
          onTap: () => _pickDeadline(context, repo, item),
          onClear: item.deadline == null
              ? null
              : () => repo.setDeadline(item.id, null),
        ),
        _InspectorTile(
          icon: Icons.label_outline_rounded,
          color: AppTheme.primaryBlue,
          label: '标签',
          value: tags.isEmpty && inherited.isEmpty
              ? '无'
              : [...tags, ...inherited].map((t) => t.title).join(' / '),
          onTap: () => TagPickerSheet.show(context, item.id),
        ),
        const SizedBox(height: 18),
        FilledButton.tonalIcon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TaskDetailScreen(initial: item)),
          ),
          icon: const Icon(Icons.open_in_full_rounded, size: 18),
          label: const Text('完整详情'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () async {
            await repo.moveToTrash(item.id);
            widget.onClear();
          },
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('移到垃圾桶'),
        ),
      ],
    );
  }

  Future<void> _pickDeadline(
    BuildContext context,
    dynamic repo,
    Item item,
  ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: item.deadline ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: '选择截止日期',
    );
    if (picked != null) {
      await repo.setDeadline(item.id, picked);
    }
  }
}

class _InspectorTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _InspectorTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            SizedBox(
              width: 46,
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onClear != null)
              IconButton(
                tooltip: '清除',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 16),
              )
            else
              const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}
