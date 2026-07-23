import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_providers.dart';
import '../../ai/agent/capture_agent.dart';
import '../../ai/capture/capture_draft.dart';
import '../../ai/capture/capture_parser.dart';
import '../../ai/core/llm_exception.dart';
import '../../domain/models/item.dart';
import '../providers/item_providers.dart';
import '../shared/theme/app_theme.dart';
import '../shared/utils/date_format.dart';
import '../shared/widgets/move_target_sheet.dart';
import '../shared/widgets/when_picker_sheet.dart';
import 'ai_settings_screen.dart';

const _hideGlobalMagicPlusRoute = 'hide-global-magic-plus';

class AiConversationCaptureScreen extends ConsumerStatefulWidget {
  final String? initialText;
  final String? projectId;
  final String? headingId;

  const AiConversationCaptureScreen({
    super.key,
    this.initialText,
    this.projectId,
    this.headingId,
  });

  @override
  ConsumerState<AiConversationCaptureScreen> createState() =>
      _AiConversationCaptureScreenState();
}

class _AiConversationCaptureScreenState
    extends ConsumerState<AiConversationCaptureScreen> {
  final _input = TextEditingController();
  final _focusNode = FocusNode();
  final _scroll = ScrollController();
  final List<_ChatLine> _lines = [];
  final List<_DraftEdit> _drafts = [];

  int _draftSeq = 0;
  bool _thinking = false;
  bool _creating = false;
  List<String> _lastCreatedIds = const [];
  List<String> _lastCreatedAreaIds = const [];
  int _lastCreatedCount = 0;
  List<String> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialText?.trim();
    if (initial != null && initial.isNotEmpty) {
      _input.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _send());
    } else {
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _focusNode.dispose();
    _scroll.dispose();
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  bool get _hasValidDraft =>
      _drafts.any((d) => d.include && d.title.text.trim().isNotEmpty);

  int get _createCount {
    var total = 0;
    for (final d in _drafts.where((d) => d.include)) {
      if (d.title.text.trim().isEmpty) continue;
      total += 1;
      if (d.type == ItemType.project) {
        total += d.children
            .where((c) => c.include && c.title.text.trim().isNotEmpty)
            .length;
      }
    }
    return total;
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _append(_ChatLine line) {
    setState(() => _lines.add(line));
    _scrollToEnd();
  }

  Future<void> _openSettings() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: _hideGlobalMagicPlusRoute),
        builder: (_) => const AiSettingsScreen(),
      ),
    );
  }

  Future<void> _sendPreset(String text) async {
    _input.text = text;
    await _send();
  }

  Future<void> _send() async {
    final raw = _input.text.trim();
    if (raw.isEmpty || _thinking || _creating) return;
    final history = _agentHistory();
    _input.clear();
    _suggestions = const [];
    _append(_ChatLine.user(raw));

    if (_drafts.isNotEmpty && _isCreateCommand(raw)) {
      await _commitDrafts();
      return;
    }

    if (!ref.read(aiEnabledProvider)) {
      _append(_ChatLine.assistant('先配置一个 AI 模型。', needsConfig: true));
      return;
    }

    setState(() => _thinking = true);
    _scrollToEnd();

    final ctx = CaptureContext(
      now: DateTime.now(),
      projectNames: (ref.read(projectsProvider).value ?? [])
          .map((e) => e.title)
          .toList(),
      areaNames: (ref.read(areasProvider).value ?? [])
          .map((e) => e.title)
          .toList(),
      tagNames: (ref.read(tagsProvider).value ?? [])
          .map((e) => e.title)
          .toList(),
    );

    try {
      final result = await ref
          .read(captureAgentProvider)
          .run(
            latest: raw,
            context: ctx,
            currentDraft: _currentDraft(),
            history: history,
          );
      if (!mounted) return;
      _replaceDraft(result.draft);
      setState(() {
        _thinking = false;
        _suggestions = result.suggestions;
      });
      _append(_ChatLine.assistant(result.message));
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() => _thinking = false);
      _append(
        _ChatLine.assistant(
          e.isNotConfigured ? '先配置一个 AI 模型。' : '整理失败：${e.message}',
          needsConfig: e.isNotConfigured,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _thinking = false);
      _append(_ChatLine.assistant('整理失败：$e'));
    }
  }

  bool _isCreateCommand(String raw) {
    const exact = {'创建', '确认', '保存', '就这样', '可以', '没问题'};
    return exact.contains(raw) || raw.contains('直接创建') || raw.contains('帮我建');
  }

  List<CaptureAgentMessage> _agentHistory() {
    return [
      for (final line in _lines)
        if (line.role == _LineRole.user || line.role == _LineRole.assistant)
          CaptureAgentMessage(
            line.role == _LineRole.user ? 'user' : 'assistant',
            line.text,
          ),
    ];
  }

  CaptureDraft? _currentDraft() {
    if (_drafts.isEmpty) return null;
    final tags = ref.read(tagsProvider).value ?? [];
    String? tagTitle(String id) {
      for (final tag in tags) {
        if (tag.id == id) return tag.title;
      }
      return null;
    }

    return CaptureDraft(
      source: 'current',
      items: [
        for (final draft in _drafts)
          DraftItem(
            title: draft.title.text.trim(),
            type: draft.type,
            when: _fromWhenChoice(draft.when),
            deadline: draft.deadline,
            tagNames: [
              for (final id in draft.tagIds)
                if (tagTitle(id) != null) tagTitle(id)!,
              ...draft.newTagNames,
            ],
            listName: _containerNameForAgent(draft),
            listKind: draft.newAreaName != null
                ? DraftListKind.newArea
                : (draft.newProjectName != null
                      ? DraftListKind.newProject
                      : null),
            children: [
              for (final child in draft.children)
                DraftChild(
                  title: child.title.text.trim(),
                  when: _fromWhenChoice(child.when),
                  deadline: child.deadline,
                  include: child.include,
                ),
            ],
          ),
      ],
    );
  }

  static DraftWhen _fromWhenChoice(WhenChoice choice) {
    if (choice.start == WhenStart.someday) {
      return const DraftWhen(DraftWhenKind.someday);
    }
    if (choice.startDate == null) return DraftWhen.none;
    if (choice.evening) return const DraftWhen(DraftWhenKind.evening);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(
      choice.startDate!.year,
      choice.startDate!.month,
      choice.startDate!.day,
    );
    if (date == today) return const DraftWhen(DraftWhenKind.today);
    return DraftWhen(DraftWhenKind.date, date: date);
  }

  static String? _listNameForAgent(MoveTarget? target) {
    if (target == null) return null;
    if (target.inbox) return DraftItem.inboxToken;
    return target.projectTitle ?? target.areaTitle;
  }

  static String? _containerNameForAgent(_DraftEdit draft) {
    if (draft.newAreaName != null) return draft.newAreaName;
    if (draft.newProjectName != null) return draft.newProjectName;
    return _listNameForAgent(draft.list);
  }

  void _replaceDraft(CaptureDraft draft) {
    for (final d in _drafts) {
      d.dispose();
    }
    _drafts
      ..clear()
      ..addAll(_buildDraftEdits(draft));
  }

  List<_DraftEdit> _buildDraftEdits(CaptureDraft draft) {
    final projects = ref.read(projectsProvider).value ?? [];
    final areas = ref.read(areasProvider).value ?? [];
    final tags = ref.read(tagsProvider).value ?? [];

    MoveTarget? resolveList(String? name) {
      if (name == null) {
        if (widget.projectId == null) return null;
        final match = projects.where((p) => p.id == widget.projectId);
        if (match.isEmpty) return null;
        return MoveTarget.project(match.first.id, match.first.title);
      }
      if (name == DraftItem.inboxToken) return const MoveTarget.inbox();
      final projectMatch = projects.where(
        (e) => e.title.toLowerCase() == name.toLowerCase(),
      );
      if (projectMatch.isNotEmpty) {
        return MoveTarget.project(
          projectMatch.first.id,
          projectMatch.first.title,
        );
      }
      final areaMatch = areas.where(
        (e) => e.title.toLowerCase() == name.toLowerCase(),
      );
      if (areaMatch.isNotEmpty) {
        return MoveTarget.area(areaMatch.first.id, areaMatch.first.title);
      }
      return null;
    }

    return [
      for (final item in draft.items)
        () {
          final list = resolveList(item.listName);
          final unresolved =
              list == null &&
              item.listName != null &&
              item.listName != DraftItem.inboxToken;
          return _DraftEdit(
            id: ++_draftSeq,
            title: item.title,
            type: item.type,
            when: _toWhenChoice(item.when),
            deadline: item.deadline,
            list: list,
            newAreaName: unresolved && item.listKind == DraftListKind.newArea
                ? item.listName
                : null,
            newProjectName:
                unresolved && item.listKind == DraftListKind.newProject
                ? item.listName
                : null,
            tagIds: {
              for (final name in item.tagNames)
                for (final tag in tags)
                  if (tag.title.toLowerCase() == name.toLowerCase()) tag.id,
            },
            newTagNames: [
              for (final name in item.tagNames)
                if (!tags.any(
                  (tag) => tag.title.toLowerCase() == name.toLowerCase(),
                ))
                  name,
            ],
            children: [
              for (final child in item.children)
                _DraftChildEdit(
                  child.title,
                  when: _toWhenChoice(child.when),
                  deadline: child.deadline,
                ),
            ],
          );
        }(),
    ];
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

  Future<void> _commitDrafts() async {
    if (!_hasValidDraft || _creating) return;
    setState(() => _creating = true);
    final repo = ref.read(itemRepositoryProvider);
    final created = <String>[];
    final createdAreaIds = <String>[];
    final projects = ref.read(projectsProvider).value ?? [];
    final areas = ref.read(areasProvider).value ?? [];

    String? existingAreaId(String name) {
      final lower = name.toLowerCase();
      for (final area in areas) {
        if (area.title.toLowerCase() == lower) return area.id;
      }
      return null;
    }

    String? existingProjectId(String name) {
      final lower = name.toLowerCase();
      for (final project in projects) {
        if (project.title.toLowerCase() == lower) return project.id;
      }
      return null;
    }

    try {
      for (final draft in _drafts.where((d) => d.include)) {
        final title = draft.title.text.trim();
        if (title.isEmpty) continue;

        final tagIds = <String>{...draft.tagIds};
        for (final name in draft.newTagNames) {
          final trimmed = name.trim();
          if (trimmed.isNotEmpty) tagIds.add(await repo.createTag(trimmed));
        }

        String? areaId;
        String? projectId;
        var toInbox = false;
        if (draft.list != null) {
          areaId = draft.list!.areaId;
          projectId = draft.list!.projectId;
          toInbox = draft.list!.inbox;
        } else if (draft.newAreaName != null) {
          final name = draft.newAreaName!.trim();
          if (name.isNotEmpty) {
            areaId = existingAreaId(name);
            if (areaId == null) {
              areaId = await repo.createArea(title: name);
              createdAreaIds.add(areaId);
            }
          }
        } else if (draft.newProjectName != null &&
            draft.type == ItemType.task) {
          final name = draft.newProjectName!.trim();
          if (name.isNotEmpty) {
            projectId = existingProjectId(name);
            if (projectId == null) {
              projectId = await repo.createProject(title: name);
              created.add(projectId);
            }
          }
        } else {
          projectId = widget.projectId;
        }

        var start = draft.when.start;
        final hasParent = projectId != null || areaId != null;
        if (hasParent && start == WhenStart.inbox && !toInbox) {
          start = WhenStart.anytime;
        }

        if (draft.type == ItemType.project) {
          final projectId = await repo.createProject(
            title: title,
            areaId: areaId,
            start: start == WhenStart.inbox ? WhenStart.anytime : start,
          );
          created.add(projectId);
          if (draft.when.startDate != null ||
              draft.when.start == WhenStart.someday) {
            await repo.setWhen(
              projectId,
              start: draft.when.start == WhenStart.inbox
                  ? WhenStart.anytime
                  : draft.when.start,
              startDate: draft.when.startDate,
              evening: draft.when.evening,
            );
          }
          if (draft.deadline != null) {
            await repo.setDeadline(projectId, draft.deadline);
          }
          for (final tagId in tagIds) {
            await repo.attachTag(projectId, tagId);
          }
          for (final child in draft.children.where((c) => c.include)) {
            final childTitle = child.title.text.trim();
            if (childTitle.isEmpty) continue;
            final childId = await repo.createTask(
              title: childTitle,
              start: child.when.start == WhenStart.inbox
                  ? WhenStart.anytime
                  : child.when.start,
              startDate: child.when.startDate,
              evening: child.when.evening,
              deadline: child.deadline,
              projectId: projectId,
            );
            created.add(childId);
          }
        } else {
          final taskId = await repo.createTask(
            title: title,
            start: start,
            startDate: draft.when.startDate,
            evening: draft.when.evening,
            deadline: draft.deadline,
            areaId: areaId,
            projectId: projectId,
            headingId: widget.headingId,
          );
          created.add(taskId);
          for (final tagId in tagIds) {
            await repo.attachTag(taskId, tagId);
          }
          for (final child in draft.children.where((c) => c.include)) {
            final childTitle = child.title.text.trim();
            if (childTitle.isNotEmpty) {
              await repo.addChecklistItem(taskId, childTitle);
            }
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      _append(_ChatLine.assistant('创建失败：$e'));
      return;
    }

    if (!mounted) return;
    for (final draft in _drafts) {
      draft.dispose();
    }
    setState(() {
      _lastCreatedIds = created;
      _lastCreatedAreaIds = createdAreaIds;
      _lastCreatedCount = created.length;
      _drafts.clear();
      _creating = false;
    });
    _append(_ChatLine.result(created.length));
  }

  Future<void> _undoLastCreated() async {
    final ids = _lastCreatedIds;
    final areaIds = _lastCreatedAreaIds;
    if (ids.isEmpty && areaIds.isEmpty) return;
    final repo = ref.read(itemRepositoryProvider);
    for (final id in ids) {
      await repo.moveToTrash(id);
    }
    for (final id in areaIds) {
      await repo.deleteArea(id);
    }
    if (!mounted) return;
    setState(() {
      _lastCreatedIds = const [];
      _lastCreatedAreaIds = const [];
    });
    _append(_ChatLine.assistant('已撤销 $_lastCreatedCount 项。'));
  }

  Future<void> _editWhen(_DraftEdit draft) async {
    final choice = await WhenPickerSheet.showChoice(context);
    if (choice != null) setState(() => draft.when = choice);
  }

  Future<void> _editDeadline(_DraftEdit draft) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: draft.deadline ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => draft.deadline = picked);
  }

  Future<void> _editList(_DraftEdit draft) async {
    final target = await MoveTargetSheet.show(context);
    if (target != null) {
      setState(() {
        draft.list = target;
        draft.newAreaName = null;
        draft.newProjectName = null;
      });
    }
  }

  String _whenLabel(WhenChoice when) {
    switch (when.start) {
      case WhenStart.inbox:
        return '收件箱';
      case WhenStart.someday:
        return '将来';
      case WhenStart.anytime:
        if (when.startDate == null) return '随时';
        if (when.evening) return '今晚';
        final diff = DateFmt.daysFromToday(when.startDate!);
        if (diff == 0) return '今天';
        return DateFmt.groupLabel(when.startDate!);
    }
  }

  String _listLabel(_DraftEdit draft) {
    final target = draft.list;
    if (draft.newAreaName != null) return '+领域 ${draft.newAreaName}';
    if (draft.newProjectName != null) return '+项目 ${draft.newProjectName}';
    if (target == null) return widget.projectId == null ? '收件箱' : '当前项目';
    if (target.inbox) return '收件箱';
    return target.projectTitle ?? target.areaTitle ?? '收件箱';
  }

  @override
  Widget build(BuildContext context) {
    final aiEnabled = ref.watch(aiEnabledProvider);
    final media = MediaQuery.of(context);
    final desktop = media.size.width >= 900;
    final content = Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              math.max(12, media.viewInsets.bottom > 0 ? 8 : 16),
            ),
            children: [
              if (_lines.isEmpty && _drafts.isEmpty) _emptyState(aiEnabled),
              for (final line in _lines) _message(line),
              if (_thinking) const _TypingBubble(),
              if (_drafts.isNotEmpty) _draftSection(),
            ],
          ),
        ),
        if (_drafts.isNotEmpty) _commitBar(),
        _suggestionRow(),
        _composer(aiEnabled),
      ],
    );
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF111113)
          : const Color(0xFFF7F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          tooltip: '关闭',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: const Text(
          'AI 理清',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: '模型',
            icon: const Icon(Icons.tune_rounded, size: 21),
            onPressed: _openSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: desktop ? 980 : double.infinity,
            ),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _emptyState(bool aiEnabled) {
    return Padding(
      padding: const EdgeInsets.only(top: 54),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppTheme.primaryBlue,
              size: 28,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            aiEnabled ? '把事情说出来' : '先配置一个 AI 模型',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            aiEnabled ? '一句话、多行清单、模糊念头都可以。' : '配置后回到这里继续输入。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          if (!aiEnabled)
            FilledButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('去配置'),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _sampleChip('今天给王总发 AI 配置方案'),
                _sampleChip('买机票\n订酒店\n整理行李清单'),
                _sampleChip('想开始学日语'),
              ],
            ),
        ],
      ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.08),
    );
  }

  Widget _sampleChip(String text) {
    return ActionChip(
      label: Text(text.replaceAll('\n', ' / ')),
      onPressed: () => _sendPreset(text),
      backgroundColor: Theme.of(context).colorScheme.surface,
      side: BorderSide(color: AppTheme.dividerColor),
      labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
    );
  }

  Widget _message(_ChatLine line) {
    final isUser = line.role == _LineRole.user;
    if (line.role == _LineRole.result) return _resultCard(line.count ?? 0);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isUser
              ? AppTheme.primaryBlue
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomRight: Radius.circular(isUser ? 5 : 18),
            bottomLeft: Radius.circular(isUser ? 18 : 5),
          ),
          border: isUser ? null : Border.all(color: AppTheme.dividerColor),
          boxShadow: [
            if (!isUser)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              line.text,
              style: TextStyle(
                color: isUser ? Colors.white : AppTheme.textPrimary,
                fontSize: 14.5,
                height: 1.38,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (line.needsConfig) ...[
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: _openSettings,
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: const Text('去配置'),
              ),
            ],
          ],
        ),
      ).animate().fadeIn(duration: 180.ms).slideY(begin: 0.08),
    );
  }

  Widget _resultCard(int count) {
    final canUndo = _lastCreatedIds.isNotEmpty;
    return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF22A06B).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF22A06B).withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF22A06B)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '已创建 $count 项',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              TextButton(
                onPressed: canUndo ? _undoLastCreated : null,
                child: const Text('撤销'),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 180.ms)
        .scale(begin: const Offset(0.98, 0.98), end: const Offset(1, 1));
  }

  Widget _draftSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: AppTheme.primaryBlue,
                ),
                const SizedBox(width: 6),
                Text(
                  '待创建',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _drafts.length,
            proxyDecorator: (child, _, animation) {
              return ScaleTransition(
                scale: Tween<double>(begin: 1, end: 1.02).animate(animation),
                child: Material(color: Colors.transparent, child: child),
              );
            },
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                final item = _drafts.removeAt(oldIndex);
                _drafts.insert(newIndex, item);
              });
            },
            itemBuilder: (context, index) {
              final draft = _drafts[index];
              return _DraftCard(
                key: ValueKey(draft.id),
                draft: draft,
                index: index,
                whenLabel: _whenLabel(draft.when),
                listLabel: _listLabel(draft),
                onChanged: () => setState(() {}),
                onToggleInclude: () =>
                    setState(() => draft.include = !draft.include),
                onToggleType: () => setState(() {
                  draft.type = draft.type == ItemType.project
                      ? ItemType.task
                      : ItemType.project;
                }),
                onToggleExpanded: () =>
                    setState(() => draft.expanded = !draft.expanded),
                onEditWhen: () => _editWhen(draft),
                onEditDeadline: () => _editDeadline(draft),
                onEditList: () => _editList(draft),
                onRemove: () => setState(() {
                  draft.dispose();
                  _drafts.removeAt(index);
                }),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _commitBar() {
    final count = _createCount;
    final valid = count > 0 && _hasValidDraft && !_creating && !_thinking;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
        border: Border(top: BorderSide(color: AppTheme.dividerColor)),
      ),
      child: Row(
        children: [
          Text(
            count == 0 ? '暂无可创建项' : '$count 项待创建',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: valid ? _commitDrafts : null,
            icon: _creating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text('创建 $count 项'),
          ),
        ],
      ),
    );
  }

  Widget _suggestionRow() {
    if (_suggestions.isEmpty) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: Wrap(
        spacing: 8,
        children: [
          for (final text in _suggestions)
            ActionChip(
              label: Text(text),
              onPressed: () => _sendPreset(text),
              backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.09),
              side: BorderSide.none,
              labelStyle: const TextStyle(
                color: AppTheme.primaryBlue,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
        ],
      ),
    );
  }

  Widget _composer(bool aiEnabled) {
    final canSend = _input.text.trim().isNotEmpty && !_thinking && !_creating;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 15, height: 1.35),
                decoration: InputDecoration(
                  hintText: aiEnabled ? '继续补充、修改或直接说“创建”' : '配置模型后继续',
                  hintStyle: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.74),
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(16, 13, 8, 13),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 7),
              child: IconButton.filled(
                onPressed: canSend ? _send : null,
                icon: const Icon(Icons.arrow_upward_rounded, size: 19),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  disabledBackgroundColor: AppTheme.textSecondary.withValues(
                    alpha: 0.16,
                  ),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(38, 38),
                  fixedSize: const Size(38, 38),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _LineRole { user, assistant, result }

class _ChatLine {
  final _LineRole role;
  final String text;
  final bool needsConfig;
  final int? count;

  const _ChatLine._(
    this.role,
    this.text, {
    this.needsConfig = false,
    this.count,
  });

  factory _ChatLine.user(String text) => _ChatLine._(_LineRole.user, text);

  factory _ChatLine.assistant(String text, {bool needsConfig = false}) =>
      _ChatLine._(_LineRole.assistant, text, needsConfig: needsConfig);

  factory _ChatLine.result(int count) =>
      _ChatLine._(_LineRole.result, '', count: count);
}

class _DraftChildEdit {
  final TextEditingController title;
  bool include;
  WhenChoice when;
  DateTime? deadline;

  _DraftChildEdit(String title, {this.when = WhenChoice.inbox, this.deadline})
    : title = TextEditingController(text: title),
      include = true;

  void dispose() => title.dispose();
}

class _DraftEdit {
  final int id;
  final TextEditingController title;
  ItemType type;
  WhenChoice when;
  DateTime? deadline;
  MoveTarget? list;
  String? newAreaName;
  String? newProjectName;
  final Set<String> tagIds;
  final List<String> newTagNames;
  final List<_DraftChildEdit> children;
  bool include;
  bool expanded;

  _DraftEdit({
    required this.id,
    required String title,
    required this.type,
    required this.when,
    this.deadline,
    this.list,
    this.newAreaName,
    this.newProjectName,
    Set<String>? tagIds,
    List<String>? newTagNames,
    List<_DraftChildEdit>? children,
    bool? expanded,
  }) : title = TextEditingController(text: title),
       tagIds = tagIds ?? {},
       newTagNames = newTagNames ?? [],
       children = children ?? [],
       include = true,
       expanded = expanded ?? ((children?.isNotEmpty ?? false));

  void dispose() {
    title.dispose();
    for (final child in children) {
      child.dispose();
    }
  }
}

class _DraftCard extends StatelessWidget {
  final _DraftEdit draft;
  final int index;
  final String whenLabel;
  final String listLabel;
  final VoidCallback onChanged;
  final VoidCallback onToggleInclude;
  final VoidCallback onToggleType;
  final VoidCallback onToggleExpanded;
  final VoidCallback onEditWhen;
  final VoidCallback onEditDeadline;
  final VoidCallback onEditList;
  final VoidCallback onRemove;

  const _DraftCard({
    super.key,
    required this.draft,
    required this.index,
    required this.whenLabel,
    required this.listLabel,
    required this.onChanged,
    required this.onToggleInclude,
    required this.onToggleType,
    required this.onToggleExpanded,
    required this.onEditWhen,
    required this.onEditDeadline,
    required this.onEditList,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isProject = draft.type == ItemType.project;
    final accent = isProject ? const Color(0xFF6E63F6) : AppTheme.primaryBlue;
    final bg = isProject
        ? const Color(0xFF6E63F6).withValues(alpha: 0.075)
        : Theme.of(context).colorScheme.surface;
    return AnimatedOpacity(
      opacity: draft.include ? 1 : 0.48,
      duration: const Duration(milliseconds: 160),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: draft.title.text.trim().isEmpty
                ? AppTheme.deadlineRed.withValues(alpha: 0.55)
                : AppTheme.dividerColor,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.045),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: AppTheme.textSecondary.withValues(alpha: 0.75),
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onToggleInclude,
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.11),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        draft.include
                            ? (isProject
                                  ? Icons.folder_rounded
                                  : Icons.check_rounded)
                            : Icons.visibility_off_rounded,
                        color: accent,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: draft.title,
                      minLines: 1,
                      maxLines: 3,
                      onChanged: (_) => onChanged(),
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        decoration: draft.include
                            ? null
                            : TextDecoration.lineThrough,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.only(top: 6),
                        hintText: '标题',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '类型',
                    onPressed: onToggleType,
                    icon: Icon(
                      isProject
                          ? Icons.account_tree_rounded
                          : Icons.check_box_outline_blank_rounded,
                      color: accent,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    tooltip: '移除',
                    onPressed: onRemove,
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppTheme.textSecondary,
                      size: 19,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 54, top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _MiniChip(
                        icon: Icons.inbox_rounded,
                        label: listLabel,
                        color: AppTheme.primaryBlue,
                        onTap: onEditList,
                      ),
                      _MiniChip(
                        icon: Icons.calendar_today_rounded,
                        label: whenLabel,
                        color: AppTheme.todayYellow,
                        onTap: onEditWhen,
                      ),
                      _MiniChip(
                        icon: Icons.flag_rounded,
                        label: draft.deadline == null
                            ? '截止'
                            : DateFmt.deadlineLabel(draft.deadline!),
                        color: AppTheme.deadlineRed,
                        active: draft.deadline != null,
                        onTap: onEditDeadline,
                      ),
                      for (final name in draft.newTagNames)
                        _MiniChip(
                          icon: Icons.label_outline_rounded,
                          label: '#$name',
                          color: const Color(0xFF22A06B),
                        ),
                      if (draft.children.isNotEmpty)
                        _MiniChip(
                          icon: draft.expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          label: '${draft.children.length}',
                          color: accent,
                          onTap: onToggleExpanded,
                        ),
                    ],
                  ),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Padding(
                  padding: const EdgeInsets.only(left: 52, top: 10),
                  child: Column(
                    children: [
                      for (final child in draft.children)
                        _ChildRow(child: child, onChanged: onChanged),
                    ],
                  ),
                ),
                crossFadeState: draft.expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 180),
                sizeCurve: Curves.easeOutCubic,
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 180.ms).slideY(begin: 0.06);
  }
}

class _ChildRow extends StatelessWidget {
  final _DraftChildEdit child;
  final VoidCallback onChanged;

  const _ChildRow({required this.child, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: child.include,
          visualDensity: VisualDensity.compact,
          activeColor: AppTheme.primaryBlue,
          onChanged: (value) {
            child.include = value ?? true;
            onChanged();
          },
        ),
        Expanded(
          child: TextField(
            controller: child.title,
            enabled: child.include,
            onChanged: (_) => onChanged(),
            style: TextStyle(
              fontSize: 14,
              height: 1.25,
              decoration: child.include ? null : TextDecoration.lineThrough,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: '下一步',
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final VoidCallback? onTap;

  const _MiniChip({
    required this.icon,
    required this.label,
    required this.color,
    this.active = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = active ? color : AppTheme.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: active ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: c,
                fontSize: 11.8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(
                18,
              ).copyWith(bottomLeft: const Radius.circular(5)),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 9),
                Text(
                  '整理中',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        )
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .fade(duration: 800.ms, begin: 0.72, end: 1);
  }
}
