import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/item.dart';
import 'providers/item_providers.dart';

/// 系统级时间视图（GTD 的几个顶级桶）。
enum AppView { inbox, today, upcoming, anytime, someday, logbook }

extension AppViewMeta on AppView {
  String get title {
    switch (this) {
      case AppView.inbox:
        return '收件箱';
      case AppView.today:
        return '今天';
      case AppView.upcoming:
        return '计划';
      case AppView.anytime:
        return '随时';
      case AppView.someday:
        return '将来';
      case AppView.logbook:
        return '日志';
    }
  }

  IconData get icon {
    switch (this) {
      case AppView.inbox:
        return Icons.inbox_rounded;
      case AppView.today:
        return Icons.star_rounded;
      case AppView.upcoming:
        return Icons.calendar_today_rounded;
      case AppView.anytime:
        return Icons.layers_rounded;
      case AppView.someday:
        return Icons.archive_rounded;
      case AppView.logbook:
        return Icons.check_circle_rounded;
    }
  }

  Color get color {
    switch (this) {
      case AppView.inbox:
        return const Color(0xFF5B8DEF); // 柔和蓝托盘
      case AppView.today:
        return const Color(0xFFFAC51C); // 金色星
      case AppView.upcoming:
        return const Color(0xFFE5564E); // 红日历
      case AppView.anytime:
        return const Color(0xFF21B5A8); // 青绿叠层
      case AppView.someday:
        return const Color(0xFFB7935A); // 米褐箱
      case AppView.logbook:
        return const Color(0xFF53B25B); // 绿对勾（Things 日志为绿）
    }
  }

  String get emptyHint {
    switch (this) {
      case AppView.inbox:
        return '随手记录你的想法，之后再理清';
      case AppView.today:
        return '今天没有任务。好好享受属于你的一天';
      case AppView.upcoming:
        return '接下来的日子还很空闲';
      case AppView.anytime:
        return '没有可随时执行的任务';
      case AppView.someday:
        return '将来也许会做的事，放在这里冷冻';
      case AppView.logbook:
        return '完成的任务会归档到这里';
    }
  }

  StreamProvider<List<Item>> get provider {
    switch (this) {
      case AppView.inbox:
        return inboxProvider;
      case AppView.today:
        return todayProvider;
      case AppView.upcoming:
        return upcomingProvider;
      case AppView.anytime:
        return anytimeProvider;
      case AppView.someday:
        return somedayProvider;
      case AppView.logbook:
        return logbookProvider;
    }
  }
}
