import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/item_repository.dart';
import '../../data/services/calendar_service.dart';
import '../../domain/models/item.dart';

final itemRepositoryProvider = Provider<ItemRepository>((ref) {
  return ItemRepository();
});

final inboxProvider = StreamProvider<List<Item>>((ref) {
  return ref.watch(itemRepositoryProvider).watchInbox();
});

final todayProvider = StreamProvider<List<Item>>((ref) {
  return ref.watch(itemRepositoryProvider).watchToday();
});

final upcomingProvider = StreamProvider<List<Item>>((ref) {
  return ref.watch(itemRepositoryProvider).watchUpcoming();
});

final upcomingEntriesProvider = StreamProvider<List<ScheduleEntry>>((ref) {
  return ref.watch(itemRepositoryProvider).watchUpcomingEntries();
});

final anytimeProvider = StreamProvider<List<Item>>((ref) {
  return ref.watch(itemRepositoryProvider).watchAnytime();
});

final somedayProvider = StreamProvider<List<Item>>((ref) {
  return ref.watch(itemRepositoryProvider).watchSomeday();
});

final logbookProvider = StreamProvider<List<Item>>((ref) {
  return ref.watch(itemRepositoryProvider).watchLogbook();
});

final areasProvider = StreamProvider<List<Area>>((ref) {
  return ref.watch(itemRepositoryProvider).watchAreas();
});

final projectsProvider = StreamProvider<List<Item>>((ref) {
  return ref.watch(itemRepositoryProvider).watchProjects();
});

final projectItemsProvider =
    StreamProvider.family<List<Item>, String>((ref, projectId) {
  return ref.watch(itemRepositoryProvider).watchProjectItems(projectId);
});

final projectProgressProvider =
    StreamProvider.family<ProjectProgress, String>((ref, projectId) {
  return ref.watch(itemRepositoryProvider).watchProjectProgress(projectId);
});

final itemProvider = StreamProvider.family<Item?, String>((ref, id) {
  return ref.watch(itemRepositoryProvider).watchItem(id);
});

final checklistProvider =
    StreamProvider.family<List<ChecklistItem>, String>((ref, taskId) {
  return ref.watch(itemRepositoryProvider).watchChecklist(taskId);
});

final tagsProvider = StreamProvider<List<Tag>>((ref) {
  return ref.watch(itemRepositoryProvider).watchTags();
});

final itemTagsProvider =
    StreamProvider.family<List<Tag>, String>((ref, itemId) {
  return ref.watch(itemRepositoryProvider).watchItemTags(itemId);
});

final trashProvider = StreamProvider<List<Item>>((ref) {
  return ref.watch(itemRepositoryProvider).watchTrash();
});

final itemTagLinksProvider = StreamProvider<Map<String, Set<String>>>((ref) {
  return ref.watch(itemRepositoryProvider).watchItemTagLinks();
});

/// 含继承（项目/区域）的有效标签映射，视图过滤用。
final effectiveItemTagLinksProvider =
    StreamProvider<Map<String, Set<String>>>((ref) {
  return ref.watch(itemRepositoryProvider).watchEffectiveItemTagLinks();
});

/// 某条目从项目/区域继承来的标签。
final inheritedTagsProvider =
    StreamProvider.family<List<Tag>, String>((ref, itemId) {
  return ref.watch(itemRepositoryProvider).watchInheritedTags(itemId);
});

/// 今天的系统日历事件（只读，编织进「今天」视图）。
final todayCalendarProvider = FutureProvider<List<CalEvent>>((ref) async {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day);
  final to = from.add(const Duration(days: 1));
  return CalendarService.instance.eventsBetween(from, to);
});

/// 未来 120 天的系统日历事件（编织进「计划」时间轴）。
final upcomingCalendarProvider = FutureProvider<List<CalEvent>>((ref) async {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  final to = from.add(const Duration(days: 120));
  return CalendarService.instance.eventsBetween(from, to);
});
