import 'dart:async';
import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

import '../database/powersync_db.dart' show db;
import '../database/schema.dart';

/// 「今日小组件」与原生 Android AppWidget 之间的数据桥。
///
/// 设计：
///   - 展示数据由主 isolate 通过 [refresh] 实时重算写入（随「今天」列表变化刷新）。
///   - 勾选完成 / 快速添加 / 标签筛选都走 home_widget 的**后台回调**（不打开 App）：
///     在后台 isolate 直接打开 PowerSync 本地库读写，再重算并刷新 widget。
///   - 标签筛选只作用于「今天」范围，单选；筛选/展开状态记在 widget 的 SharedPreferences 里。
class TodayWidgetService {
  TodayWidgetService._();
  static final instance = TodayWidgetService._();

  static const _qualifiedName =
      'com.clone.things3.things3_clone.TodayWidgetProvider';
  static const _compactName =
      'com.clone.things3.things3_clone.TodayCompactWidgetProvider';

  /// widget 上固定渲染的最大任务行数（超出用「还有 N 项」表示）。
  static const maxRows = 3;

  /// 标签行最多展示的 chip 数（无横滑，超出截断）。
  static const maxChips = 4;

  /// 交互 URI scheme（后台回调据此识别）。
  static const _scheme = 'todaywidget';

  /// 尚未接入 Auth，与 ItemRepository 保持同一固定用户。
  static const _userId = '00000000-0000-0000-0000-000000000001';

  bool _registered = false;

  /// 在 main() 里调用一次：注册后台交互回调。
  Future<void> init() async {
    if (_registered) return;
    _registered = true;
    await HomeWidget.registerInteractivityCallback(todayWidgetBackgroundCallback);
  }

  /// 主 isolate：用全局 db 重算并推送（「今天」列表一变就调）。
  Future<void> refresh() async {
    await _buildAndWrite(db);
  }

  // ----------------------------------------------------------------
  // 核心：构建展示数据并写入 + 刷新 widget（主/后台 isolate 共用）
  // ----------------------------------------------------------------

  static Future<void> _buildAndWrite(PowerSyncDatabase database) async {
    // 1) 读当前筛选 / 展开状态
    final expanded = (await HomeWidget.getWidgetData<String>('expanded')) == '1';
    final activeTagPref =
        (await HomeWidget.getWidgetData<String>('active_tag')) ?? '';

    // 2) 今日开放任务
    final today = await _queryToday(database);
    final todayIds = today.map((r) => r.id).toList();

    // 3) 今日任务的有效标签（含项目/区域继承）
    final links = <String, Set<String>>{}; // itemId -> {tagId}
    final tagTitle = <String, String>{};
    final tagOrder = <String, int>{};
    if (todayIds.isNotEmpty) {
      final placeholders = List.filled(todayIds.length, '?').join(',');
      final rows = await database.getAll('''
        SELECT i.id AS item_id, t.id AS tag_id, t.title AS tag_title, t.sort_order AS so
        FROM items i
        JOIN item_tags it
          ON (it.item_id = i.id OR it.item_id = i.project_id OR it.item_id = i.area_id)
        JOIN tags t ON t.id = it.tag_id
        WHERE i.id IN ($placeholders)
      ''', todayIds);
      for (final r in rows) {
        final itemId = r['item_id'] as String;
        final tagId = r['tag_id'] as String;
        links.putIfAbsent(itemId, () => <String>{}).add(tagId);
        tagTitle[tagId] = (r['tag_title'] as String?) ?? '';
        tagOrder[tagId] = (r['so'] as int?) ?? 0;
      }
    }

    // 今日出现过的标签（按 sort_order 排），取前 maxChips 个作为 chip
    final presentTags = tagTitle.keys.toList()
      ..sort((a, b) => (tagOrder[a] ?? 0).compareTo(tagOrder[b] ?? 0));
    final chips = presentTags.take(maxChips).toList();

    // 4) 应用筛选（active 必须仍出现在今日里才有效）
    final active = presentTags.contains(activeTagPref) ? activeTagPref : '';
    final filtered = active.isEmpty
        ? today
        : today
            .where((r) => (links[r.id] ?? const <String>{}).contains(active))
            .toList();

    // 5) 今日完成度（进度环）：今日已完成数 / (今日已完成 + 今日开放)
    final doneRows = await database.getAll('''
      SELECT COUNT(*) AS c FROM items
      WHERE type IN ('task','project') AND status = 'completed' AND trashed = 0
        AND completed_at IS NOT NULL
        AND date(completed_at,'localtime') = date('now','localtime')
    ''');
    final done = (doneRows.first['c'] as int?) ?? 0;
    final total = done + today.length;

    // 6) 写入
    await _write(
      rows: filtered,
      done: done,
      total: total,
      // 2×2 极简版用：今日待办总数 / 最紧要一条，均「不受 4×2 标签筛选影响」。
      todayOpen: today.length,
      firstTitle: today.isEmpty ? '' : today.first.title,
      expanded: active.isNotEmpty ? true : expanded,
      activeTagId: active,
      activeTagTitle: active.isEmpty ? '' : (tagTitle[active] ?? ''),
      chips: chips,
      chipTitle: tagTitle,
    );
  }

