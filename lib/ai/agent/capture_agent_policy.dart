part of 'capture_agent.dart';

class _AgentPolicy {
  final CaptureContext ctx;

  const _AgentPolicy(this.ctx);

  _AgentFinal? apply(
    String raw,
    _AgentWorkspace workspace, {
    required bool hasCurrentDraft,
  }) {
    final text = _norm(raw);

    if (!hasCurrentDraft && _isDangerousDestructive(text)) {
      workspace.replace(const []);
      return const _AgentFinal(
        message: '这个会影响已有任务，我不能直接替你删除。你可以告诉我要整理哪几项。',
        suggestions: ['只整理收件箱', '只新增待创建项'],
        needsUser: true,
      );
    }

    if (!hasCurrentDraft &&
        _isHighlyVague(text) &&
        (workspace._items.isEmpty ||
            workspace._items.every((item) => _isVagueTitle(item.title)))) {
      workspace.replace(const []);
      return _AgentFinal(
        message: '这件事具体是指什么？',
        suggestions: _vagueSuggestions(text),
        needsUser: true,
      );
    }

    for (final item in workspace._items) {
      final combined = _norm('$raw ${item.title}');
      _polishTitle(item, text);
      _applyWhen(item, combined);
      _applyDeadline(item, combined);
      _applyList(item, combined);
      _applyTags(item, combined);
    }

    return null;
  }

  void _applyList(DraftItem item, String text) {
    final canOverride =
        item.listName == null ||
        item.listName == DraftItem.inboxToken ||
        item.listKind != null;
    if (!canOverride) return;

    final project = _strongProject(text);
    if (project != null) {
      item.listName = project;
      item.listKind = null;
      return;
    }

    if (item.listName != null && item.listName != DraftItem.inboxToken) return;
    final area = _strongArea(text);
    if (area != null) {
      item.listName = area;
      item.listKind = null;
    }
  }

  String? _strongProject(String text) {
    if (_hasProject('AI 配置') &&
        _hasAny(text, const [
          'ai配置',
          'ai 配置',
          '模型',
          'apikey',
          'api key',
          'key',
          '网关',
          'gemini',
          'deepseek',
          'openai',
          'claude',
          'llm',
        ])) {
      return _projectName('AI 配置');
    }
    if (_hasProject('产品周会') &&
        _hasAny(text, const [
          '产品周会',
          '产品会',
          '周会',
          '议题',
          '复盘',
          'agenda',
          '会议材料',
        ])) {
      return _projectName('产品周会');
    }
    if (_hasProject('日本旅行') &&
        _hasAny(text, const [
          '日本旅行',
          '旅行',
          '签证',
          '机票',
          '酒店',
          '东京',
          '京都',
          '证件',
        ])) {
      return _projectName('日本旅行');
    }
    if (_hasProject('搬家') &&
        _hasAny(text, const ['搬家', '退租', '纸箱', '搬家公司', '宽带', '网约车'])) {
      return _projectName('搬家');
    }
    return null;
  }

  String? _strongArea(String text) {
    if (_hasArea('学习') &&
        _hasAny(text, const [
          '学习',
          '日语',
          '英语',
          '教程',
          '课程',
          'dart',
          'flutter',
          '摄影',
        ])) {
      return _areaName('学习');
    }
    if (_hasArea('健康') &&
        _hasAny(text, const [
          '健康',
          '运动',
          '跑步',
          '训练',
          '牙医',
          '体检',
          '身体',
          '核心训练',
        ])) {
      return _areaName('健康');
    }
    if (_hasArea('生活') &&
        _hasAny(text, const [
          '家务',
          '厨房',
          '垃圾',
          '清洁',
          '收纳',
          '房间',
          '买菜',
          '物业',
          '爸妈',
        ])) {
      return _areaName('生活');
    }
    if (_hasArea('工作') &&
        _hasAny(text, const ['工作', '日报', '财务', '报销', '设计', '首页', '文档'])) {
      return _areaName('工作');
    }
    return null;
  }

