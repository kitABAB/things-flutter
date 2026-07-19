import '../core/llm_client.dart';
import '../core/llm_message.dart';
import 'capture_draft.dart';
import 'capture_draft_codec.dart';

/// 解析时提供给模型的语境：当前日期 + 已有的项目/领域/标签名，
/// 让模型尽量把条目挂到「已存在」的清单与标签上，而不是凭空造新名字。
class CaptureContext {
  final DateTime now;
  final List<String> projectNames;
  final List<String> areaNames;
  final List<String> tagNames;

  const CaptureContext({
    required this.now,
    this.projectNames = const [],
    this.areaNames = const [],
    this.tagNames = const [],
  });
}

/// 「一句话拆解捕获」的核心：把自然语言整理成结构化的 [CaptureDraft]。
///
/// 它只依赖抽象的 [LlmClient]，因此与具体模型无关。
class CaptureParser {
  final LlmClient client;
  const CaptureParser(this.client);

  bool get isAvailable => client.isConfigured;

  Future<CaptureDraft> parse(String input, CaptureContext ctx) async {
    final raw = input.trim();
    if (raw.isEmpty) {
      return CaptureDraft(source: input, items: []);
    }

    final reply = await client.complete([
      LlmMessage.system(_systemPrompt(ctx)),
      LlmMessage.user(raw),
    ], jsonMode: true);

    return CaptureDraftCodec.decodeReply(reply, raw);
  }

  // ----------------------------------------------------------------
  // Prompt
  // ----------------------------------------------------------------

  String _systemPrompt(CaptureContext ctx) {
    final today = _ymd(ctx.now);
    final weekday = ['一', '二', '三', '四', '五', '六', '日'][ctx.now.weekday - 1];
    final projects = ctx.projectNames.isEmpty
        ? '（无）'
        : ctx.projectNames.join('、');
    final areas = ctx.areaNames.isEmpty ? '（无）' : ctx.areaNames.join('、');
    final tags = ctx.tagNames.isEmpty ? '（无）' : ctx.tagNames.join('、');

    return '''
你是一个 GTD 任务管理 App 的「捕获解析器」。用户会输入一句话或一段文字，
你要把它整理成结构化的待办，并**只输出 JSON**（不要任何解释、不要 markdown 代码块）。

今天是 $today（周$weekday）。所有相对日期都基于今天计算。
已有项目：$projects
已有领域：$areas
已有标签：$tags

输出 JSON 结构（严格遵守字段名）：
{
  "items": [
    {
      "title": "条目标题（去掉日期/标签等已被抽取的修饰词，保持简洁）",
      "type": "task" 或 "project",
      "when": "none" | "today" | "evening" | "someday" | "YYYY-MM-DD",
      "deadline": null | "YYYY-MM-DD",
      "tags": ["标签名", ...],
      "list": null | "inbox" | "已有项目或领域的名字",
      "children": ["子项标题", ...]
    }
  ]
}

判定规则：
- 默认 type=task。只有当输入明显是一个「需要多步骤完成的目标」时才用 project，
  并把可拆出的步骤放进 children（此时 children 是该项目下的任务）。
- 若是一条普通任务但提到几个检查点，可把检查点放进 children（此时是检查项）。
- when：明确说了某天就用 YYYY-MM-DD；"今天/今晚/将来"用对应枚举；没提就 none。
- deadline 仅在出现"截止/deadline/之前/前交"等明确死线语义时才填。
- tags / list 优先匹配上面「已有」列表里的名字；匹配不到也可以提出新名字，但要克制。
- 不确定的字段一律用 none / null / 空数组，绝不编造日期。
- 通常只产出 1 个顶层 item；只有输入里确实包含多件独立的事时才产出多个。
''';
  }

  static String _ymd(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}
