/// 条目类型：任务 / 项目 / 标题。
enum ItemType { task, project, heading }

/// 生命周期状态（轴 A）。
enum ItemStatus { open, completed, canceled }

/// 调度意图（轴 B），只持久化这 3 态。
/// Today / Upcoming / Anytime 由 start + startDate 派生，不入库。
enum WhenStart { inbox, anytime, someday }

/// 重复规则。none 表示不重复。
/// weekday=每个工作日(周一~周五)；monthlyLast=每月最后一天；
/// monthlyNthWeekday=每月的第 n 个周几（n 与周几从基准日期推断）。
enum RepeatRule {
  none,
  daily,
  weekday,
  weekly,
  monthly,
  monthlyLast,
  monthlyNthWeekday,
  yearly,
}

extension RepeatRuleX on RepeatRule {
  String get label {
    switch (this) {
      case RepeatRule.none:
        return '不重复';
      case RepeatRule.daily:
        return '每天';
      case RepeatRule.weekday:
        return '每个工作日';
      case RepeatRule.weekly:
        return '每周';
      case RepeatRule.monthly:
        return '每月';
      case RepeatRule.monthlyLast:
        return '每月最后一天';
      case RepeatRule.monthlyNthWeekday:
        return '每月第 N 个周几';
      case RepeatRule.yearly:
        return '每年';
    }
  }

  /// 在 [from] 基础上推进 [interval] 个周期，得到下一次发生日期。
  DateTime? next(DateTime from, int interval) {
    final n = interval < 1 ? 1 : interval;
    switch (this) {
      case RepeatRule.none:
        return null;
      case RepeatRule.daily:
        return from.add(Duration(days: n));
      case RepeatRule.weekday:
        var d = from.add(const Duration(days: 1));
        while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
          d = d.add(const Duration(days: 1));
        }
        return d;
      case RepeatRule.weekly:
        return from.add(Duration(days: 7 * n));
      case RepeatRule.monthly:
        return DateTime(from.year, from.month + n, from.day);
      case RepeatRule.monthlyLast:
        // 下个月（+n）的最后一天。
        return DateTime(from.year, from.month + n + 1, 0);
      case RepeatRule.monthlyNthWeekday:
        // 取 from 在其所属月里是第几个该周几，然后在下个月找同样的位置。
        final week = ((from.day - 1) ~/ 7) + 1;
        final weekday = from.weekday;
        return _nthWeekdayOfMonth(from.year, from.month + n, weekday, week);
      case RepeatRule.yearly:
        return DateTime(from.year + n, from.month, from.day);
    }
  }

  /// 某月里第 [week] 个 [weekday]；若该月不足，回退为最后一个该周几。
  static DateTime _nthWeekdayOfMonth(int year, int month, int weekday, int week) {
    final first = DateTime(year, month, 1);
    int offset = (weekday - first.weekday) % 7;
    if (offset < 0) offset += 7;
    var day = 1 + offset + (week - 1) * 7;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    while (day > daysInMonth) {
      day -= 7;
    }
    return DateTime(year, month, day);
  }
}

T _enumFromName<T>(List<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  for (final v in values) {
    if ((v as Enum).name == name) return v;
  }
  return fallback;
}

