/// 轻量的中文日期格式化工具（不引入 intl 依赖）。
class DateFmt {
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 相对今天的天数差（正数=未来，负数=过去）。
  static int daysFromToday(DateTime d) {
    final today = _dateOnly(DateTime.now());
    return _dateOnly(d).difference(today).inDays;
  }

  /// 计划视图分组标题：今天 / 明天 / 后天 / 周三 / 6月30日。
  static String groupLabel(DateTime d) {
    final diff = daysFromToday(d);
    if (diff == 0) return '今天';
    if (diff == 1) return '明天';
    if (diff == 2) return '后天';
    if (diff > 2 && diff < 7) return '周${_weekdays[d.weekday - 1]}';
    return '${d.month}月${d.day}日';
  }

  /// 死线徽标文案。
  static String deadlineLabel(DateTime d) {
    final diff = daysFromToday(d);
    if (diff == 0) return '今天截止';
    if (diff < 0) return '逾期 ${-diff} 天';
    if (diff == 1) return '明天截止';
    return '还剩 $diff 天';
  }

  /// 日志分组标题。
  static String logLabel(DateTime d) {
    final diff = daysFromToday(d);
    if (diff == 0) return '今天';
    if (diff == -1) return '昨天';
    return '${d.year}年${d.month}月${d.day}日';
  }

  static String yearMonthDay(DateTime d) => '${d.year}-${d.month}-${d.day}';
}
