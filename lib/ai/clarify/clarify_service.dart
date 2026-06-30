import 'dart:convert';

import '../../domain/models/item.dart';
import '../capture/capture_draft.dart';
import '../capture/capture_parser.dart' show CaptureContext;
import '../core/llm_client.dart';
import '../core/llm_message.dart';
import 'clarify_models.dart';

/// 「AI 理清」核心：一个很懂 GTD 的教练，帮用户把任意成熟度的念头理清成
/// 可执行的结构化条目；模糊时先追问，不替用户拍板。
///
/// 仅依赖抽象的 [LlmClient]，与具体模型无关。
class ClarifyService {
  final LlmClient client;
  const ClarifyService(this.client);

  bool get isAvailable => client.isConfigured;

  /// 理清一条输入。[answers] 为用户对上一轮追问的回答；带上后模型应给出最终建议。
  Future<ClarifyResult> clarify(
    String input,
    CaptureContext ctx, {
    List<ClarifyAnswer> answers = const [],
  }) async {
    final raw = input.trim();
    if (raw.isEmpty) {
      return ClarifyResult(source: input, clear: false);
    }

    final reply = await client.complete(
      [
        LlmMessage.system(_systemPrompt(ctx)),
        LlmMessage.user(_userContent(raw, answers)),
      ],
      jsonMode: true,
      temperature: 0.3,
    );

    return _decode(reply, raw);
  }

  // ----------------------------------------------------------------
  // Prompt
  // ----------------------------------------------------------------

  String _userContent(String input, List<ClarifyAnswer> answers) {
    if (answers.isEmpty) return input;
    final sb = StringBuffer()
      ..writeln('原始想法：$input')
      ..writeln('我的补充回答：');
    for (final a in answers) {
      sb.writeln('- ${a.question} → ${a.answer}');
    }
    sb.writeln('请据此给出最终的结构化建议（clear=true，不要再追问）。');
    return sb.toString();
  }

  String _systemPrompt(CaptureContext ctx) {
    final today = _ymd(ctx.now);
    final weekday = ['一', '二', '三', '四', '五', '六', '日'][ctx.now.weekday - 1];
    final projects = ctx.projectNames.isEmpty ? '（无）' : ctx.projectNames.join('、');
    final areas = ctx.areaNames.isEmpty ? '（无）' : ctx.areaNames.join('、');
    final tags = ctx.tagNames.isEmpty ? '（无）' : ctx.tagNames.join('、');

    return '''
你是一个深谙 GTD（Getting Things Done）方法论的「理清教练」。用户会给你一条收件箱里的
念头（可能非常模糊，时间/动作/归属都不确定）。你的任务是帮他把它理清成「可执行的下一步」，
并**只输出 JSON**（不要解释、不要 markdown 代码块）。

今天是 $today（周$weekday）。所有相对日期都基于今天计算。
已有项目：$projects
已有领域：$areas
已有标签：$tags

理清的判断顺序（GTD 思维）：
1. 它是「可行动的」吗？如果是模糊愿望（如"学日语"、"研究X"），它通常是一个**项目**，
   需要先问清「期望结果是什么」「下一步具体动作是什么」。
2. 如果信息不足以确定「下一步具体动作」，则 clear=false，提出 1~2 个最关键的澄清问题，
   每个问题尽量给 2~3 个快捷选项，帮用户快速选择。
3. 如果已足够清晰（或用户已补充回答），clear=true，给出 suggestion，
   其中 title 必须是**动词开头、立刻能做的一步**（例如把"拍笔记"理清成"用手机拍下今天的工作笔记并存入相册"）。

输出 JSON 结构（严格遵守字段名）：
{
  "clear": true 或 false,
  "confidence": 0.0 到 1.0 之间的小数,
  "note": "一句话点评：为什么模糊 / 你的理清思路",
  "outcome": "期望结果，一句话（可为 null）",
  "questions": [
    { "q": "澄清问题", "options": ["选项1", "选项2", "选项3"] }
  ],
  "suggestion": {
    "title": "动词开头的下一步行动",
    "type": "task" 或 "project",
    "when": "none" | "today" | "evening" | "someday" | "YYYY-MM-DD",
    "deadline": null 或 "YYYY-MM-DD",
    "tags": ["标签名"],
    "list": null | "inbox" | "已有项目或领域名",
    "children": ["子步骤1", "子步骤2"]
  }
}

规则：
- clear=false 时，questions 至少 1 个、至多 2 个；suggestion 可给初步猜测。
- clear=true 时，questions 应为空数组。
- 若判断这是一个需要多步推进的目标，type=project，并把可拆出的步骤放进 children。
- 若是一条普通任务但有检查点，type=task，children 作为检查项。
- tags / list 优先匹配「已有」列表里的名字；匹配不到可提新名字，但要克制。

关于「何时(when)」与「死线(deadline)」——这是两件不同的事，务必分清：
- when 表示“打算什么时候去做”。只有当用户明确表达了执行时间（如“今天/今晚/明天/这周末/某月某日”）才设置对应值；
  仅仅“想做/想开始/该学了”这类愿望不等于今天，这种一律 when=none，绝不臆测成 today。
- deadline 表示“最晚必须完成的时间”。当出现死线语义时必须解析成具体日期填入 deadline：
  例如“周五前/X 之前/截止/deadline/最晚/赶在…前/前交”。相对日期（如“周五”“下周三”）要基于今天推算成 YYYY-MM-DD。
  例：“周五下午3点前把报告发给老板” → deadline = 本周五的日期（when 可为 none）。
- 二者都不确定时才用 none / null，但绝不要漏掉已明确说出的死线，也不要编造没有依据的日期。
- 若判断这是“无具体行动的长期愿望/将来也许做”，可在 note 里说明并建议 when=someday；普通可执行任务不要轻易丢进 someday。
''';
  }

