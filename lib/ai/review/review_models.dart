/// 回顾报告里每个区块的类型。
enum ReviewKind {
  inbox, // 待整理收件箱
  incubation, // 孵化区到期回顾（将来里放久的）
  projectNoNextAction, // 缺少下一步行动的项目
  stalledTask, // 随时区里被长期遗忘的散任务
}

extension ReviewKindMeta on ReviewKind {
  String get title {
    switch (this) {
      case ReviewKind.inbox:
        return '待整理收件箱';
      case ReviewKind.incubation:
        return '孵化区到期回顾';
      case ReviewKind.projectNoNextAction:
        return '项目健康';
      case ReviewKind.stalledTask:
        return '停滞任务';
    }
  }

  String get description {
    switch (this) {
      case ReviewKind.inbox:
        return '这些念头还没理清，先清空收件箱。';
      case ReviewKind.incubation:
        return '放进「将来」已超过两周，是激活还是继续孵化？';
      case ReviewKind.projectNoNextAction:
        return '这些项目没有「下一步行动」，正在停摆。';
      case ReviewKind.stalledTask:
        return '在「随时」里被遗忘很久，重新安排或放手。';
    }
  }
}

/// 报告里指向某个真实条目的引用（用于就地跳转/预览）。
class ReviewItemRef {
  final String id;
  final String title;

  /// 附加说明，如「14 天前创建」「0 个下一步」。
  final String? hint;
  const ReviewItemRef({required this.id, required this.title, this.hint});
}

/// 报告的一个区块。
class ReviewSection {
  final ReviewKind kind;
  final List<ReviewItemRef> items;
  const ReviewSection({required this.kind, required this.items});

  int get count => items.length;
  bool get isEmpty => items.isEmpty;
}

/// 一次回顾的完整快照。
class ReviewReport {
  final DateTime generatedAt;
  final List<ReviewSection> sections;

  /// AI 本周聚焦建议（未配置 Key 时为 null）。
  final String? aiAdvice;

  /// 当前是否具备 AI 能力（决定是否展示「配置可获建议」的提示）。
  final bool aiAvailable;

  const ReviewReport({
    required this.generatedAt,
    required this.sections,
    this.aiAdvice,
    this.aiAvailable = false,
  });

  /// 需要关注的条目总数。
  int get pendingTotal =>
      sections.fold(0, (sum, s) => sum + s.count);

  /// 全部就绪（没有任何待办区块）。
  bool get allClear => pendingTotal == 0;

  /// 仅含有内容的区块。
  List<ReviewSection> get nonEmptySections =>
      sections.where((s) => !s.isEmpty).toList();
}