  void _applyTags(DraftItem item, String text) {
    if (_hasAny(text, const [
      'ai',
      '模型',
      'key',
      '网关',
      'gemini',
      'deepseek',
      'openai',
      'claude',
      'llm',
    ])) {
      _addTag(item, 'AI');
    }
    if (_hasAny(text, const [
      '发',
      '电话',
      '消息',
      '联系',
      '确认',
      '约',
      '王总',
      '李雷',
      '爸妈',
    ])) {
      _addTag(item, '沟通');
    }
    if (_hasAny(text, const ['周会', '产品会', '会议', 'agenda', '议题', '纪要', '复盘'])) {
      _addTag(item, '会议');
    }
    if (_hasAny(text, const ['日语', '五十音', '口语'])) {
      _addTag(item, '日语');
    }
    if (_hasAny(text, const ['买', '采购', '价格', '票', '纸箱', '收纳箱'])) {
      _addTag(item, '采购');
    }
    if (_hasAny(text, const ['运动', '跑步', '训练', '核心训练'])) {
      _addTag(item, '运动');
      if (!ctx.tagNames.any((tag) => _same(tag, '跑步')) && text.contains('跑步')) {
        _addTag(item, '跑步', requireExisting: false);
      }
    }
    if (_hasAny(text, const ['家务', '厨房', '垃圾', '清洁', '收拾', '收纳', '房间'])) {
      _addTag(item, '家务');
    }
  }

  void _applyWhen(DraftItem item, String text) {
    if (item.when.kind != DraftWhenKind.none) return;
    if (text.contains('今晚') || text.contains('今天晚上')) {
      item.when = const DraftWhen(DraftWhenKind.evening);
      return;
    }
    if (text.contains('今天')) {
      item.when = const DraftWhen(DraftWhenKind.today);
      return;
    }
    if (text.contains('明天')) {
      item.when = DraftWhen(
        DraftWhenKind.date,
        date: _dateOnly(ctx.now.add(const Duration(days: 1))),
      );
      return;
    }
    if (text.contains('下周一') || text.contains('下周')) {
      item.when = DraftWhen(DraftWhenKind.date, date: _nextWeekday(1));
      return;
    }
    final weekday = _mentionedWeekday(text);
    if (weekday != null) {
      item.when = DraftWhen(DraftWhenKind.date, date: _nextWeekday(weekday));
      return;
    }
    if (text.contains('下个月')) {
      item.when = DraftWhen(DraftWhenKind.date, date: _firstDayOfNextMonth());
      return;
    }
    if (_hasAny(text, const ['有空', '某天', '以后', '回头', '之后'])) {
      item.when = const DraftWhen(DraftWhenKind.someday);
    }
  }

  void _applyDeadline(DraftItem item, String text) {
    if (item.deadline != null) return;
    if (!_hasAny(text, const ['前', '之前', '截止', 'deadline'])) return;

    final monthDay = _monthDay(text);
    if (monthDay != null) {
      item.deadline = monthDay;
      return;
    }
    if (text.contains('周末前')) {
      item.deadline = _nextWeekday(7);
      return;
    }
    final weekday = _mentionedWeekday(text);
    if (weekday != null) {
      item.deadline = _nextWeekday(weekday);
      return;
    }
    if (text.contains('明天')) {
      item.deadline = _dateOnly(ctx.now.add(const Duration(days: 1)));
      return;
    }
    if (text.contains('今天')) {
      item.deadline = _dateOnly(ctx.now);
    }
  }

