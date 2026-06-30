import 'package:flutter_test/flutter_test.dart';

import 'package:things3_clone/ai/capture/capture_draft.dart';
import 'package:things3_clone/ai/capture/capture_parser.dart' show CaptureContext;
import 'package:things3_clone/ai/clarify/clarify_models.dart';
import 'package:things3_clone/ai/clarify/clarify_service.dart';
import 'package:things3_clone/ai/core/llm_client.dart';
import 'package:things3_clone/ai/core/llm_message.dart';
import 'package:things3_clone/ai/review/review_models.dart';
import 'package:things3_clone/ai/review/review_service.dart';
import 'package:things3_clone/domain/models/item.dart';

/// 可编排的假 LLM 客户端：按需返回固定文本，或标记为未配置。
class FakeLlmClient implements LlmClient {
  final String reply;
  final bool configured;
  List<LlmMessage>? lastMessages;

  FakeLlmClient({this.reply = '', this.configured = true});

  @override
  bool get isConfigured => configured;

  @override
  Future<String> complete(
    List<LlmMessage> messages, {
    bool jsonMode = false,
    double temperature = 0.2,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    lastMessages = messages;
    return reply;
  }

  @override
  Future<List<String>> listModels({
    Duration timeout = const Duration(seconds: 15),
  }) async =>
      const [];
}

Item _task({
  required String id,
  String title = 't',
  WhenStart start = WhenStart.anytime,
  DateTime? startDate,
  String? projectId,
  String? areaId,
  DateTime? createdAt,
}) {
  final now = DateTime.now();
  return Item(
    id: id,
    userId: 'u',
    type: ItemType.task,
    title: title,
    start: start,
    startDate: startDate,
    projectId: projectId,
    areaId: areaId,
    createdAt: createdAt ?? now,
    updatedAt: now,
  );
}

Item _project({required String id, String title = 'p', DateTime? createdAt}) {
  final now = DateTime.now();
  return Item(
    id: id,
    userId: 'u',
    type: ItemType.project,
    title: title,
    start: WhenStart.anytime,
    createdAt: createdAt ?? now,
    updatedAt: now,
  );
}

void main() {
  final ctx = CaptureContext(now: DateTime(2026, 6, 25));

  group('ClarifyService', () {
    test('模糊条目：返回 clear=false 且带追问', () async {
      const json = '''
      {
        "clear": false,
        "confidence": 0.4,
        "note": "学日语是个目标，需要先定下一步",
        "outcome": "能进行日常日语对话",
        "questions": [
          {"q": "你想达到什么程度？", "options": ["入门", "能对话", "考级"]}
        ],
        "suggestion": {"title": "学日语", "type": "project"}
      }
      ''';
      final svc = ClarifyService(FakeLlmClient(reply: json));
      final r = await svc.clarify('学日语', ctx);

      expect(r.clear, false);
      expect(r.hasQuestions, true);
      expect(r.questions.first.options, contains('能对话'));
      expect(r.autoApplicable, false);
      expect(r.outcome, '能进行日常日语对话');
    });

    test('清晰条目：解析出项目 + 子任务 + 今天 + 标签', () async {
      const json = '''
      {
        "clear": true,
        "confidence": 0.9,
        "note": "已是可执行的一步",
        "suggestion": {
          "title": "整理本周工作笔记",
          "type": "project",
          "when": "today",
          "tags": ["工作"],
          "list": "inbox",
          "children": ["拍下纸质笔记", "录入要点"]
        }
      }
      ''';
      final svc = ClarifyService(FakeLlmClient(reply: json));
      final r = await svc.clarify('拍笔记', ctx);

      expect(r.clear, true);
      expect(r.hasQuestions, false);
      expect(r.autoApplicable, true); // clear + 0.9 + 有建议
      final s = r.suggestion!;
      expect(s.title, '整理本周工作笔记');
      expect(s.type, ItemType.project);
      expect(s.when.kind, DraftWhenKind.today);
      expect(s.tagNames, contains('工作'));
      expect(s.listName, DraftItem.inboxToken);
      expect(s.children.length, 2);
    });

    test('携带回答时把问答写进发给模型的内容', () async {
      final fake = FakeLlmClient(reply: '{"clear":true,"suggestion":{"title":"x"}}');
      final svc = ClarifyService(fake);
      await svc.clarify('学日语', ctx,
          answers: const [ClarifyAnswer('你想达到什么程度？', '能对话')]);

      final user = fake.lastMessages!.last.content;
      expect(user, contains('能对话'));
      expect(user, contains('最终的结构化建议'));
    });

    test('模型返回非 JSON 时优雅降级为单条', () async {
      final svc = ClarifyService(FakeLlmClient(reply: '抱歉我不会'));
      final r = await svc.clarify('随便写点', ctx);
      expect(r.suggestion!.title, '随便写点');
    });
  });

  group('ReviewService', () {
    test('按 GTD 维度正确分类', () async {
      final old = DateTime.now().subtract(const Duration(days: 30));
      final recent = DateTime.now().subtract(const Duration(days: 2));

      final active = <Item>[
        // 1. 收件箱
        _task(id: 'inbox1', start: WhenStart.inbox, title: '一个念头'),
        // 2. 孵化到期（someday + 旧）
        _task(id: 'some_old', start: WhenStart.someday, createdAt: old),
        // someday 但新 → 不计
        _task(id: 'some_new', start: WhenStart.someday, createdAt: recent),
        // 3. 无下一步的项目
        _project(id: 'p_empty', title: '空项目'),
        // 有任务的项目 → 不计；其子任务也不应进停滞
        _project(id: 'p_ok', title: '健康项目'),
        _task(id: 'p_ok_child', projectId: 'p_ok', startDate: null, createdAt: old),
        // 4. 停滞散任务（anytime 无日期 无归属 旧）
        _task(id: 'stalled', start: WhenStart.anytime, createdAt: old),
        // 最近的散任务 → 不计
        _task(id: 'fresh', start: WhenStart.anytime, createdAt: recent),
      ];

      // 未配置 AI：跳过建议，仅本地分类。
      final svc = ReviewService(FakeLlmClient(configured: false));
      final report = await svc.build(active);

      Map<ReviewKind, List<String>> ids = {
        for (final s in report.sections)
          s.kind: s.items.map((e) => e.id).toList()
      };

      expect(ids[ReviewKind.inbox], ['inbox1']);
      expect(ids[ReviewKind.incubation], ['some_old']);
      expect(ids[ReviewKind.projectNoNextAction], ['p_empty']);
      expect(ids[ReviewKind.stalledTask], ['stalled']);
      expect(report.aiAvailable, false);
      expect(report.aiAdvice, isNull);
      expect(report.pendingTotal, 4);
      expect(report.allClear, false);
    });

    test('全部就绪时 allClear=true', () async {
      final svc = ReviewService(FakeLlmClient(configured: false));
      final report = await svc.build([
        _task(id: 'ok', start: WhenStart.anytime, startDate: DateTime.now()),
      ]);
      expect(report.allClear, true);
      expect(report.pendingTotal, 0);
    });

    test('配置 AI 且有待办时附带建议', () async {
      final svc = ReviewService(FakeLlmClient(reply: '先清空收件箱。'));
      final report = await svc.build([
        _task(id: 'inbox1', start: WhenStart.inbox),
      ]);
      expect(report.aiAvailable, true);
      expect(report.aiAdvice, '先清空收件箱。');
    });
  });
}
