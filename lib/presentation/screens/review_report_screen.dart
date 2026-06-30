import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_providers.dart';
import '../../ai/review/review_models.dart';
import '../../domain/models/item.dart';
import '../app_view.dart';
import '../providers/item_providers.dart';
import '../shared/theme/app_theme.dart';
import 'batch_clarify_screen.dart';
import 'project_screen.dart';
import 'view_screen.dart';

/// 一键回顾报告：本地扫描全库，按 GTD 维度生成只读快照，附 AI 本周聚焦建议。
class ReviewReportScreen extends ConsumerStatefulWidget {
  const ReviewReportScreen({super.key});

  @override
  ConsumerState<ReviewReportScreen> createState() => _ReviewReportScreenState();
}

class _ReviewReportScreenState extends ConsumerState<ReviewReportScreen> {
  bool _loading = true;
  ReviewReport? _report;
  List<Item> _active = const [];

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    final repo = ref.read(itemRepositoryProvider);
    final service = ref.read(reviewServiceProvider);
    final active = await repo.activeSnapshot();
    final report = await service.build(active);
    if (!mounted) return;
    setState(() {
      _active = active;
      _report = report;
      _loading = false;
    });
  }

  Color _kindColor(ReviewKind k) {
    switch (k) {
      case ReviewKind.inbox:
        return AppView.inbox.color;
      case ReviewKind.incubation:
        return AppView.someday.color;
      case ReviewKind.projectNoNextAction:
        return AppTheme.primaryBlue;
      case ReviewKind.stalledTask:
        return AppView.anytime.color;
    }
  }

  IconData _kindIcon(ReviewKind k) {
    switch (k) {
      case ReviewKind.inbox:
        return Icons.inbox_rounded;
      case ReviewKind.incubation:
        return Icons.archive_rounded;
      case ReviewKind.projectNoNextAction:
        return Icons.folder_rounded;
      case ReviewKind.stalledTask:
        return Icons.hourglass_bottom_rounded;
    }
  }

  void _openView(AppView view) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ViewScreen(view: view, showBack: true),
    ));
  }

  void _openProject(String id, String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProjectScreen(projectId: id, projectTitle: title),
    ));
  }

  Future<void> _batchClarify() async {
    final inbox =
        _active.where((i) => i.isTask && i.start == WhenStart.inbox).toList();
    if (inbox.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BatchClarifyScreen(items: inbox),
    ));
    _generate(); // 回来后刷新报告
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('回顾'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '重新生成',
            onPressed: _loading ? null : _generate,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryBlue))
            : _content(),
      ),
    );
  }

  Widget _content() {
    final report = _report!;
    final sections = report.nonEmptySections;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _summaryHeader(report),
        if (report.aiAdvice != null) _adviceCard(report.aiAdvice!),
        if (!report.aiAvailable) _aiHintCard(),
        if (report.allClear)
          _allClearCard()
        else
          for (final s in sections) _sectionCard(s),
      ],
    );
  }

  Widget _summaryHeader(ReviewReport report) {
    final t = report.generatedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.allClear ? '一切就绪' : '有 ${report.pendingTotal} 项待关注',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text('生成于 $time',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _adviceCard(String advice) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryBlue.withValues(alpha: 0.12),
            AppTheme.primaryBlue.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.auto_awesome_rounded,
                  size: 16, color: AppTheme.primaryBlue),
              SizedBox(width: 6),
              Text('本周聚焦',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: AppTheme.primaryBlue)),
            ],
          ),
          const SizedBox(height: 8),
          Text(advice,
              style: const TextStyle(fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }

  Widget _aiHintCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded,
              size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text('配置 AI 模型后，回顾可获得每周聚焦建议',
                style: TextStyle(
                    fontSize: 12.5, color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _allClearCard() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          const Icon(Icons.spa_rounded, size: 60, color: Color(0xFF53B25B)),
          const SizedBox(height: 16),
          const Text('系统很干净',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('收件箱清空、项目都有下一步，享受你的专注。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _sectionCard(ReviewSection s) {
    final color = _kindColor(s.kind);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_kindIcon(s.kind), color: Colors.white, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.kind.title,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(s.kind.description,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${s.count}',
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              ],
            ),
          ),
          for (final ref in s.items.take(4)) _itemPreview(ref),
          if (s.count > 4)
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 2, 16, 4),
              child: Text('…还有 ${s.count - 4} 条',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ),
          const Divider(height: 1),
          _sectionAction(s),
        ],
      ),
    );
  }

  Widget _itemPreview(ReviewItemRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 3, 16, 3),
      child: Row(
        children: [
          Expanded(
            child: Text('· ${ref.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5)),
          ),
          if (ref.hint != null)
            Text(ref.hint!,
                style: TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _sectionAction(ReviewSection s) {
    String label;
    VoidCallback onTap;
    switch (s.kind) {
      case ReviewKind.inbox:
        label = '批量理清';
        onTap = _batchClarify;
        break;
      case ReviewKind.incubation:
        label = '去「将来」';
        onTap = () => _openView(AppView.someday);
        break;
      case ReviewKind.projectNoNextAction:
        label = s.items.length == 1 ? '去该项目补行动' : '逐个补行动';
        onTap = () {
          final first = s.items.first;
          _openProject(first.id, first.title);
        };
        break;
      case ReviewKind.stalledTask:
        label = '去「随时」';
        onTap = () => _openView(AppView.anytime);
        break;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5)),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 13, color: AppTheme.primaryBlue),
          ],
        ),
      ),
    );
  }
}
