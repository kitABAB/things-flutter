/// 轻量日历事件模型（与 UI 解耦）。
class CalEvent {
  final String title;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  const CalEvent({
    required this.title,
    required this.start,
    this.end,
    this.allDay = false,
  });
}

/// 系统日历事件读取（只读）。
///
/// 说明：系统日历插件 `device_calendar` 当前锁定 `timezone ^0.9.0`，
/// 与本项目通知栈所需的 `flutter_local_notifications 22 → timezone ^0.11.0`
/// 存在不可调和的版本冲突。为保住更高优先级的「本地闹钟提醒」，这里先以
/// 安全空实现接入：UI 的事件编织、Today/Upcoming 的 provider 全部就绪，
/// 一旦出现兼容 timezone 0.11 的日历插件，仅替换本文件即可启用真实读取。
class CalendarService {
  CalendarService._();
  static final CalendarService instance = CalendarService._();

  /// 是否已接入真实系统日历（当前为否）。
  bool get isAvailable => false;

  Future<bool> ensurePermission() async => false;

  /// 取 [from, to) 范围内的系统日历事件。当前返回空列表。
  Future<List<CalEvent>> eventsBetween(DateTime from, DateTime to) async {
    return const [];
  }
}