  // ----------------------------------------------------------------
  // 解析
  // ----------------------------------------------------------------

  ClarifyResult _decode(String reply, String source) {
    final jsonStr = _extractJson(reply);
    if (jsonStr == null) {
      return ClarifyResult(
        source: source,
        clear: true,
        confidence: 0.3,
        suggestion: DraftItem(title: source),
      );
    }

    Map<String, dynamic> map;
    try {
      map = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return ClarifyResult(
        source: source,
        clear: true,
        confidence: 0.3,
        suggestion: DraftItem(title: source),
      );
    }

    final clear = map['clear'] == true;
    final confidence = _toDouble(map['confidence']);
    final note = _nonEmpty(map['note']);
    final outcome = _nonEmpty(map['outcome']);

    final questions = <ClarifyQuestion>[];
    if (map['questions'] is List) {
      for (final q in map['questions']) {
        if (q is Map && q['q'] is String) {
          final opts = <String>[];
          if (q['options'] is List) {
            for (final o in q['options']) {
              if (o is String && o.trim().isNotEmpty) opts.add(o.trim());
            }
          }
          questions.add(ClarifyQuestion(
              question: (q['q'] as String).trim(), options: opts));
        }
      }
    }

    DraftItem? suggestion;
    if (map['suggestion'] is Map) {
      suggestion = _decodeItem(map['suggestion'] as Map);
    }
    suggestion ??= DraftItem(title: source);

    return ClarifyResult(
      source: source,
      clear: clear,
      confidence: confidence,
      note: note,
      outcome: outcome,
      questions: clear ? const [] : questions,
      suggestion: suggestion,
    );
  }

  DraftItem? _decodeItem(Map raw) {
    final title = (raw['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;

    final type = (raw['type'] == 'project') ? ItemType.project : ItemType.task;

    final tags = <String>[];
    if (raw['tags'] is List) {
      for (final t in raw['tags']) {
        if (t is String && t.trim().isNotEmpty) tags.add(t.trim());
      }
    }

    String? listName;
    final list = raw['list'];
    if (list is String && list.trim().isNotEmpty && list != 'null') {
      listName = list.trim().toLowerCase() == 'inbox'
          ? DraftItem.inboxToken
          : list.trim();
    }

    final children = <DraftChild>[];
    if (raw['children'] is List) {
      for (final c in raw['children']) {
        if (c is String && c.trim().isNotEmpty) {
          children.add(DraftChild(title: c.trim()));
        } else if (c is Map && c['title'] is String) {
          children.add(DraftChild(title: (c['title'] as String).trim()));
        }
      }
    }

    return DraftItem(
      title: title,
      type: type,
      when: _decodeWhen(raw['when']),
      deadline: _decodeDate(raw['deadline']),
      tagNames: tags,
      listName: listName,
      children: children,
    );
  }

  DraftWhen _decodeWhen(Object? raw) {
    if (raw is! String) return DraftWhen.none;
    switch (raw) {
      case 'today':
        return const DraftWhen(DraftWhenKind.today);
      case 'evening':
        return const DraftWhen(DraftWhenKind.evening);
      case 'someday':
        return const DraftWhen(DraftWhenKind.someday);
      case 'none':
      case '':
        return DraftWhen.none;
      default:
        final d = _decodeDate(raw);
        return d == null ? DraftWhen.none : DraftWhen(DraftWhenKind.date, date: d);
    }
  }

  DateTime? _decodeDate(Object? raw) {
    if (raw is! String || raw.isEmpty || raw == 'null') return null;
    final d = DateTime.tryParse(raw);
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  double _toDouble(Object? raw) {
    if (raw is num) return raw.toDouble().clamp(0, 1);
    if (raw is String) return (double.tryParse(raw) ?? 0).clamp(0, 1);
    return 0;
  }

  String? _nonEmpty(Object? raw) {
    if (raw is String && raw.trim().isNotEmpty && raw.trim() != 'null') {
      return raw.trim();
    }
    return null;
  }

  String? _extractJson(String reply) {
    final start = reply.indexOf('{');
    final end = reply.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return reply.substring(start, end + 1);
  }

  static String _ymd(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}