  static Future<void> _write({
    required List<_TodayRow> rows,
    required int done,
    required int total,
    required int todayOpen,
    required String firstTitle,
    required bool expanded,
    required String activeTagId,
    required String activeTagTitle,
    required List<String> chips,
    required Map<String, String> chipTitle,
  }) async {
    final shown = rows.length > maxRows ? maxRows : rows.length;
    // 数字一律以字符串存储，规避 home_widget 在 Android 上 Int/Long 读取不一致的坑。
    await HomeWidget.saveWidgetData<String>('count', '${rows.length}');
    await HomeWidget.saveWidgetData<String>('today_open', '$todayOpen');
    await HomeWidget.saveWidgetData<String>('first_title', firstTitle);
    await HomeWidget.saveWidgetData<String>('rows_shown', '$shown');
    await HomeWidget.saveWidgetData<String>('more', '${rows.length - shown}');
    await HomeWidget.saveWidgetData<String>('done', '$done');
    await HomeWidget.saveWidgetData<String>('total', '$total');
    await HomeWidget.saveWidgetData<String>('expanded', expanded ? '1' : '0');
    await HomeWidget.saveWidgetData<String>('active_tag', activeTagId);
    await HomeWidget.saveWidgetData<String>('active_tag_title', activeTagTitle);

    for (var i = 0; i < maxRows; i++) {
      if (i < shown) {
        final r = rows[i];
        await HomeWidget.saveWidgetData<String>('row${i}_id', r.id);
        await HomeWidget.saveWidgetData<String>('row${i}_title', r.title);
        await HomeWidget.saveWidgetData<bool>('row${i}_flag', r.flag);
        await HomeWidget.saveWidgetData<bool>('row${i}_evening', r.evening);
      } else {
        await HomeWidget.saveWidgetData<String>('row${i}_id', '');
        await HomeWidget.saveWidgetData<String>('row${i}_title', '');
      }
    }

    await HomeWidget.saveWidgetData<String>('chip_count', '${chips.length}');
    for (var i = 0; i < maxChips; i++) {
      final id = i < chips.length ? chips[i] : '';
      await HomeWidget.saveWidgetData<String>('chip${i}_id', id);
      await HomeWidget.saveWidgetData<String>(
          'chip${i}_title', id.isEmpty ? '' : (chipTitle[id] ?? ''));
    }

    await HomeWidget.updateWidget(qualifiedAndroidName: _qualifiedName);
    await HomeWidget.updateWidget(qualifiedAndroidName: _compactName);
  }

  // ----------------------------------------------------------------
  // 后台回调（独立 isolate，无法访问 App 的 Riverpod / 主 isolate 的 db）
  // ----------------------------------------------------------------

