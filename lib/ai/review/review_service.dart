import '../../domain/models/item.dart';
import '../core/llm_client.dart';
import '../core/llm_message.dart';
import 'review_models.dart';

/// 「一键回顾」核心：本地扫描全部活跃条目，按 GTD 维度分类成回顾报告，
/// 并在配置了 AI 时附上一段「本周聚焦」建议。
///
/// 扫描完全离线、即时；AI 只负责锦上添花的文字建议，未配置也不影响报告生成。
class ReviewService {
  final LlmClient client;
  const ReviewService(this.client);

  /// 孵化/停滞的「放久了」阈值（天）。
  static const int staleDays = 14;

  /// 从一份活跃条目快照构建报告。[withAi] 控制是否请求 AI 建议。
  Future<ReviewReport> build(
    List<Item> active, {
    DateTime? now,
    bool withAi = true,
  }) async {
    final today = now ?? DateTime.now();
    final staleBefore = today.subtract(const Duration(days: staleDays));

    final tasks = active.where((i) => i.isTask).toList();
    final projects = active.where((i) => i.isProject).toList();

    // 1. 待整理收件箱
    final inbox = tasks
        .where((t) => t.start == WhenStart.inbox)
        .map((t) => ReviewItemRef(id: t.id, title: t.title))
        .toList();

    // 2. 孵化区到期回顾（将来里创建超过阈值）
    final incubation = active
        .where((i) =>
            i.start == WhenStart.someday && i.createdAt.isBefore(staleBefore))
        .map((i) => ReviewItemRef(
              id: i.id,
              title: i.title,
              hint: '${_daysAgo(i.createdAt, today)} 天前放入',
            ))
        .toList();

    // 3. 项目健康：活跃项目其下 0 条活跃任务（缺下一步行动）
    final openTaskCountByProject = <String, int>{};
    for (final t in tasks) {
      final pid = t.projectId;
      if (pid != null) {
        openTaskCountByProject[pid] = (openTaskCountByProject[pid] ?? 0) + 1;
      }
    }
    final projectNoNext = projects
        .where((p) => (openTaskCountByProject[p.id] ?? 0) == 0)
        .map((p) => ReviewItemRef(id: p.id, title: p.title, hint: '0 个下一步行动'))
        .toList();

    // 4. 停滞任务：随时区、无日期、不属于任何项目/领域、创建超过阈值
    final stalled = tasks
        .where((t) =>
            t.start == WhenStart.anytime &&
            t.startDate == null &&
            t.projectId == null &&
            t.areaId == null &&
            t.createdAt.isBefore(staleBefore))
        .map((t) => ReviewItemRef(
              id: t.id,
              title: t.title,
              hint: '${_daysAgo(t.createdAt, today)} 天未动',
            ))
        .toList();

    final sections = [
      ReviewSection(kind: ReviewKind.inbox, items: inbox),
      ReviewSection(kind: ReviewKind.incubation, items: incubation),
      ReviewSection(
          kind: ReviewKind.projectNoNextAction, items: projectNoNext),
      ReviewSection(kind: ReviewKind.stalledTask, items: stalled),
    ];

    String? advice;
    final aiAvailable = client.isConfigured;
    final pending = sections.fold(0, (s, x) => s + x.count);
    if (withAi && aiAvailable && pending > 0) {
      advice = await _advise(sections, today);
    }

    return ReviewReport(
      generatedAt: today,
      sections: sections,
      aiAdvice: advice,
      aiAvailable: aiAvailable,
    );
  }

  Future<String?> _advise(List<ReviewSection> sections, DateTime now) async {
    final sb = StringBuffer()
      ..writeln('这是用户的 GTD 系统当前快照，请给出本周聚焦建议：');
    for (final s in sections) {
      if (s.isEmpty) continue;
      final samples = s.items.take(4).map((e) => e.title).join('、');
      sb.writeln('- ${s.kind.title}：${s.count} 条（例：$samples）');
    }

    try {
      final reply = await client.complete(
        [
          LlmMessage.system(
            '你是一个 GTD 教练。基于用户系统快照，用中文给出 2~3 句、温和而具体的本周聚焦建议。'
            '优先顺序：先清空收件箱 → 再给停摆项目补下一步 → 最后处理孵化区。'
            '只输出建议正文，不要标题、不要列表符号、不要 JSON。',
          ),
          LlmMessage.user(sb.toString()),
        ],
        temperature: 0.5,
      );
      return reply.trim();
    } catch (_) {
      // AI 建议是锦上添花，失败时静默降级，不影响报告本体。
      return null;
    }
  }

  int _daysAgo(DateTime from, DateTime now) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(now.year, now.month, now.day);
    return b.difference(a).inDays;
  }
}