  void _polishTitle(DraftItem item, String text) {
    final original = item.title.trim();
    if (original.isEmpty) return;

    if (text.contains('王总') &&
        text.contains('方案') &&
        _hasAny(text, const ['那个', '给他', '得给'])) {
      item.title = text.contains('ai') ? '把 AI 配置方案发给王总' : '把方案发给王总';
      return;
    }
    if (text.contains('周会') && text.contains('捋一版')) {
      item.title = '整理产品周会材料初稿';
      return;
    }
    if (text.contains('旅行') && text.contains('证件') && text.contains('缺')) {
      item.title = '检查旅行证件材料缺口';
      return;
    }
    if (_hasAny(text, const ['ai key', 'apikey', 'key']) &&
        _hasAny(text, const ['测', '测试', '能跑'])) {
      item.title = '测试 AI Key 是否可用';
      return;
    }

    var title = original
        .replaceAll(RegExp(r'那个啥|这个|那个|这块'), '')
        .replaceAll(RegExp(r'我得|得|一下|先'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (title.isNotEmpty) item.title = title;
  }

  void _addTag(DraftItem item, String name, {bool requireExisting = true}) {
    final resolved = _tagName(name);
    if (resolved == null && requireExisting) return;
    final tag = resolved ?? name;
    if (item.tagNames.any((existing) => _same(existing, tag))) return;
    item.tagNames.add(tag);
  }

  bool _isDangerousDestructive(String text) {
    return _hasAny(text, const ['删掉', '删除', '清空', '重置']) &&
        _hasAny(text, const ['所有', '全部', '旧任务', '历史任务', '已有任务']);
  }

  bool _isHighlyVague(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    if (compact.length <= 4 && _hasAny(compact, const ['安排', '处理', '弄一下'])) {
      return true;
    }
    return _hasAny(compact, const [
      '回头处理一下',
      '这个别忘了',
      '那个事',
      '安排一下',
      '帮我弄一下',
      '跟他说一下',
      '周末弄一下',
      '最近脑子很乱',
    ]);
  }

  bool _isVagueTitle(String title) {
    final text = _norm(title);
    return text.isEmpty ||
        _hasAny(text, const ['处理一下', '弄一下', '看看那个', '这个别忘了', '那个事']);
  }

  List<String> _vagueSuggestions(String text) {
    if (text.contains('脑子') || text.contains('乱')) {
      return const ['整理收件箱', '列出最近担心的事', '先建一个清单'];
    }
    return const ['补充具体对象', '先记到收件箱', '改成一个动作'];
  }

  DateTime? _monthDay(String text) {
    final match = RegExp(
      r'(\d{1,2})\s*月\s*(\d{1,2})\s*(日|号)?',
    ).firstMatch(text);
    if (match == null) return null;
    final month = int.tryParse(match.group(1)!);
    final day = int.tryParse(match.group(2)!);
    if (month == null || day == null) return null;
    var date = DateTime(ctx.now.year, month, day);
    if (date.isBefore(_dateOnly(ctx.now))) {
      date = DateTime(ctx.now.year + 1, month, day);
    }
    return date;
  }

  DateTime _firstDayOfNextMonth() {
    return ctx.now.month == 12
        ? DateTime(ctx.now.year + 1, 1, 1)
        : DateTime(ctx.now.year, ctx.now.month + 1, 1);
  }

  DateTime _nextWeekday(int weekday) {
    var delta = weekday - ctx.now.weekday;
    if (delta <= 0) delta += 7;
    return _dateOnly(ctx.now.add(Duration(days: delta)));
  }

  int? _mentionedWeekday(String text) {
    final match = RegExp(r'周([一二三四五六日天])').firstMatch(text);
    if (match == null) return null;
    switch (match.group(1)) {
      case '一':
        return 1;
      case '二':
        return 2;
      case '三':
        return 3;
      case '四':
        return 4;
      case '五':
        return 5;
      case '六':
        return 6;
      case '日':
      case '天':
        return 7;
    }
    return null;
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _hasProject(String name) => _projectName(name) != null;

  String? _projectName(String name) {
    for (final project in ctx.projectNames) {
      if (_same(project, name)) return project;
    }
    return null;
  }

  bool _hasArea(String name) => _areaName(name) != null;

  String? _areaName(String name) {
    for (final area in ctx.areaNames) {
      if (_same(area, name)) return area;
    }
    return null;
  }

  String? _tagName(String name) {
    for (final tag in ctx.tagNames) {
      if (_same(tag, name)) return tag;
    }
    return null;
  }

  bool _hasAny(String text, List<String> words) {
    return words.any((word) => text.contains(_norm(word)));
  }

  bool _same(String a, String b) => _norm(a) == _norm(b);

  String _norm(String value) {
    return value
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .replaceAll('-', '')
        .trim();
  }
}