  static Future<void> handleBackground(Uri? uri) async {
    if (uri == null || uri.scheme != _scheme) return;

    final database = await _openLocalDb();
    try {
      switch (uri.host) {
        case 'complete':
          final id = uri.queryParameters['id'];
          if (id != null && id.isNotEmpty) {
            final now = DateTime.now().toIso8601String();
            await database.execute(
              "UPDATE items SET status = 'completed', completed_at = ?, updated_at = ? WHERE id = ?",
              [now, now, id],
            );
          }
          break;
        case 'add':
          final title = (uri.queryParameters['title'] ?? '').trim();
          if (title.isNotEmpty) {
            // 小组件只做「便捷投递」：一律落入收件箱，随后在 App 里整理。
            await _insertInbox(database, title);
          }
          break;
        case 'togglefilter':
          final cur = (await HomeWidget.getWidgetData<String>('expanded')) == '1';
          await HomeWidget.saveWidgetData<String>('expanded', cur ? '0' : '1');
          break;
        case 'filter':
          final tag = uri.queryParameters['tag'] ?? '';
          final cur = (await HomeWidget.getWidgetData<String>('active_tag')) ?? '';
          // 点已选中的、或空 tag（「全部」/✕）→ 清除；否则设为该标签并保持展开。
          final next = (tag.isEmpty || tag == cur) ? '' : tag;
          await HomeWidget.saveWidgetData<String>('active_tag', next);
          if (next.isNotEmpty) {
            await HomeWidget.saveWidgetData<String>('expanded', '1');
          }
          break;
        default:
          return;
      }
      await _buildAndWrite(database);
    } finally {
      await database.close();
    }
  }

  /// 在后台 isolate 直接插入一条收件箱任务（字段默认值与 ItemRepository.createTask 对齐）。
  static Future<void> _insertInbox(PowerSyncDatabase database, String title) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final order = now.millisecondsSinceEpoch;
    await database.execute('''
      INSERT INTO items
        (id, user_id, type, title, status, completed_at, trashed,
         start, start_date, evening, deadline,
         repeat, repeat_interval, reminder_time, archived,
         area_id, project_id, heading_id, sort_order, today_sort_order,
         created_at, updated_at)
      VALUES (?, ?, 'task', ?, 'open', NULL, 0,
              'inbox', NULL, 0, NULL,
              'none', 1, NULL, 0,
              NULL, NULL, NULL, ?, ?,
              ?, ?)
    ''', [id, _userId, title, order, order, nowIso, nowIso]);
  }

  /// 在后台 isolate 打开同一个本地 PowerSync 库（离线，不连云）。
  static Future<PowerSyncDatabase> _openLocalDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}${Platform.pathSeparator}things3_clone_db.sqlite';
    final local = PowerSyncDatabase(schema: appSchema, path: path);
    await local.initialize();
    return local;
  }

  /// 与 ItemRepository.watchToday 同源的「今天」查询（后台精简版）。
  static Future<List<_TodayRow>> _queryToday(PowerSyncDatabase database) async {
    final result = await database.getAll('''
      SELECT id, title, evening, deadline FROM items
      WHERE type IN ('task','project') AND status = 'open' AND trashed = 0
        AND (
          (start = 'anytime' AND start_date IS NOT NULL
             AND start_date <= date('now','localtime'))
          OR (deadline IS NOT NULL
             AND deadline <= date('now','localtime','+2 days'))
        )
      ORDER BY
        CASE WHEN deadline IS NOT NULL
             AND deadline <= date('now','localtime','+2 days') THEN 0 ELSE 1 END,
        evening ASC, today_sort_order ASC, created_at ASC
    ''');
    return result
        .map((r) => _TodayRow.fromRow(r as Map<String, dynamic>))
        .toList();
  }
}

/// home_widget 后台交互回调入口。
///
/// 必须是**顶层函数**且带 `@pragma('vm:entry-point')`——AOT 下若放在类的静态方法上，
/// 原生侧访问会报 “must be annotated” 而无法调用。
@pragma('vm:entry-point')
Future<void> todayWidgetBackgroundCallback(Uri? uri) {
  return TodayWidgetService.handleBackground(uri);
}

/// widget 单行的精简数据。
class _TodayRow {
  final String id;
  final String title;
  final bool flag; // 死线临近（今天/逾期/未来 2 天内）
  final bool evening;
  const _TodayRow(this.id, this.title, this.flag, this.evening);

  factory _TodayRow.fromRow(Map<String, dynamic> r) {
    final deadlineStr = r['deadline'] as String?;
    DateTime? deadline =
        (deadlineStr == null || deadlineStr.isEmpty) ? null : DateTime.tryParse(deadlineStr);
    final flag = deadline != null &&
        DateTime(deadline.year, deadline.month, deadline.day)
            .isBefore(DateTime.now().add(const Duration(days: 3)));
    return _TodayRow(
      r['id'] as String,
      (r['title'] as String?) ?? '',
      flag,
      ((r['evening'] as int?) ?? 0) == 1,
    );
  }
}
