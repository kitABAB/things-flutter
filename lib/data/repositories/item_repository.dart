import 'package:uuid/uuid.dart';
import '../../domain/models/item.dart';
import '../database/powersync_db.dart';
import '../services/notification_service.dart';

/// 把 DateTime 规整为仅日期的字符串（YYYY-MM-DD），
/// 以便与 SQLite 的 date('now','localtime') 做无歧义的字符串比较。
String? _dateOnly(DateTime? d) {
  if (d == null) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

class ItemRepository {
  final _uuid = const Uuid();

  /// 尚未接入 Auth，先用固定用户。
  static const String currentUserId = '00000000-0000-0000-0000-000000000001';

  // ----------------------------------------------------------------
  // 写操作
  // ----------------------------------------------------------------

  /// 创建一个任务。start / startDate / evening 共同决定它落在哪个时间视图。
  Future<String> createTask({
    required String title,
    WhenStart start = WhenStart.inbox,
    DateTime? startDate,
    bool evening = false,
    DateTime? deadline,
    RepeatRule repeat = RepeatRule.none,
    int repeatInterval = 1,
    String? reminderTime,
    String? areaId,
    String? projectId,
    String? headingId,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final order = now.millisecondsSinceEpoch;

    await db.execute('''
      INSERT INTO items
        (id, user_id, type, title, status, completed_at, trashed,
         start, start_date, evening, deadline,
         repeat, repeat_interval, reminder_time, archived,
         area_id, project_id, heading_id, sort_order, today_sort_order,
         created_at, updated_at)
      VALUES (?, ?, 'task', ?, 'open', NULL, 0,
              ?, ?, ?, ?,
              ?, ?, ?, 0,
              ?, ?, ?, ?, ?,
              ?, ?)
    ''', [
      id, currentUserId, title,
      start.name, _dateOnly(startDate), evening ? 1 : 0, _dateOnly(deadline),
      repeat.name, repeatInterval, reminderTime,
      areaId, projectId, headingId, order, order,
      nowIso, nowIso,
    ]);
    await _reschedule(id);
    return id;
  }

  Future<String> createProject({
    required String title,
    String? areaId,
    WhenStart start = WhenStart.anytime,
  }) async {
    final id = _uuid.v4();
    final nowIso = DateTime.now().toIso8601String();
    final order = DateTime.now().millisecondsSinceEpoch;
    await db.execute('''
      INSERT INTO items
        (id, user_id, type, title, status, trashed, start, evening,
         area_id, sort_order, today_sort_order, created_at, updated_at)
      VALUES (?, ?, 'project', ?, 'open', 0, ?, 0, ?, ?, ?, ?, ?)
    ''', [id, currentUserId, title, start.name, areaId, order, order, nowIso, nowIso]);
    return id;
  }

  Future<String> createHeading({required String title, required String projectId}) async {
    final id = _uuid.v4();
    final nowIso = DateTime.now().toIso8601String();
    final order = DateTime.now().millisecondsSinceEpoch;
    await db.execute('''
      INSERT INTO items
        (id, user_id, type, title, status, trashed, start, evening,
         project_id, sort_order, today_sort_order, created_at, updated_at)
      VALUES (?, ?, 'heading', ?, 'open', 0, 'anytime', 0, ?, ?, ?, ?, ?)
    ''', [id, currentUserId, title, projectId, order, order, nowIso, nowIso]);
    return id;
  }

  Future<String> createArea({required String title}) async {
    final id = _uuid.v4();
    final nowIso = DateTime.now().toIso8601String();
    final order = DateTime.now().millisecondsSinceEpoch;
    await db.execute('''
      INSERT INTO areas (id, user_id, title, sort_order, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
    ''', [id, currentUserId, title, order, nowIso, nowIso]);
    return id;
  }

  /// 编辑标题。
  Future<void> updateContent(String id, {required String title}) async {
    await db.execute('''
      UPDATE items SET title = ?, updated_at = ? WHERE id = ?
    ''', [title, DateTime.now().toIso8601String(), id]);
  }

  /// 变更条目类型（AI 理清把一条任务转成项目时使用）。
  Future<void> setType(String id, ItemType type) async {
    await db.execute('''
      UPDATE items SET type = ?, updated_at = ? WHERE id = ?
    ''', [type.name, DateTime.now().toIso8601String(), id]);
  }

  /// 设置调度意图（When）。这是「计划 / 今天 / 今晚 / 随时 / 将来」改期的统一入口。
  Future<void> setWhen(
    String id, {
    required WhenStart start,
    DateTime? startDate,
    bool evening = false,
  }) async {
    await db.execute('''
      UPDATE items
      SET start = ?, start_date = ?, evening = ?, updated_at = ?
      WHERE id = ?
    ''', [start.name, _dateOnly(startDate), evening ? 1 : 0, DateTime.now().toIso8601String(), id]);
    await _reschedule(id);
  }

  /// 仅切换「今晚」标记（不动 start / start_date）。
  /// 供「今天」视图里把任务在「白天 ⇄ 今晚」两段之间拖拽时使用。
  Future<void> setEvening(String id, bool evening) async {
    await db.execute('''
      UPDATE items SET evening = ?, updated_at = ? WHERE id = ?
    ''', [evening ? 1 : 0, DateTime.now().toIso8601String(), id]);
  }

  Future<void> setDeadline(String id, DateTime? deadline) async {
    await db.execute('''
      UPDATE items SET deadline = ?, updated_at = ? WHERE id = ?
    ''', [_dateOnly(deadline), DateTime.now().toIso8601String(), id]);
  }

  /// 设置重复规则。
  Future<void> setRepeat(String id, RepeatRule rule, {int interval = 1}) async {
    await db.execute('''
      UPDATE items SET repeat = ?, repeat_interval = ?, updated_at = ? WHERE id = ?
    ''', [rule.name, interval, DateTime.now().toIso8601String(), id]);
  }

  /// 设置 / 清除闹钟提醒（'HH:mm'，传 null 清除）。
  Future<void> setReminder(String id, String? hhmm) async {
    await db.execute('''
      UPDATE items SET reminder_time = ?, updated_at = ? WHERE id = ?
    ''', [hhmm, DateTime.now().toIso8601String(), id]);
    await _reschedule(id);
  }

  /// 勾选 / 取消勾选。完成时记录 completed_at 以供日志排序。
  /// 若任务设了重复规则，完成时自动生成下一次的实例。
  Future<void> setStatus(String id, ItemStatus status) async {
    final now = DateTime.now().toIso8601String();
    final completedAt = status == ItemStatus.open ? null : now;

    if (status != ItemStatus.open) {
      final rows = await db.getAll('SELECT * FROM items WHERE id = ?', [id]);
      if (rows.isNotEmpty) {
        final it = Item.fromRow(rows.first as Map<String, dynamic>);
        if (it.isRepeating && status == ItemStatus.completed) {
          await _spawnNextOccurrence(it);
        }
      }
      await NotificationService.instance.cancel(id);
    }

    await db.execute('''
      UPDATE items SET status = ?, completed_at = ?, updated_at = ? WHERE id = ?
    ''', [status.name, completedAt, now, id]);

    if (status == ItemStatus.open) await _reschedule(id);
  }

  Future<void> toggleComplete(String id, bool complete) {
    return setStatus(id, complete ? ItemStatus.completed : ItemStatus.open);
  }

  /// 重复任务完成后，克隆一个新的 open 实例并推进到下一发生日期。
  Future<void> _spawnNextOccurrence(Item it) async {
    final base = it.startDate ?? DateTime.now();
    final next = it.repeat.next(base, it.repeatInterval);
    if (next == null) return;

    final newId = await createTask(
      title: it.title,
      start: WhenStart.anytime,
      startDate: next,
      evening: it.evening,
      deadline: it.deadline == null
          ? null
          : it.repeat.next(it.deadline!, it.repeatInterval),
      repeat: it.repeat,
      repeatInterval: it.repeatInterval,
      reminderTime: it.reminderTime,
      areaId: it.areaId,
      projectId: it.projectId,
      headingId: it.headingId,
    );

    // 复制标签
    final tagRows =
        await db.getAll('SELECT tag_id FROM item_tags WHERE item_id = ?', [it.id]);
    for (final r in tagRows) {
      await attachTag(newId, r['tag_id'] as String);
    }
    // 复制检查项（重置为未完成）
    final clRows = await db.getAll(
        'SELECT title FROM checklist_items WHERE item_id = ? ORDER BY sort_order ASC',
        [it.id]);
    for (final r in clRows) {
      await addChecklistItem(newId, r['title'] as String);
    }
  }

  /// 依据 start_date + reminder_time 重新调度（或取消）提醒。
  Future<void> _reschedule(String id) async {
    final rows = await db.getAll('SELECT * FROM items WHERE id = ?', [id]);
    if (rows.isEmpty) return;
    final it = Item.fromRow(rows.first as Map<String, dynamic>);
    final t = it.reminderTime;
    if (it.isDone || it.trashed || it.startDate == null || t == null || t.isEmpty) {
      await NotificationService.instance.cancel(id);
      return;
    }
    final parts = t.split(':');
    final h = int.tryParse(parts.first) ?? 9;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final when = DateTime(
        it.startDate!.year, it.startDate!.month, it.startDate!.day, h, m);
    await NotificationService.instance
        .schedule(itemId: id, title: it.title, when: when);
  }

  /// 移入垃圾站（软删除）。
  Future<void> moveToTrash(String id) async {
    await db.execute('''
      UPDATE items SET trashed = 1, updated_at = ? WHERE id = ?
    ''', [DateTime.now().toIso8601String(), id]);
  }

  Future<void> restore(String id) async {
    await db.execute('''
      UPDATE items SET trashed = 0, updated_at = ? WHERE id = ?
    ''', [DateTime.now().toIso8601String(), id]);
  }

  /// 移动任务的归属。
  /// - toInbox：回到收件箱（清空领域/项目，start 置 inbox）
  /// - 指定 project / area：归入对应容器；若原本在收件箱则提升为 anytime。
  Future<void> assignParent(
    String id, {
    String? areaId,
    String? projectId,
    bool toInbox = false,
    required WhenStart currentStart,
  }) async {
    final WhenStart start = toInbox
        ? WhenStart.inbox
        : (currentStart == WhenStart.inbox ? WhenStart.anytime : currentStart);
    await db.execute('''
      UPDATE items
      SET area_id = ?, project_id = ?, heading_id = NULL, start = ?, updated_at = ?
      WHERE id = ?
    ''', [areaId, projectId, start.name, DateTime.now().toIso8601String(), id]);
  }

  // ---------------- 检查项 ----------------

  Future<void> addChecklistItem(String taskId, String title) async {
    final id = _uuid.v4();
    final nowIso = DateTime.now().toIso8601String();
    final order = DateTime.now().millisecondsSinceEpoch;
    await db.execute('''
      INSERT INTO checklist_items
        (id, item_id, title, is_completed, sort_order, created_at, updated_at)
      VALUES (?, ?, ?, 0, ?, ?, ?)
    ''', [id, taskId, title, order, nowIso, nowIso]);
  }

  Future<void> toggleChecklistItem(String id, bool done) async {
    await db.execute('''
      UPDATE checklist_items SET is_completed = ?, updated_at = ? WHERE id = ?
    ''', [done ? 1 : 0, DateTime.now().toIso8601String(), id]);
  }

  Future<void> renameChecklistItem(String id, String title) async {
    await db.execute('''
      UPDATE checklist_items SET title = ?, updated_at = ? WHERE id = ?
    ''', [title, DateTime.now().toIso8601String(), id]);
  }

  Future<void> deleteChecklistItem(String id) async {
    await _enqueueTombstone('checklist_items', id);
    await db.execute('DELETE FROM checklist_items WHERE id = ?', [id]);
  }

  Stream<List<ChecklistItem>> watchChecklist(String taskId) {
    return db.watch('''
      SELECT * FROM checklist_items WHERE item_id = ? ORDER BY sort_order ASC
    ''', parameters: [taskId]).map(
      (rows) => rows
          .map((r) => ChecklistItem.fromRow(r as Map<String, dynamic>))
          .toList(),
    );
  }

  // ---------------- 标签 ----------------

  Future<String> createTag(String title, {String? parentTagId}) async {
    final id = _uuid.v4();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final order = DateTime.now().millisecondsSinceEpoch;
    await db.execute('''
      INSERT INTO tags (id, user_id, title, parent_tag_id, sort_order, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
    ''', [id, currentUserId, title, parentTagId, order, nowIso]);
    return id;
  }

  Future<void> attachTag(String itemId, String tagId) async {
    await db.execute('''
      INSERT INTO item_tags (id, user_id, item_id, tag_id, updated_at)
      VALUES (?, ?, ?, ?, ?)
    ''', [
      _uuid.v4(),
      currentUserId,
      itemId,
      tagId,
      DateTime.now().toUtc().toIso8601String()
    ]);
  }

  Future<void> detachTag(String itemId, String tagId) async {
    final rows = await db.getAll(
        'SELECT id FROM item_tags WHERE item_id = ? AND tag_id = ?',
        [itemId, tagId]);
    for (final r in rows) {
      await _enqueueTombstone('item_tags', r['id'] as String);
    }
    await db.execute(
        'DELETE FROM item_tags WHERE item_id = ? AND tag_id = ?', [itemId, tagId]);
  }

  Stream<List<Tag>> watchTags() {
    return db.watch('SELECT * FROM tags ORDER BY sort_order ASC').map(
        (rows) => rows.map((r) => Tag.fromRow(r as Map<String, dynamic>)).toList());
  }

  /// 全部「条目 -> 标签集合」映射，供各视图顶部的标签过滤器使用。
  Stream<Map<String, Set<String>>> watchItemTagLinks() {
    return db.watch('SELECT item_id, tag_id FROM item_tags').map((rows) {
      final map = <String, Set<String>>{};
      for (final r in rows) {
        final itemId = r['item_id'] as String;
        final tagId = r['tag_id'] as String;
        map.putIfAbsent(itemId, () => <String>{}).add(tagId);
      }
      return map;
    });
  }

  Stream<List<Tag>> watchItemTags(String itemId) {
    return db.watch('''
      SELECT t.* FROM tags t
      JOIN item_tags it ON it.tag_id = t.id
      WHERE it.item_id = ?
      ORDER BY t.sort_order ASC
    ''', parameters: [itemId]).map(
        (rows) => rows.map((r) => Tag.fromRow(r as Map<String, dynamic>)).toList());
  }

  /// 继承得来的标签（来自所属项目 / 区域，不含自身直接打的标签）。
  Stream<List<Tag>> watchInheritedTags(String itemId) {
    return db.watch('''
      SELECT DISTINCT t.* FROM tags t
      JOIN item_tags it ON it.tag_id = t.id
      JOIN items self ON self.id = ?
      WHERE (it.item_id = self.project_id OR it.item_id = self.area_id)
        AND t.id NOT IN (SELECT tag_id FROM item_tags WHERE item_id = ?)
      ORDER BY t.sort_order ASC
    ''', parameters: [itemId, itemId]).map(
        (rows) => rows.map((r) => Tag.fromRow(r as Map<String, dynamic>)).toList());
  }

  /// 「条目 -> 有效标签集合」映射，含从项目/区域继承的标签。供视图过滤器使用。
  Stream<Map<String, Set<String>>> watchEffectiveItemTagLinks() {
    return db.watch('''
      SELECT i.id AS item_id, it.tag_id AS tag_id
      FROM items i
      JOIN item_tags it
        ON it.item_id = i.id
        OR it.item_id = i.project_id
        OR it.item_id = i.area_id
      WHERE i.trashed = 0
    ''').map((rows) {
      final map = <String, Set<String>>{};
      for (final r in rows) {
        final itemId = r['item_id'] as String;
        final tagId = r['tag_id'] as String;
        map.putIfAbsent(itemId, () => <String>{}).add(tagId);
      }
      return map;
    });
  }

  // ---------------- 单条 ----------------

  Stream<Item?> watchItem(String id) {
    return db.watch('SELECT * FROM items WHERE id = ?', parameters: [id]).map(
        (rows) => rows.isEmpty
            ? null
            : Item.fromRow(rows.first as Map<String, dynamic>));
  }

  // ---------------- 搜索 ----------------

  /// 按标题模糊搜索活跃的任务与项目（Type Travel 用）。
  Future<List<Item>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final rows = await db.getAll('''
      SELECT * FROM items
      WHERE trashed = 0
        AND type IN ('task','project')
        AND title LIKE ?
      ORDER BY
        CASE status WHEN 'open' THEN 0 ELSE 1 END,
        updated_at DESC
      LIMIT 50
    ''', ['%$q%']);
    return rows.map((r) => Item.fromRow(r as Map<String, dynamic>)).toList();
  }

  /// 全局标签过滤：列出带某标签（含继承）的活跃任务/项目。
  Future<List<Item>> itemsWithTag(String tagId) async {
    final rows = await db.getAll('''
      SELECT DISTINCT i.* FROM items i
      JOIN item_tags it
        ON it.item_id = i.id OR it.item_id = i.project_id OR it.item_id = i.area_id
      WHERE it.tag_id = ?
        AND i.trashed = 0
        AND i.type IN ('task','project')
        AND i.status = 'open'
      ORDER BY i.updated_at DESC
      LIMIT 100
    ''', [tagId]);
    return rows.map((r) => Item.fromRow(r as Map<String, dynamic>)).toList();
  }

  // ---------------- 垃圾桶 ----------------

  Future<void> deletePermanently(String id) async {
    await _enqueueChildTombstones(id);
    await _enqueueTombstone('items', id);
    await db.execute('DELETE FROM checklist_items WHERE item_id = ?', [id]);
    await db.execute('DELETE FROM item_tags WHERE item_id = ?', [id]);
    await db.execute('DELETE FROM items WHERE id = ?', [id]);
  }

  Future<void> emptyTrash() async {
    final trashed =
        await db.getAll('SELECT id FROM items WHERE trashed = 1');
    for (final r in trashed) {
      final id = r['id'] as String;
      await _enqueueChildTombstones(id);
      await _enqueueTombstone('items', id);
    }
    await db.execute('''
      DELETE FROM checklist_items
      WHERE item_id IN (SELECT id FROM items WHERE trashed = 1)
    ''');
    await db.execute('''
      DELETE FROM item_tags
      WHERE item_id IN (SELECT id FROM items WHERE trashed = 1)
    ''');
    await db.execute('DELETE FROM items WHERE trashed = 1');
  }

  /// 为某条目下的检查项与标签关联登记删除墓碑。
  Future<void> _enqueueChildTombstones(String itemId) async {
    final cl =
        await db.getAll('SELECT id FROM checklist_items WHERE item_id = ?', [itemId]);
    for (final r in cl) {
      await _enqueueTombstone('checklist_items', r['id'] as String);
    }
    final it =
        await db.getAll('SELECT id FROM item_tags WHERE item_id = ?', [itemId]);
    for (final r in it) {
      await _enqueueTombstone('item_tags', r['id'] as String);
    }
  }

  // ---------------- 云同步底层支持 ----------------

  /// 登记一条删除墓碑（硬删除时调用），待下次同步推送给服务器。
  Future<void> _enqueueTombstone(String table, String rowId) async {
    await db.execute('''
      INSERT INTO sync_deletions (id, row_table, row_id, deleted_at)
      VALUES (?, ?, ?, ?)
    ''', [
      _uuid.v4(),
      table,
      rowId,
      DateTime.now().toUtc().toIso8601String(),
    ]);
  }

  /// 读取某表全部行（用于全量推送）。
  Future<List<Map<String, dynamic>>> allRows(String table) async {
    final rows = await db.getAll('SELECT * FROM $table');
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  /// 读取待推送的删除墓碑。
  Future<List<Map<String, dynamic>>> pendingDeletions() async {
    final rows = await db.getAll('SELECT * FROM sync_deletions');
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<void> clearDeletions(List<String> ids) async {
    for (final id in ids) {
      await db.execute('DELETE FROM sync_deletions WHERE id = ?', [id]);
    }
  }

  /// 给历史上缺失 updated_at 的 tags / item_tags 补时间戳（首次同步前调用）。
  Future<void> backfillTimestamps() async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await db.execute(
        "UPDATE tags SET updated_at = ? WHERE updated_at IS NULL OR updated_at = ''",
        [nowIso]);
    await db.execute(
        "UPDATE item_tags SET updated_at = ? WHERE updated_at IS NULL OR updated_at = ''",
        [nowIso]);
  }

  /// 应用一条来自服务器的 upsert（按表写入已知列）。不触发墓碑。
  Future<void> applyRemoteUpsert(String table, Map<String, dynamic> row) async {
    final cols = _syncColumns[table];
    if (cols == null) return;
    final id = row['id'];
    if (id == null) return;
    final present = cols.where((c) => row.containsKey(c)).toList();
    if (!present.contains('id')) present.insert(0, 'id');
    final placeholders = List.filled(present.length, '?').join(', ');
    final values = present.map((c) => row[c]).toList();
    await db.execute('DELETE FROM $table WHERE id = ?', [id]);
    await db.execute(
      'INSERT INTO $table (${present.join(', ')}) VALUES ($placeholders)',
      values,
    );
  }

  /// 应用一条来自服务器的删除。不触发墓碑。
  Future<void> applyRemoteDelete(String table, String id) async {
    if (!_syncColumns.containsKey(table)) return;
    await db.execute('DELETE FROM $table WHERE id = ?', [id]);
  }

  /// 各同步表的列（用于安全地按列写入远端行）。
  static const Map<String, List<String>> _syncColumns = {
    'items': [
      'id', 'user_id', 'type', 'title', 'status', 'completed_at',
      'trashed', 'start', 'start_date', 'evening', 'deadline', 'repeat',
      'repeat_interval', 'reminder_time', 'archived', 'area_id', 'project_id',
      'heading_id', 'sort_order', 'today_sort_order', 'created_at', 'updated_at',
    ],
    'areas': ['id', 'user_id', 'title', 'sort_order', 'created_at', 'updated_at'],
    'checklist_items': [
      'id', 'item_id', 'title', 'is_completed', 'sort_order', 'created_at',
      'updated_at',
    ],
    'tags': ['id', 'user_id', 'title', 'parent_tag_id', 'sort_order', 'updated_at'],
    'item_tags': ['id', 'user_id', 'item_id', 'tag_id', 'updated_at'],
  };

  static List<String> get syncTables => _syncColumns.keys.toList();

  // ----------------------------------------------------------------
  // 派生视图（核心：Today/Upcoming/Anytime 全靠 start + start_date 查询得出）
  // ----------------------------------------------------------------

  List<Item> _map(Iterable<dynamic> rows) =>
      rows.map((r) => Item.fromRow(r as Map<String, dynamic>)).toList();

  static const _activeTask = "type = 'task' AND status = 'open' AND trashed = 0";
  static const _activeListable =
      "type IN ('task','project') AND status = 'open' AND trashed = 0";

  /// 收件箱：未理清的任务（start = inbox）。
  Stream<List<Item>> watchInbox() {
    return db.watch('''
      SELECT * FROM items
      WHERE $_activeTask AND start = 'inbox'
      ORDER BY sort_order ASC, created_at DESC
    ''').map(_map);
  }

  /// 今天：两类来源（去重取并集）——
  ///   1. 被安排到今天/逾期的 anytime 任务（start_date <= 今天）；
  ///   2. 死线已到或逾期的任务（deadline <= 今天，无论它当前在哪个桶）。
  /// 对齐 Things：到点的死线会被强制拉到今天最上方。
  Stream<List<Item>> watchToday() {
    return db.watch('''
      SELECT * FROM items
      WHERE $_activeListable
        AND (
          (start = 'anytime' AND start_date IS NOT NULL
             AND start_date <= date('now','localtime'))
          -- 死线临近（含今天/逾期，及未来 2 天内）即从任意桶强推今天
          OR (deadline IS NOT NULL
             AND deadline <= date('now','localtime','+2 days'))
        )
      ORDER BY
        CASE WHEN deadline IS NOT NULL
             AND deadline <= date('now','localtime','+2 days') THEN 0 ELSE 1 END,
        evening ASC, today_sort_order ASC, created_at ASC
    ''').map(_map);
  }

  /// 计划：anytime 且 start_date 在未来。按日期升序，UI 再分组。
  Stream<List<Item>> watchUpcoming() {
    return db.watch('''
      SELECT * FROM items
      WHERE $_activeListable
        AND start = 'anytime'
        AND start_date IS NOT NULL
        AND start_date > date('now','localtime')
      ORDER BY start_date ASC, sort_order ASC
    ''').map(_map);
  }

  /// 计划视图的「占格」：被安排在未来的任务 + 未来死线影子。
  /// 一条任务可能同时产生两个占格（执行日 + 死线日），与 Things 一致。
  Stream<List<ScheduleEntry>> watchUpcomingEntries() {
    return db.watch('''
      SELECT * FROM items
      WHERE $_activeListable
        AND (
          (start = 'anytime' AND start_date IS NOT NULL
             AND start_date > date('now','localtime'))
          OR (deadline IS NOT NULL AND deadline > date('now','localtime'))
        )
      ORDER BY created_at ASC
    ''').map((rows) {
      final items = _map(rows);
      final entries = <ScheduleEntry>[];
      final today = DateTime.now();
      bool future(DateTime d) =>
          d.isAfter(DateTime(today.year, today.month, today.day));
      final horizon = DateTime(today.year, today.month, today.day)
          .add(const Duration(days: 120));
      for (final it in items) {
        if (it.start == WhenStart.anytime &&
            it.startDate != null &&
            future(it.startDate!)) {
          entries.add(ScheduleEntry(it, it.startDate!));
        }
        if (it.deadline != null && future(it.deadline!)) {
          entries.add(ScheduleEntry(it, it.deadline!, isDeadline: true));
        }
        // 重复任务：在未来日期上排出半透明影子预视。
        if (it.isRepeating && it.startDate != null) {
          var d = it.startDate!;
          for (var i = 0; i < 12; i++) {
            final n = it.repeat.next(d, it.repeatInterval);
            if (n == null || n.isAfter(horizon)) break;
            d = n;
            if (future(d)) entries.add(ScheduleEntry(it, d, isShadow: true));
          }
        }
      }
      entries.sort((a, b) => a.date.compareTo(b.date));
      return entries;
    });
  }

  /// 随时：anytime 且不被安排在未来（无日期或已到期）。含今天的任务。
  Stream<List<Item>> watchAnytime() {
    return db.watch('''
      SELECT * FROM items
      WHERE $_activeListable
        AND start = 'anytime'
        AND (start_date IS NULL OR start_date <= date('now','localtime'))
      ORDER BY sort_order ASC, created_at DESC
    ''').map(_map);
  }

  /// 将来：冷冻库（start = someday），灰显。
  Stream<List<Item>> watchSomeday() {
    return db.watch('''
      SELECT * FROM items
      WHERE $_activeListable AND start = 'someday'
      ORDER BY sort_order ASC, created_at DESC
    ''').map(_map);
  }

  /// 日志：已完成 / 已取消的任务与项目，按完成时间降序。
  Stream<List<Item>> watchLogbook() {
    return db.watch('''
      SELECT * FROM items
      WHERE type IN ('task','project')
        AND status IN ('completed','canceled')
        AND trashed = 0
      ORDER BY completed_at DESC
    ''').map(_map);
  }

  /// 垃圾站。
  Stream<List<Item>> watchTrash() {
    return db.watch('''
      SELECT * FROM items WHERE trashed = 1 ORDER BY updated_at DESC
    ''').map(_map);
  }

  /// 某个项目下的活跃任务与标题（用于项目详情页，按标题分组）。
  /// 已归档的标题（archived=1）连同其下任务都不在此列出。
  Stream<List<Item>> watchProjectItems(String projectId) {
    return db.watch('''
      SELECT * FROM items
      WHERE project_id = ? AND trashed = 0
        AND type IN ('task','heading')
        AND (type = 'heading' OR status = 'open')
        AND COALESCE(archived, 0) = 0
        AND (heading_id IS NULL OR heading_id NOT IN (
              SELECT id FROM items WHERE type = 'heading' AND COALESCE(archived,0) = 1
            ))
      ORDER BY sort_order ASC, created_at ASC
    ''', parameters: [projectId]).map(_map);
  }

  /// 归档 / 取消归档一个标题。
  Future<void> setHeadingArchived(String id, bool archived) async {
    await db.execute('''
      UPDATE items SET archived = ?, updated_at = ? WHERE id = ?
    ''', [archived ? 1 : 0, DateTime.now().toIso8601String(), id]);
  }

  /// 按给定顺序持久化一批条目的 sort_order（拖拽排序后调用）。
  Future<void> reorder(List<String> idsInOrder, {bool todayOrder = false}) async {
    final col = todayOrder ? 'today_sort_order' : 'sort_order';
    final now = DateTime.now().toIso8601String();
    await db.writeTransaction((tx) async {
      for (var i = 0; i < idsInOrder.length; i++) {
        await tx.execute(
          'UPDATE items SET $col = ?, updated_at = ? WHERE id = ?',
          [i, now, idsInOrder[i]],
        );
      }
    });
  }

  /// 把一个任务移动到某个标题下（或移出标题：headingId=null）。
  Future<void> assignHeading(String id, String? headingId) async {
    await db.execute('''
      UPDATE items SET heading_id = ?, updated_at = ? WHERE id = ?
    ''', [headingId, DateTime.now().toIso8601String(), id]);
  }

  /// 领域列表。
  Stream<List<Area>> watchAreas() {
    return db.watch('''
      SELECT * FROM areas ORDER BY sort_order ASC
    ''').map((rows) => rows.map((r) => Area.fromRow(r)).toList());
  }

  /// 所有活跃项目（侧边栏/主列表用）。
  Stream<List<Item>> watchProjects() {
    return db.watch('''
      SELECT * FROM items
      WHERE type = 'project' AND status = 'open' AND trashed = 0
      ORDER BY sort_order ASC
    ''').map(_map);
  }

  /// 一次性取出全部活跃（open、未删除）的任务与项目，供「一键回顾」在内存中分类。
  Future<List<Item>> activeSnapshot() async {
    final rows = await db.getAll('''
      SELECT * FROM items
      WHERE type IN ('task','project') AND status = 'open' AND trashed = 0
    ''');
    return _map(rows);
  }

  /// 项目进度（活跃 + 已完成任务的比例）。
  Stream<ProjectProgress> watchProjectProgress(String projectId) {
    return db.watch('''
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS done
      FROM items
      WHERE project_id = ? AND type = 'task' AND trashed = 0
        AND status != 'canceled'
    ''', parameters: [projectId]).map((rows) {
      final row = rows.first;
      final total = (row['total'] as int?) ?? 0;
      final done = (row['done'] as int?) ?? 0;
      return ProjectProgress(total, done);
    });
  }
}
