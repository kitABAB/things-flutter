import 'package:flutter_test/flutter_test.dart';
import 'package:things3_clone/ai/agent/capture_agent.dart';
import 'package:things3_clone/ai/capture/capture_draft.dart';
import 'package:things3_clone/ai/capture/capture_parser.dart'
    show CaptureContext;
import 'package:things3_clone/ai/core/llm_client.dart';
import 'package:things3_clone/ai/core/llm_message.dart';
import 'package:things3_clone/domain/models/item.dart';

class FakeLlmClient implements LlmClient {
  final List<String> replies;
  final bool configured;
  final calls = <List<LlmMessage>>[];
  int _index = 0;

  FakeLlmClient(this.replies, {this.configured = true});

  @override
  bool get isConfigured => configured;

  @override
  Future<String> complete(
    List<LlmMessage> messages, {
    bool jsonMode = false,
    double temperature = 0.2,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    calls.add(messages);
    final reply = replies[_index.clamp(0, replies.length - 1)];
    _index += 1;
    return reply;
  }

  @override
  Future<List<String>> listModels({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return const [];
  }
}

void main() {
  final ctx = CaptureContext(
    now: DateTime(2026, 7, 19),
    projectNames: const ['产品周会'],
    areaNames: const ['学习'],
    tagNames: const ['AI'],
  );
  final richCtx = CaptureContext(
    now: DateTime(2026, 7, 19),
    projectNames: const ['AI 配置', '产品周会', '搬家', '日本旅行'],
    areaNames: const ['工作', '学习', '生活', '健康'],
    tagNames: const ['AI', '沟通', '日语', '会议', '采购', '运动', '家务'],
  );

  test('Agent 通过 replace_drafts 工具生成待创建项', () async {
    const reply = '''
    {
      "tool_calls": [
        {
          "name": "replace_drafts",
          "arguments": {
            "items": [
              {
                "title": "给王总发 AI 配置方案",
                "type": "task",
                "when": "today",
                "deadline": null,
                "tags": ["AI"],
                "list": "inbox",
                "children": []
              }
            ]
          }
        }
      ],
      "final": {"message": "已整理出 1 项。", "suggestions": []}
    }
    ''';

    final agent = CaptureAgent(FakeLlmClient([reply]));
    final result = await agent.run(latest: '今天给王总发 AI 配置方案', context: ctx);

    expect(result.message, '已整理出 1 项。');
    expect(result.draft.items, hasLength(1));
    expect(result.draft.items.first.title, '给王总发 AI 配置方案');
    expect(result.draft.items.first.when.kind, DraftWhenKind.today);
    expect(result.draft.items.first.listName, DraftItem.inboxToken);
  });

  test('Agent 通过工具修改当前工作区，不重复创建同义项', () async {
    const reply = '''
    {
      "tool_calls": [
        {"name": "remove_draft", "arguments": {"index": 2}},
        {
          "name": "update_draft",
          "arguments": {"index": 1, "patch": {"when": "today"}}
        }
      ],
      "final": {"message": "已更新待创建项。", "suggestions": []}
    }
    ''';

    final current = CaptureDraft(
      source: 'current',
      items: [
        DraftItem(title: '买机票'),
        DraftItem(title: '订酒店'),
      ],
    );

    final agent = CaptureAgent(FakeLlmClient([reply]));
    final result = await agent.run(
      latest: '第二个不要建，第一个放今天',
      context: ctx,
      currentDraft: current,
    );

    expect(result.draft.items, hasLength(1));
    expect(result.draft.items.first.title, '买机票');
    expect(result.draft.items.first.when.kind, DraftWhenKind.today);
  });

  test('Agent 可以追问并返回 chips，不产生待创建项', () async {
    const reply = '''
    {
      "tool_calls": [
        {
          "name": "ask_user",
          "arguments": {
            "message": "你学日语主要为了什么？",
            "suggestions": ["旅行能交流", "考试", "先随便学"]
          }
        }
      ]
    }
    ''';

    final fake = FakeLlmClient([reply]);
    final agent = CaptureAgent(fake);
    final result = await agent.run(latest: '想开始学日语', context: ctx);

    expect(fake.calls, hasLength(1));
    expect(result.needsUser, isTrue);
    expect(result.message, '你学日语主要为了什么？');
    expect(result.suggestions, ['旅行能交流', '考试', '先随便学']);
    expect(result.draft.items, isEmpty);
  });

  test('Agent 兼容旧 items JSON 输出', () async {
    const reply = '''
    {
      "items": [
        {
          "title": "准备产品周会",
          "type": "project",
          "when": "2026-07-20",
          "deadline": null,
          "tags": [],
          "list": "产品周会",
          "children": ["整理议题", "确认参会人"]
        }
      ]
    }
    ''';

    final agent = CaptureAgent(FakeLlmClient([reply]));
    final result = await agent.run(latest: '下周准备产品周会', context: ctx);

    expect(result.draft.items.single.type, ItemType.project);
    expect(result.draft.items.single.children, hasLength(2));
    expect(result.message, '已整理出 3 项。');
  });

  test('Agent 保留模型明确建议的新领域', () async {
    const reply = '''
    {
      "tool_calls": [
        {
          "name": "replace_drafts",
          "arguments": {
            "items": [
              {
                "title": "制定跑步训练计划",
                "type": "task",
                "when": "none",
                "deadline": null,
                "tags": ["跑步"],
                "list": {"type": "new_area", "name": "健康"},
                "children": []
              }
            ]
          }
        }
      ],
      "final": {"message": "已整理出 1 项。", "suggestions": []}
    }
    ''';

    final agent = CaptureAgent(FakeLlmClient([reply]));
    final result = await agent.run(latest: '研究跑步训练体系', context: ctx);

    expect(result.draft.items.single.listName, '健康');
    expect(result.draft.items.single.listKind, DraftListKind.newArea);
    expect(result.draft.items.single.tagNames, ['跑步']);
  });

  test('Agent 保留已有领域、标签和美化后的标题', () async {
    const reply = '''
    {
      "tool_calls": [
        {
          "name": "replace_drafts",
          "arguments": {
            "items": [
              {
                "title": "整理 AI 配置方案并发给王总",
                "type": "task",
                "when": "today",
                "deadline": null,
                "tags": ["AI"],
                "list": "学习",
                "children": []
              }
            ]
          }
        }
      ],
      "final": {"message": "已创建 1 项。", "suggestions": []}
    }
    ''';

    final agent = CaptureAgent(FakeLlmClient([reply]));
    final result = await agent.run(latest: '王总那个 AI 配置今天发一下', context: ctx);

    final item = result.draft.items.single;
    expect(result.message, '已整理出 1 项。');
    expect(item.title, '整理 AI 配置方案并发给王总');
    expect(item.listName, '学习');
    expect(item.listKind, isNull);
    expect(item.tagNames, ['AI']);
    expect(item.when.kind, DraftWhenKind.today);
  });

  test('Agent 保留模型明确建议的新项目', () async {
    const reply = '''
    {
      "tool_calls": [
        {
          "name": "replace_drafts",
          "arguments": {
            "items": [
              {
                "title": "确认搬家公司报价",
                "type": "task",
                "when": "none",
                "deadline": null,
                "tags": ["搬家"],
                "list": {"type": "new_project", "name": "搬家"},
                "children": []
              }
            ]
          }
        }
      ],
      "final": {"message": "已整理出 1 项。", "suggestions": []}
    }
    ''';

    final agent = CaptureAgent(FakeLlmClient([reply]));
    final result = await agent.run(latest: '搬家这周找报价', context: ctx);

    expect(result.draft.items.single.listName, '搬家');
    expect(result.draft.items.single.listKind, DraftListKind.newProject);
    expect(result.draft.items.single.tagNames, ['搬家']);
  });

  test('Agent 对不明确归属保持收件箱', () async {
    const reply = '''
    {
      "tool_calls": [
        {
          "name": "replace_drafts",
          "arguments": {
            "items": [
              {
                "title": "买牛奶",
                "type": "task",
                "when": "none",
                "deadline": null,
                "tags": [],
                "list": "inbox",
                "children": []
              }
            ]
          }
        }
      ],
      "final": {"message": "已整理出 1 项。", "suggestions": []}
    }
    ''';

    final agent = CaptureAgent(FakeLlmClient([reply]));
    final result = await agent.run(latest: '买牛奶', context: ctx);

    expect(result.draft.items.single.listName, DraftItem.inboxToken);
    expect(result.draft.items.single.listKind, isNull);
  });

  test('Agent 后处理会把强信号归属到已有项目并补时间标签', () async {
    const reply = '''
    {
      "tool_calls": [
        {
          "name": "replace_drafts",
          "arguments": {
            "items": [
              {
                "title": "提交产品周会复盘",
                "type": "task",
                "when": "none",
                "deadline": null,
                "tags": [],
                "list": "inbox",
                "children": []
              }
            ]
          }
        }
      ],
      "final": {"message": "已整理出 1 项。", "suggestions": []}
    }
    ''';

    final result = await CaptureAgent(
      FakeLlmClient([reply]),
    ).run(latest: '下周提交产品周会复盘', context: richCtx);

    final item = result.draft.items.single;
    expect(item.listName, '产品周会');
    expect(item.when.kind, DraftWhenKind.date);
    expect(item.when.date, DateTime(2026, 7, 20));
    expect(item.tagNames, contains('会议'));
  });

  test('Agent 后处理会识别 deadline 和已有旅行项目', () async {
    const reply = '''
    {
      "tool_calls": [
        {
          "name": "replace_drafts",
          "arguments": {
            "items": [
              {
                "title": "搞定签证材料",
                "type": "task",
                "when": "none",
                "deadline": null,
                "tags": [],
                "list": "inbox",
                "children": []
              }
            ]
          }
        }
      ],
      "final": {"message": "已整理出 1 项。", "suggestions": []}
    }
    ''';

    final result = await CaptureAgent(
      FakeLlmClient([reply]),
    ).run(latest: '8 月 1 日之前搞定签证材料', context: richCtx);

    final item = result.draft.items.single;
    expect(item.listName, '日本旅行');
    expect(item.deadline, DateTime(2026, 8, 1));
  });

  test('Agent 后处理会把高度模糊输入转成追问', () async {
    const reply = '''
    {
      "tool_calls": [
        {
          "name": "replace_drafts",
          "arguments": {
            "items": [
              {
                "title": "处理一下",
                "type": "task",
                "when": "none",
                "deadline": null,
                "tags": [],
                "list": "inbox",
                "children": []
              }
            ]
          }
        }
      ],
      "final": {"message": "已整理出 1 项。", "suggestions": []}
    }
    ''';

    final result = await CaptureAgent(
      FakeLlmClient([reply]),
    ).run(latest: '回头处理一下', context: richCtx);

    expect(result.needsUser, isTrue);
    expect(result.draft.items, isEmpty);
    expect(result.suggestions, contains('补充具体对象'));
  });

  test('Agent 后处理会清理口语标题并补充日期和沟通标签', () async {
    const reply = '''
    {
      "tool_calls": [
        {
          "name": "replace_drafts",
          "arguments": {
            "items": [
              {
                "title": "王总那个方案今天得给他一下",
                "type": "task",
                "when": "none",
                "deadline": null,
                "tags": [],
                "list": "inbox",
                "children": []
              }
            ]
          }
        }
      ],
      "final": {"message": "已整理出 1 项。", "suggestions": []}
    }
    ''';

    final result = await CaptureAgent(
      FakeLlmClient([reply]),
    ).run(latest: '王总那个方案今天得给他一下', context: richCtx);

    final item = result.draft.items.single;
    expect(item.title, '把方案发给王总');
    expect(item.when.kind, DraftWhenKind.today);
    expect(item.tagNames, contains('沟通'));
  });

  test('Agent 提示词包含内置分配与美化约束', () async {
    const reply = '''
    {
      "tool_calls": [
        {
          "name": "replace_drafts",
          "arguments": {
            "items": [
              {
                "title": "买牛奶",
                "type": "task",
                "when": "none",
                "deadline": null,
                "tags": [],
                "list": "inbox",
                "children": []
              }
            ]
          }
        }
      ],
      "final": {"message": "已整理出 1 项。", "suggestions": []}
    }
    ''';

    final fake = FakeLlmClient([reply]);
    final agent = CaptureAgent(fake);
    await agent.run(latest: '买牛奶', context: ctx);

    final systemPrompt = fake.calls.single.first.content;
    expect(systemPrompt, contains('内置核心能力'));
    expect(systemPrompt, contains('不要偷懒把所有任务都丢进 inbox'));
    expect(systemPrompt, contains('保持 inbox'));
    expect(systemPrompt, contains('标题要简洁、中文优先、动词开头'));
    expect(systemPrompt, contains('模型/key/网关'));
    expect(systemPrompt, contains('高度模糊输入优先追问'));
    expect(systemPrompt, contains('口语和语音转写要去掉填充词'));
  });
}