DateTime? _parseDate(Object? raw) {
  if (raw == null) return null;
  final s = raw as String;
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

class Item {
  final String id;
  final String userId;
  final ItemType type;
  final String title;

  // 轴 A：生命周期
  final ItemStatus status;
  final DateTime? completedAt;
  final bool trashed;

  // 轴 B：调度意图
  final WhenStart start;
  final DateTime? startDate; // 仅日期粒度
  final bool evening;

  // 轴 C：死线
  final DateTime? deadline; // 仅日期粒度

  // 重复 & 提醒
  final RepeatRule repeat;
  final int repeatInterval;
  final String? reminderTime; // 'HH:mm'

  // 标题归档
  final bool archived;

  // 层级归属
  final String? areaId;
  final String? projectId;
  final String? headingId;

  final int sortOrder;
  final int todaySortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Item({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    this.status = ItemStatus.open,
    this.completedAt,
    this.trashed = false,
    this.start = WhenStart.inbox,
    this.startDate,
    this.evening = false,
    this.deadline,
    this.repeat = RepeatRule.none,
    this.repeatInterval = 1,
    this.reminderTime,
    this.archived = false,
    this.areaId,
    this.projectId,
    this.headingId,
    this.sortOrder = 0,
    this.todaySortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isTask => type == ItemType.task;
  bool get isProject => type == ItemType.project;
  bool get isHeading => type == ItemType.heading;
  bool get isCompleted => status == ItemStatus.completed;
  bool get isCanceled => status == ItemStatus.canceled;
  bool get isDone => isCompleted || isCanceled;
  bool get isRepeating => repeat != RepeatRule.none;

  factory Item.fromRow(Map<String, dynamic> row) {
    return Item(
      id: row['id'] as String,
      userId: row['user_id'] as String? ?? '',
      type: _enumFromName(ItemType.values, row['type'] as String?, ItemType.task),
      title: row['title'] as String? ?? '',
      status: _enumFromName(ItemStatus.values, row['status'] as String?, ItemStatus.open),
      completedAt: _parseDate(row['completed_at']),
      trashed: (row['trashed'] as int? ?? 0) == 1,
      start: _enumFromName(WhenStart.values, row['start'] as String?, WhenStart.inbox),
      startDate: _parseDate(row['start_date']),
      evening: (row['evening'] as int? ?? 0) == 1,
      deadline: _parseDate(row['deadline']),
      repeat: _enumFromName(RepeatRule.values, row['repeat'] as String?, RepeatRule.none),
      repeatInterval: (row['repeat_interval'] as int?) ?? 1,
      reminderTime: row['reminder_time'] as String?,
      archived: (row['archived'] as int? ?? 0) == 1,
      areaId: row['area_id'] as String?,
      projectId: row['project_id'] as String?,
      headingId: row['heading_id'] as String?,
      sortOrder: (row['sort_order'] as int?) ?? 0,
      todaySortOrder: (row['today_sort_order'] as int?) ?? 0,
      createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(row['updated_at']) ?? DateTime.now(),
    );
  }
}

class Area {
  final String id;
  final String userId;
  final String title;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Area({
    required this.id,
    required this.userId,
    required this.title,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Area.fromRow(Map<String, dynamic> row) {
    return Area(
      id: row['id'] as String,
      userId: row['user_id'] as String? ?? '',
      title: row['title'] as String? ?? '',
      sortOrder: (row['sort_order'] as int?) ?? 0,
      createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(row['updated_at']) ?? DateTime.now(),
    );
  }
}

/// 检查项：挂在单个 task 之下的轻量子清单。
class ChecklistItem {
  final String id;
  final String itemId;
  final String title;
  final bool isCompleted;
  final int sortOrder;

  const ChecklistItem({
    required this.id,
    required this.itemId,
    required this.title,
    this.isCompleted = false,
    this.sortOrder = 0,
  });

  factory ChecklistItem.fromRow(Map<String, dynamic> row) {
    return ChecklistItem(
      id: row['id'] as String,
      itemId: row['item_id'] as String? ?? '',
      title: row['title'] as String? ?? '',
      isCompleted: (row['is_completed'] as int? ?? 0) == 1,
      sortOrder: (row['sort_order'] as int?) ?? 0,
    );
  }
}

/// 标签：支持层级（parentTagId）。
class Tag {
  final String id;
  final String title;
  final String? parentTagId;
  final int sortOrder;

  const Tag({
    required this.id,
    required this.title,
    this.parentTagId,
    this.sortOrder = 0,
  });

  factory Tag.fromRow(Map<String, dynamic> row) {
    return Tag(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      parentTagId: row['parent_tag_id'] as String?,
      sortOrder: (row['sort_order'] as int?) ?? 0,
    );
  }
}

/// 计划视图里的一次「占格」：同一条目可能既被安排在某天(isDeadline=false)，
/// 又在另一天有死线(isDeadline=true)，因此用独立 entry 承载日期与含义。
class ScheduleEntry {
  final Item item;
  final DateTime date;
  final bool isDeadline;

  /// 重复任务在未来日期上的半透明「影子」预视，不是真实条目。
  final bool isShadow;
  const ScheduleEntry(this.item, this.date,
      {this.isDeadline = false, this.isShadow = false});
}

/// 项目进度（用于进度圆环）。
class ProjectProgress {
  final int total;
  final int done;
  const ProjectProgress(this.total, this.done);

  double get fraction => total == 0 ? 0 : done / total;
  bool get isComplete => total > 0 && done >= total;
}
