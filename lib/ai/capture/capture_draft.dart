import '../../domain/models/item.dart';

/// AI 拆解产出的「何时」草稿。刻意与 UI 的 WhenChoice 解耦，
/// 保持 ai 层不依赖 presentation 层（依赖方向单向：presentation -> ai）。
enum DraftWhenKind { none, today, evening, someday, date }

class DraftWhen {
  final DraftWhenKind kind;
  final DateTime? date; // 仅 kind == date 时有效

  const DraftWhen(this.kind, {this.date});
  static const none = DraftWhen(DraftWhenKind.none);

  bool get isSet => kind != DraftWhenKind.none;
}

/// 一个被拆出来的子条目：
///   - 当父级是项目(project) 时，它是一条任务(task)；
///   - 当父级是任务(task) 时，它是一条检查项(checklist)，此时只用到 [title]。
class DraftChild {
  String title;
  DraftWhen when;
  DateTime? deadline;

  /// 用户是否勾选保留（默认全选）。
  bool include;

  DraftChild({
    required this.title,
    this.when = DraftWhen.none,
    this.deadline,
    this.include = true,
  });
}

/// 顶层草稿条目（通常一句话拆出一个）。
class DraftItem {
  String title;
  ItemType type; // task | project
  DraftWhen when;
  DateTime? deadline;

  /// AI 建议的标签名（评审/落库时再解析成已有标签或新建）。
  List<String> tagNames;

  /// AI 建议放入的清单名：null=沿用语境，'__inbox__'=收件箱，否则是项目/领域名。
  String? listName;

  /// 子条目（项目→任务 / 任务→检查项）。
  List<DraftChild> children;

  DraftItem({
    required this.title,
    this.type = ItemType.task,
    this.when = DraftWhen.none,
    this.deadline,
    List<String>? tagNames,
    this.listName,
    List<DraftChild>? children,
  })  : tagNames = tagNames ?? [],
        children = children ?? [];

  static const inboxToken = '__inbox__';
}

/// 一次拆解的完整结果。
class CaptureDraft {
  /// 用户原始输入，便于「退回纯文本重编辑」。
  final String source;

  final List<DraftItem> items;

  const CaptureDraft({required this.source, required this.items});

  bool get isEmpty => items.isEmpty;

  /// 是否「拆出了更多结构」——决定要不要进入草稿评审，
  /// 否则直接降级为单条普通保存。
  bool get hasStructure {
    if (items.length > 1) return true;
    if (items.isEmpty) return false;
    final only = items.first;
    return only.type == ItemType.project ||
        only.children.isNotEmpty ||
        only.when.isSet ||
        only.deadline != null ||
        only.tagNames.isNotEmpty ||
        only.listName != null;
  }
}
