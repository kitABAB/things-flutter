/// 自然语言日期/时间解析（中文 + 英文），对齐 Things 的 Jump Start。
///
/// 支持例子：
///   今天 / 明天 / 后天 / 大后天 / today / tom / tomorrow
///   周六 / 星期天 / 下周一 / sat / monday
///   3天后 / 三天后 / in 4 days / 下周 / 下个月
///   8月1日 / 8/1 / aug 1
///   今晚 / 晚上8点 / 8pm / 20:00 / wed 8pm
class NaturalDateResult {
  final DateTime? date;
  final bool evening;
  final String? time; // 'HH:mm'
  const NaturalDateResult({this.date, this.evening = false, this.time});

  bool get isEmpty => date == null && !evening && time == null;
}

class NaturalDate {
  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static const _cnNum = {
    '一': 1, '二': 2, '两': 2, '三': 3, '四': 4, '五': 5,
    '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
  };

  static const _weekdayCn = {
    '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7,
  };

  static const _weekdayEn = {
    'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7,
  };

  static int? _parseCnNumber(String s) {
    if (s.isEmpty) return null;
    final direct = int.tryParse(s);
    if (direct != null) return direct;
    // 十 / 十一 / 二十 等简易中文数字
    if (s == '十') return 10;
    if (s.startsWith('十')) return 10 + (_cnNum[s.substring(1)] ?? 0);
    if (s.contains('十')) {
      final parts = s.split('十');
      final tens = _cnNum[parts[0]] ?? 1;
      final ones = parts.length > 1 ? (_cnNum[parts[1]] ?? 0) : 0;
      return tens * 10 + ones;
    }
    return _cnNum[s];
  }

  static NaturalDateResult parse(String raw) {
    final input = raw.trim().toLowerCase();
    if (input.isEmpty) return const NaturalDateResult();

    DateTime? date;
    bool evening = false;
    String? time = _parseTime(input);
    if (input.contains('今晚') || input.contains('晚上') || input.contains('evening')) {
      evening = true;
    }

    final today = _today();

    // 相对日
    if (input.contains('大后天')) {
      date = today.add(const Duration(days: 3));
    } else if (input.contains('后天')) {
      date = today.add(const Duration(days: 2));
    } else if (input.contains('明天') ||
        input.contains('tomorrow') ||
        RegExp(r'\btom\b').hasMatch(input)) {
      date = today.add(const Duration(days: 1));
    } else if (input.contains('今天') ||
        input.contains('今晚') ||
        input.contains('today')) {
      date = today;
    }

    // N 天后 / in N days
    date ??= _parseRelativeDays(input, today);
    // 下周 / 下个月
    if (date == null) {
      if (input.contains('下周') || input.contains('下星期') || input.contains('next week')) {
        date = today.add(const Duration(days: 7));
      } else if (input.contains('下个月') || input.contains('下月') || input.contains('next month')) {
        date = DateTime(today.year, today.month + 1, today.day);
      }
    }
    // 星期几 / weekday
    date ??= _parseWeekday(input, today);
    // 月日 8月1日 / 8/1 / aug 1
    date ??= _parseMonthDay(input, today);

    return NaturalDateResult(date: date, evening: evening, time: time);
  }

  static DateTime? _parseRelativeDays(String input, DateTime today) {
    final en = RegExp(r'in\s+(\d+)\s*day').firstMatch(input);
    if (en != null) {
      return today.add(Duration(days: int.parse(en.group(1)!)));
    }
    final cn = RegExp(r'([0-9一二两三四五六七八九十]+)\s*天后').firstMatch(input);
    if (cn != null) {
      final n = _parseCnNumber(cn.group(1)!);
      if (n != null) return today.add(Duration(days: n));
    }
    final cnWeek = RegExp(r'([0-9一二两三四五六七八九十]+)\s*周后').firstMatch(input);
    if (cnWeek != null) {
      final n = _parseCnNumber(cnWeek.group(1)!);
      if (n != null) return today.add(Duration(days: n * 7));
    }
    return null;
  }

  static DateTime? _parseWeekday(String input, DateTime today) {
    int? target;
    final cn = RegExp(r'(周|星期|礼拜)([一二三四五六日天])').firstMatch(input);
    if (cn != null) target = _weekdayCn[cn.group(2)];
    if (target == null) {
      for (final e in _weekdayEn.entries) {
        if (input.contains(e.key)) {
          target = e.value;
          break;
        }
      }
    }
    if (target == null) return null;

    final nextWeek = input.contains('下周') || input.contains('下星期') || input.contains('next');
    var delta = (target - today.weekday) % 7;
    if (delta <= 0) delta += 7; // 默认取将来最近的那天
    if (nextWeek && delta < 7) delta += 7;
    return today.add(Duration(days: delta));
  }

  static DateTime? _parseMonthDay(String input, DateTime today) {
    final cn = RegExp(r'(\d{1,2})\s*月\s*(\d{1,2})').firstMatch(input);
    if (cn != null) {
      return _normalizeMonthDay(
          int.parse(cn.group(1)!), int.parse(cn.group(2)!), today);
    }
    final slash = RegExp(r'\b(\d{1,2})/(\d{1,2})\b').firstMatch(input);
    if (slash != null) {
      return _normalizeMonthDay(
          int.parse(slash.group(1)!), int.parse(slash.group(2)!), today);
    }
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    for (final e in months.entries) {
      final m = RegExp('${e.key}[a-z]*\\s+(\\d{1,2})').firstMatch(input);
      if (m != null) {
        return _normalizeMonthDay(e.value, int.parse(m.group(1)!), today);
      }
    }
    return null;
  }

  static DateTime _normalizeMonthDay(int month, int day, DateTime today) {
    var d = DateTime(today.year, month, day);
    if (d.isBefore(today)) d = DateTime(today.year + 1, month, day);
    return d;
  }

  static String? _parseTime(String input) {
    // 20:00 / 8:30
    final hm = RegExp(r'\b(\d{1,2}):(\d{2})\b').firstMatch(input);
    if (hm != null) {
      final h = int.parse(hm.group(1)!);
      final m = int.parse(hm.group(2)!);
      if (h < 24 && m < 60) return _fmt(h, m);
    }
    // 8pm / 11am
    final ampm = RegExp(r'\b(\d{1,2})\s*(am|pm)\b').firstMatch(input);
    if (ampm != null) {
      var h = int.parse(ampm.group(1)!);
      if (ampm.group(2) == 'pm' && h < 12) h += 12;
      if (ampm.group(2) == 'am' && h == 12) h = 0;
      return _fmt(h, 0);
    }
    // 晚上8点 / 早上7点 / 下午3点
    final cn = RegExp(r'(早上|上午|中午|下午|晚上)?\s*([0-9一二两三四五六七八九十]+)\s*点').firstMatch(input);
    if (cn != null) {
      var h = _parseCnNumber(cn.group(2)!) ?? 0;
      final period = cn.group(1);
      if ((period == '下午' || period == '晚上') && h < 12) h += 12;
      if (period == '中午') h = 12;
      return _fmt(h % 24, 0);
    }
    return null;
  }

  static String _fmt(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}
