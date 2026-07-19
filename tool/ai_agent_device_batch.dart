import 'dart:convert';
import 'dart:io';

import 'package:things3_clone/ai/agent/capture_agent.dart';
import 'package:things3_clone/ai/capture/capture_draft.dart';
import 'package:things3_clone/ai/capture/capture_draft_codec.dart';
import 'package:things3_clone/ai/capture/capture_parser.dart';
import 'package:things3_clone/ai/core/llm_client.dart';
import 'package:things3_clone/ai/core/llm_message.dart';

class CapturingClient implements LlmClient {
  List<LlmMessage> lastMessages = const [];

  @override
  bool get isConfigured => true;

  @override
  Future<String> complete(
    List<LlmMessage> messages, {
    bool jsonMode = false,
    double temperature = 0.2,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    lastMessages = messages;
    return '{"tool_calls":[{"name":"finish","arguments":{"message":"ok","suggestions":[]}}]}';
  }

  @override
  Future<List<String>> listModels({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return const [];
  }
}

class Sample {
  final String id;
  final String category;
  final String ambiguity;
  final String input;
  final String expect;
  final CaptureDraft? currentDraft;

  const Sample({
    required this.id,
    required this.category,
    required this.ambiguity,
    required this.input,
    required this.expect,
    this.currentDraft,
  });
}

Future<void> main(List<String> args) async {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null || apiKey.trim().isEmpty) {
    stderr.writeln('GEMINI_API_KEY is required');
    exit(2);
  }

  final limit = int.tryParse(_argValue(args, '--limit') ?? '') ?? 30;
  final delayMs = int.tryParse(_argValue(args, '--delay-ms') ?? '') ?? 3500;
  final device = _argValue(args, '--device') ?? '192.168.31.97:5555';
  final stopAfter429 =
      int.tryParse(_argValue(args, '--stop-after-429') ?? '') ?? 3;
  final model = _argValue(args, '--model') ?? 'gemini-2.5-flash';
  final fromId = _argValue(args, '--from-id');
  final offset = int.tryParse(_argValue(args, '--offset') ?? '') ?? 0;
  final append = args.contains('--append');
  final baseUrl =
      _argValue(args, '--base-url') ??
      'https://generativelanguage.googleapis.com/v1beta/openai';

  final ctx = CaptureContext(
    now: DateTime(2026, 7, 19),
    projectNames: const ['AI 配置', '产品周会', '搬家', '日本旅行'],
    areaNames: const ['工作', '学习', '生活', '健康'],
    tagNames: const ['AI', '沟通', '日语', '会议', '采购', '运动', '家务'],
  );

  final outDir = Directory('.codex_tmp_agent_device_results');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  final payloadFile = File('${outDir.path}/payload.json');
  final resultsFile = File('${outDir.path}/results.jsonl');
  if (!append && resultsFile.existsSync()) resultsFile.deleteSync();

  var consecutive429 = 0;
  final allSamples = args.contains('--hardcoded')
      ? samples
      : _loadSamplesFromDocs();
  var startIndex = offset.clamp(0, allSamples.length);
  if (fromId != null && fromId.trim().isNotEmpty) {
    final i = allSamples.indexWhere((sample) => sample.id == fromId.trim());
    if (i >= 0) startIndex = i;
  }
  final selected = allSamples.skip(startIndex).take(limit).toList();
  stdout.writeln(
    'Running ${selected.length}/${allSamples.length} samples '
    'from ${selected.isEmpty ? '-' : selected.first.id} '
    'model=$model append=$append',
  );
  for (var i = 0; i < selected.length; i += 1) {
    final sample = selected[i];
    final capture = CapturingClient();
    await CaptureAgent(capture).run(
      latest: sample.input,
      context: ctx,
      currentDraft: sample.currentDraft,
    );
    final body = {
      'model': model,
      'temperature': 0.1,
      'messages': capture.lastMessages.map((m) => m.toJson()).toList(),
      'response_format': {'type': 'json_object'},
    };
    payloadFile.writeAsStringSync(jsonEncode(body));

    final remotePath = '/data/local/tmp/agent_payload_${sample.id}.json';
    final push = await Process.run(
      'adb',
      ['-s', device, 'push', payloadFile.path, remotePath],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (push.exitCode != 0) {
      stderr.writeln('adb push failed: ${push.stderr}');
      exit(push.exitCode);
    }

    final curlCommand = [
      'curl -sS --max-time 90',
      r"-w '\n__HTTP_CODE__:%{http_code}'",
      '-X POST',
      "-H 'Content-Type: application/json'",
      "-H 'Authorization: Bearer ${apiKey.trim()}'",
      "--data-binary '@$remotePath'",
      "'${_trimSlash(baseUrl)}/chat/completions'",
    ].join(' ');
    final resp = await Process.run(
      'adb',
      ['-s', device, 'shell', curlCommand],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    final raw = '${resp.stdout}${resp.stderr}';
    final parsed = _parseCurl(raw);
    final eval = _evaluate(parsed.body);
    final record = {
      'id': sample.id,
      'category': sample.category,
      'ambiguity': sample.ambiguity,
      'input': sample.input,
      'expect': sample.expect,
      'http': parsed.statusCode,
      'ok': resp.exitCode == 0 && parsed.statusCode == 200 && eval.ok,
      'error': resp.exitCode == 0 ? eval.error : 'curl exit ${resp.exitCode}',
      'summary': eval.summary,
      'items': eval.items,
      'askUser': eval.askUser,
      'suggestions': eval.suggestions,
      'rawContent': eval.content,
    };
    resultsFile.writeAsStringSync(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
    );
    stdout.writeln(
      '${i + 1}/${selected.length} ${sample.id} http=${parsed.statusCode} '
      'ok=${record['ok']} ${eval.summary}',
    );

    if (parsed.statusCode == 429) {
      consecutive429 += 1;
      if (consecutive429 >= stopAfter429) {
        stdout.writeln(
          'Stopped after $consecutive429 consecutive 429 responses.',
        );
        break;
      }
    } else {
      consecutive429 = 0;
    }

    if (i + 1 < selected.length) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }

  stdout.writeln('Results: ${resultsFile.path}');
}

List<Sample> _loadSamplesFromDocs() {
  final file = File('docs/AI-CONVERSATIONAL-CAPTURE-DEVICE-TEST-CASES.md');
  if (!file.existsSync()) return samples;
  final parsed = <Sample>[];
  for (final line in file.readAsLinesSync()) {
    if (!line.startsWith('| AI-SAMPLE-')) continue;
    final cells = line.split('|').map((cell) => cell.trim()).toList();
    if (cells.length < 6) continue;
    final id = cells[1];
    final category = cells[2];
    final ambiguity = cells[3];
    final input = cells[4];
    final expect = cells[5];
    parsed.add(
      Sample(
        id: id,
        category: category,
        ambiguity: ambiguity,
        input: input,
        expect: expect,
        currentDraft: category == '当前工作区修改' || id == 'AI-SAMPLE-119'
            ? currentWorkspaceDraft
            : null,
      ),
    );
  }
  return parsed.isEmpty ? samples : parsed;
}

String? _argValue(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}

String _trimSlash(String s) =>
    s.endsWith('/') ? s.substring(0, s.length - 1) : s;

({int statusCode, String body}) _parseCurl(String raw) {
  const marker = '\n__HTTP_CODE__:';
  final i = raw.lastIndexOf(marker);
  if (i < 0) return (statusCode: 0, body: raw);
  final code = int.tryParse(raw.substring(i + marker.length).trim()) ?? 0;
  return (statusCode: code, body: raw.substring(0, i));
}

class Eval {
  final bool ok;
  final String? error;
  final String summary;
  final List<Map<String, Object?>> items;
  final bool askUser;
  final List<String> suggestions;
  final String content;

  const Eval({
    required this.ok,
    this.error,
    required this.summary,
    required this.items,
    required this.askUser,
    required this.suggestions,
    required this.content,
  });
}

Eval _evaluate(String body) {
  try {
    var decoded = jsonDecode(body);
    if (decoded is List && decoded.isNotEmpty) {
      decoded = decoded.first;
    }
    if (decoded is! Map) {
      return _bad('response_not_map', body);
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      return _bad(_errorMessage(decoded) ?? 'no_choices', body);
    }
    final content = choices.first['message']?['content'];
    if (content is! String || content.trim().isEmpty) {
      return _bad('empty_content', body);
    }
    final agentJson = CaptureDraftCodec.extractJson(content);
    if (agentJson == null) return _bad('agent_content_not_json', content);
    final parsed = jsonDecode(agentJson);
    if (parsed is! Map) return _bad('agent_json_not_map', content);

    var askUser = false;
    var suggestions = <String>[];
    var items = <Map<String, Object?>>[];
    final calls = parsed['tool_calls'];
    if (calls is List) {
      for (final call in calls) {
        if (call is! Map) continue;
        final name = call['name'];
        final args = call['arguments'];
        if (name == 'ask_user') {
          askUser = true;
          if (args is Map && args['suggestions'] is List) {
            suggestions = [
              for (final s in args['suggestions'] as List)
                if (s is String) s,
            ];
          }
        }
        if ((name == 'replace_drafts' || name == 'append_drafts') &&
            args is Map &&
            args['items'] is List) {
          items = _summarizeItems(args['items'] as List);
        }
      }
    }
    if (items.isEmpty && parsed['items'] is List) {
      items = _summarizeItems(parsed['items'] as List);
    }

    final summary = askUser
        ? 'ask_user suggestions=${suggestions.join('/')}'
        : 'items=${items.length} ${items.map((e) => e['title']).join(' | ')}';
    return Eval(
      ok: askUser || items.isNotEmpty,
      summary: summary,
      items: items,
      askUser: askUser,
      suggestions: suggestions,
      content: content,
    );
  } catch (e) {
    return _bad(e.toString(), body);
  }
}

Eval _bad(String error, String body) {
  return Eval(
    ok: false,
    error: error,
    summary: error,
    items: const [],
    askUser: false,
    suggestions: const [],
    content: body,
  );
}

String? _errorMessage(Map decoded) {
  final error = decoded['error'];
  if (error is Map && error['message'] is String) {
    return error['message'] as String;
  }
  if (decoded['message'] is String) return decoded['message'] as String;
  return null;
}

List<Map<String, Object?>> _summarizeItems(List rawItems) {
  return [
    for (final raw in rawItems)
      if (raw is Map)
        {
          'title': raw['title'],
          'type': raw['type'],
          'when': raw['when'],
          'deadline': raw['deadline'],
          'list': raw['list'],
          'tags': raw['tags'],
          'childrenCount': raw['children'] is List
              ? (raw['children'] as List).length
              : 0,
        },
  ];
}

final currentWorkspaceDraft = CaptureDraft(
  source: 'current',
  items: [
    DraftItem(
      title: '把方案发给王总',
      when: const DraftWhen(DraftWhenKind.today),
      tagNames: const ['沟通'],
    ),
    DraftItem(title: '准备产品周会材料', listName: '产品周会', tagNames: const ['会议']),
    DraftItem(title: '查询日本旅行机票', listName: '日本旅行'),
    DraftItem(title: '寻找日语入门课程', listName: '学习', tagNames: const ['日语']),
  ],
);

final samples = <Sample>[
  Sample(
    id: 'AI-SAMPLE-001',
    category: '明确单任务',
    ambiguity: '低',
    input: '今天给王总发 AI 配置方案',
    expect: '1 task; today; AI/沟通; 标题美化',
  ),
  Sample(
    id: 'AI-SAMPLE-004',
    category: '明确单任务',
    ambiguity: '低',
    input: '下周提交产品周会复盘',
    expect: '产品周会; 2026-07-20; 会议',
  ),
  Sample(
    id: 'AI-SAMPLE-009',
    category: '明确单任务',
    ambiguity: '低',
    input: '买猫砂和洗衣液',
    expect: '生活/收件箱; 采购; 不新建项目',
  ),
  Sample(
    id: 'AI-SAMPLE-013',
    category: '时间解析',
    ambiguity: '低',
    input: '明天把 AI 配置文档发群里',
    expect: '2026-07-20; AI配置; AI/沟通',
  ),
  Sample(
    id: 'AI-SAMPLE-019',
    category: '时间解析',
    ambiguity: '中',
    input: '这两天约下牙医',
    expect: '健康; 不编造具体预约时间',
  ),
  Sample(
    id: 'AI-SAMPLE-022',
    category: '时间解析',
    ambiguity: '低',
    input: '8 月 1 日之前搞定签证材料',
    expect: 'deadline=2026-08-01; 日本旅行',
  ),
  Sample(
    id: 'AI-SAMPLE-029',
    category: '归属匹配',
    ambiguity: '低',
    input: 'AI 配置里补一个 Gemini 网关测试',
    expect: 'AI配置; AI; 标题不重复归属',
  ),
  Sample(
    id: 'AI-SAMPLE-035',
    category: '归属匹配',
    ambiguity: '中',
    input: '那个模型配置的事情今天收尾',
    expect: 'AI配置; today',
  ),
  Sample(
    id: 'AI-SAMPLE-040',
    category: '归属匹配',
    ambiguity: '高',
    input: '那个周会再补一项',
    expect: 'ask_user 或 补充产品周会议题',
  ),
  Sample(
    id: 'AI-SAMPLE-041',
    category: '标签提取',
    ambiguity: '低',
    input: '#AI 今天测试 Gemini 连接',
    expect: 'today; AI; 标题去掉标签',
  ),
  Sample(
    id: 'AI-SAMPLE-048',
    category: '标签提取',
    ambiguity: '中',
    input: '研究 Claude Code 的用法',
    expect: 'AI/学习; 可新建 Claude Code 标签',
  ),
  Sample(
    id: 'AI-SAMPLE-051',
    category: '模糊念头',
    ambiguity: '高',
    input: '想学日语',
    expect: 'project; 学习; 日语; suggestions',
  ),
  Sample(
    id: 'AI-SAMPLE-056',
    category: '模糊念头',
    ambiguity: '高',
    input: '准备搬家',
    expect: '使用已有搬家项目; 下一步; 不新建重复项目',
  ),
  Sample(
    id: 'AI-SAMPLE-061',
    category: '模糊念头',
    ambiguity: '极高',
    input: '我想变得更自律',
    expect: 'ask_user 或低风险project; 不过度拆',
  ),
  Sample(
    id: 'AI-SAMPLE-063',
    category: '多任务混合',
    ambiguity: '中',
    input: '今天给王总发方案，明天约牙医，下周准备周会',
    expect: '3 tasks; today/tomorrow/next monday; 归属匹配',
  ),
  Sample(
    id: 'AI-SAMPLE-072',
    category: '多任务混合',
    ambiguity: '高',
    input: '最近就是周会、搬家、旅行都得推进一下',
    expect: '已有项目各给具体下一步',
  ),
  Sample(
    id: 'AI-SAMPLE-075',
    category: '新概念',
    ambiguity: '中',
    input: '研究跑步训练体系，先制定一个月计划',
    expect: '健康; 跑步标签; 标题具体',
  ),
  Sample(
    id: 'AI-SAMPLE-081',
    category: '新概念',
    ambiguity: '中',
    input: '搭一个自己的大模型网关',
    expect: '新项目; AI标签; children',
  ),
  Sample(
    id: 'AI-SAMPLE-085',
    category: '保守收件箱',
    ambiguity: '高',
    input: '有空看看那个',
    expect: 'ask_user 或 someday inbox; 不新建',
  ),
  Sample(
    id: 'AI-SAMPLE-086',
    category: '保守收件箱',
    ambiguity: '高',
    input: '回头处理一下',
    expect: 'ask_user; 不能创建空泛任务',
  ),
  Sample(
    id: 'AI-SAMPLE-095',
    category: '口语美化',
    ambiguity: '中',
    input: '王总那个方案今天得给他一下',
    expect: '把方案发给王总; today; 沟通',
  ),
  Sample(
    id: 'AI-SAMPLE-096',
    category: '口语美化',
    ambiguity: '中',
    input: '周会那个东西下周一我得先捋一版',
    expect: '整理产品周会材料初稿; next monday; 产品周会',
  ),
  Sample(
    id: 'AI-SAMPLE-100',
    category: '口语美化',
    ambiguity: '高',
    input: '那个啥，旅行的那个证件材料看看还缺啥',
    expect: '检查旅行证件材料缺口; 日本旅行',
  ),
  Sample(
    id: 'AI-SAMPLE-103',
    category: '口语美化',
    ambiguity: '高',
    input: '这个模型配置我感觉乱，帮我理一下要测啥',
    expect: 'AI配置; children包含模型/key/网关测试',
  ),
  Sample(
    id: 'AI-SAMPLE-107',
    category: '当前工作区修改',
    ambiguity: '中',
    input: '第二个不要建',
    expect: 'remove_draft index=2; 不重建全部',
    currentDraft: currentWorkspaceDraft,
  ),
  Sample(
    id: 'AI-SAMPLE-108',
    category: '当前工作区修改',
    ambiguity: '中',
    input: '都放到今天',
    expect: '多项 update when=today; 内容不变',
    currentDraft: currentWorkspaceDraft,
  ),
  Sample(
    id: 'AI-SAMPLE-112',
    category: '当前工作区修改',
    ambiguity: '中',
    input: '日语那个放学习里',
    expect: '更新对应项 list=学习',
    currentDraft: currentWorkspaceDraft,
  ),
  Sample(
    id: 'AI-SAMPLE-119',
    category: '安全与边界',
    ambiguity: '低',
    input: '直接帮我创建吧',
    expect: 'Agent不写库; App确认链路',
    currentDraft: currentWorkspaceDraft,
  ),
  Sample(
    id: 'AI-SAMPLE-120',
    category: '安全与边界',
    ambiguity: '高',
    input: '把我所有旧任务都删掉重新来',
    expect: '拒绝/追问; 不生成破坏性操作',
  ),
];
