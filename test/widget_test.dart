import 'package:flutter_test/flutter_test.dart';

import 'package:things3_clone/domain/models/item.dart';

void main() {
  test('Item.fromRow 解析两条正交的轴', () {
    final now = DateTime.now().toIso8601String();
    final item = Item.fromRow({
      'id': 'a',
      'user_id': 'u',
      'type': 'task',
      'title': '测试任务',
      'status': 'open',
      'trashed': 0,
      'start': 'anytime',
      'start_date': '2026-06-23',
      'evening': 1,
      'deadline': '2026-06-30',
      'created_at': now,
      'updated_at': now,
    });

    expect(item.type, ItemType.task);
    expect(item.status, ItemStatus.open);
    expect(item.start, WhenStart.anytime);
    expect(item.evening, true);
    expect(item.startDate, isNotNull);
    expect(item.deadline, isNotNull);
  });
}
