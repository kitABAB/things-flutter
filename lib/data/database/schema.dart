import 'package:powersync/powersync.dart';

/// 统一的条目表：任务(task) / 项目(project) / 标题(heading) 共用一张表，
/// 用 `type` 区分。这样做贴合 Things 3 的真实实现：
///   - 项目本身可以被安排到「今天」，作为带进度圆环的一行出现在列表里；
///   - 任务与标题在项目内拖拽排序时共享同一套 sort_order。
///
/// 两条正交的轴：
///   - 生命周期 status：open / completed / canceled（决定死活，配合 trashed 垃圾站）
///   - 调度意图 start：inbox / anytime / someday（只存这 3 态）
/// 「今天 / 计划 / 随时」全部由 start + start_date 实时派生，而不是持久化存储。
const itemsTable = Table('items', [
  Column.text('user_id'),
  // 'task' | 'project' | 'heading'
  Column.text('type'),
  Column.text('title'),

  // 轴 A：生命周期
  // 'open' | 'completed' | 'canceled'
  Column.text('status'),
  Column.text('completed_at'),
  Column.integer('trashed'),

  // 轴 B：调度意图（只存 3 态）
  // 'inbox' | 'anytime' | 'someday'
  Column.text('start'),
  // "打算哪天做" 的日期，存 YYYY-MM-DD；Today/Upcoming 全靠它派生
  Column.text('start_date'),
  Column.integer('evening'),

  // 轴 C：死线（与 start_date 完全正交）
  Column.text('deadline'),

  // 重复规则：none / daily / weekly / monthly / yearly，配合 repeat_interval。
  Column.text('repeat'),
  Column.integer('repeat_interval'),

  // 闹钟提醒：'HH:mm'（与 start_date 组合成精确提醒时刻）。
  Column.text('reminder_time'),

  // 标题(heading)归档：归档后连同其下任务从项目视图收起。
  Column.integer('archived'),

  // 层级归属（全部可空 -> 支持孤立项目 / 孤立任务）
  Column.text('area_id'),
  Column.text('project_id'),
  Column.text('heading_id'),

  // 手动排序
  Column.integer('sort_order'),
  Column.integer('today_sort_order'),

  Column.text('created_at'),
  Column.text('updated_at'),
]);

/// 责任领域：侧边栏顶层聚合根，没有日期。
const areasTable = Table('areas', [
  Column.text('user_id'),
  Column.text('title'),
  Column.integer('sort_order'),
  Column.text('created_at'),
  Column.text('updated_at'),
]);

/// 检查项：挂在单个 task 之下的轻量子清单。
const checklistItemsTable = Table('checklist_items', [
  Column.text('item_id'),
  Column.text('title'),
  Column.integer('is_completed'),
  Column.integer('sort_order'),
  Column.text('created_at'),
  Column.text('updated_at'),
]);

/// 标签：支持层级（parent_tag_id 指向父标签）。
const tagsTable = Table('tags', [
  Column.text('user_id'),
  Column.text('title'),
  Column.text('parent_tag_id'),
  Column.integer('sort_order'),
  // 云同步用时间戳
  Column.text('updated_at'),
]);

/// 任务 <-> 标签 多对多关联。
const itemTagsTable = Table('item_tags', [
  Column.text('user_id'),
  Column.text('item_id'),
  Column.text('tag_id'),
  // 云同步用时间戳
  Column.text('updated_at'),
]);

/// 本地删除墓碑队列：硬删除时写入，待下次同步推送给服务器后清除。
const syncDeletionsTable = Table.localOnly('sync_deletions', [
  Column.text('row_table'),
  Column.text('row_id'),
  Column.text('deleted_at'),
]);

const appSchema = Schema([
  itemsTable,
  areasTable,
  checklistItemsTable,
  tagsTable,
  itemTagsTable,
  syncDeletionsTable,
]);
