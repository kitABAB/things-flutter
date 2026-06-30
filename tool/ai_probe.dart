// AI 调教探针：用真实模型跑「理清 / 回顾」，打印输出以评估 prompt 效果。
//
// 运行（PowerShell）：
//   $env:AI_API_KEY="<key>"; dart run tool/ai_probe.dart
// 可选：$env:AI_PROVIDER="gemini"  $env:AI_MODEL="gemini-2.5-flash"
//
// 不会改库、不联网以外的副作用；仅打印，供人工评估理清质量。
import 'dart:io';

import 'package:things3_clone/ai/capture/capture_parser.dart' show CaptureContext;
import 'package:things3_clone/ai/clarify/clarify_models.dart';
import 'package:things3_clone/ai/clarify/clarify_service.dart';
import 'package:things3_clone/ai/config/ai_config.dart';
import 'package:things3_clone/ai/core/llm_exception.dart';
import 'package:things3_clone/ai/providers/openai_compat_client.dart';
import 'package:things3_clone/ai/review/review_models.dart';
import 'package:things3_clone/ai/review/review_service.dart';
import 'package:things3_clone/domain/models/item.dart';

// 模拟用户的清单语境（让 AI 有已有项目/领域/标签可挂靠）。
final ctx = CaptureContext(
  now: DateTime.now(),
  projectNames: ['酒吧组局', '减脂计划'],
  areaNames: ['工作', '健康', '饮食', '学习'],
  tagNames: ['在电脑前', '在手机上', '工作', '学习', '购物'],
);

/// 不同模糊度的测试物料。
const inputs = <String>[
  // —— 极模糊：愿望/灵感，无动作无时间 ——
  '学日语',
  '研究自动化 AI 做视频',
  'Web3 工作',
  '拍笔记',
  '醒图 P 图',
  // —— 中等：有大致方向但下一步不明确 ——
  '看 Rust 视频（200小时）',
  '做酒吧组局，发 98 抖音研究如何引流',
  '健身、护肤、饮食',
  // —— 较清晰：基本可执行 ——
  '买大麦茶和杯子',
  '每天早饭后吃鱼油、叶黄素、VC泡腾片',
  // —— 明确：动作+时间，应判定 clear 直接给建议 ——
  '周五下午3点前把季度报告发给老板',
];

Future<void> main() async {
  final key = Platform.environment['AI_API_KEY'] ?? '';
  if (key.trim().isEmpty) {
    stderr.writeln('缺少 AI_API_KEY 环境变量。');
    exit(2);
  }
  final providerName = Platform.environment['AI_PROVIDER'] ?? 'gemini';
  final model = Platform.environment['AI_MODEL'];
  final provider = AiProvider.values.firstWhere(
    (p) => p.name == providerName,
    orElse: () => AiProvider.gemini,
  );
  final config = AiConfig.preset(provider, apiKey: key, model: model);
  final client = OpenAiCompatClient(config);

  stdout.writeln('=== 模型：${config.provider.label} / ${config.model} ===\n');

  final clarify = ClarifyService(client);

  // 允许用 PROBE_INPUTS（用 || 分隔）覆盖默认输入，便于针对性快速验证。
  final override = Platform.environment['PROBE_INPUTS'];
  final testInputs = (override != null && override.trim().isNotEmpty)
      ? override.split('||').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
      : inputs;

  for (final input in testInputs) {
    stdout.writeln('────────────────────────────────────────');
    stdout.writeln('【输入】$input');
    try {
      final r = await _clarifyWithRetry(clarify, input, ctx);
      _printResult(r);

      // 模糊的：模拟用户选第一个选项作答后再理清，看能否落地。
      if (!r.clear && r.questions.isNotEmpty) {
        final answers = <ClarifyAnswer>[];
        for (final q in r.questions) {
          final ans = q.options.isNotEmpty ? q.options.first : '随便';
          answers.add(ClarifyAnswer(q.question, ans));
        }
        stdout.writeln('  ↳ 模拟回答：${answers.map((a) => '${a.question}=${a.answer}').join('；')}');
        final r2 = await _clarifyWithRetry(clarify, input, ctx, answers: answers);
        stdout.writeln('  ↳ 二轮结果：');
        _printResult(r2, indent: '    ');
      }
    } catch (e) {
      stdout.writeln('  [错误] $e');
    }
    // 免费额度限流（RPM）很低，条目间留间隔。
    await Future.delayed(const Duration(milliseconds: 4500));
  }

  // 回顾建议
  stdout.writeln('\n════════ 一键回顾 · AI 建议 ════════');
  final now = DateTime.now();
  final old = now.subtract(const Duration(days: 30));
  final active = <Item>[
    _t('收件箱里堆的念头', start: WhenStart.inbox),
    _t('再堆一条没理的', start: WhenStart.inbox),
    _t('学吉他', start: WhenStart.someday, createdAt: old),
    _p('网站重构', createdAt: old), // 无子任务 → 缺下一步
    _t('整理旧照片', start: WhenStart.anytime, createdAt: old), // 停滞
  ];
  final review = ReviewService(client);
  final report = await review.build(active, now: now);
  for (final s in report.sections) {
    if (s.isEmpty) continue;
    stdout.writeln('- ${s.kind.title}：${s.count} 条');
  }
  stdout.writeln('AI 建议：${report.aiAdvice ?? '（无）'}');
}

/// 遇到 429 限流时退避重试，最多 3 次。
Future<ClarifyResult> _clarifyWithRetry(
  ClarifyService svc,
  String input,
  CaptureContext ctx, {
  List<ClarifyAnswer> answers = const [],
}) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await svc.clarify(input, ctx, answers: answers);
    } on LlmException catch (e) {
      if (e.statusCode == 429 && attempt < 3) {
        final wait = Duration(seconds: 12 * (attempt + 1));
        stdout.writeln('  (429 限流，等待 ${wait.inSeconds}s 后重试…)');
        await Future.delayed(wait);
        continue;
      }
      rethrow;
    }
  }
}

void _printResult(ClarifyResult r, {String indent = '  '}) {
  stdout.writeln('${indent}clear=${r.clear}  confidence=${r.confidence.toStringAsFixed(2)}'
      '  autoApplicable=${r.autoApplicable}');
  if (r.note != null) stdout.writeln('${indent}note: ${r.note}');
  if (r.outcome != null) stdout.writeln('${indent}outcome: ${r.outcome}');
  for (final q in r.questions) {
    stdout.writeln('$indent? ${q.question}  [${q.options.join(' / ')}]');
  }
  final s = r.suggestion;
  if (s != null) {
    final dl = s.deadline == null
        ? '-'
        : s.deadline.toString().split(' ').first;
    stdout.writeln('$indent→ 建议: "${s.title}"  类型=${s.type.name}'
        '  when=${_when(s.when)}  deadline=$dl  list=${s.listName ?? '-'}'
        '  tags=${s.tagNames.isEmpty ? '-' : s.tagNames.join(',')}');
    if (s.children.isNotEmpty) {
      stdout.writeln('$indent  子步骤: ${s.children.map((c) => c.title).join(' | ')}');
    }
  }
}

String _when(dynamic w) {
  final k = w.kind.toString().split('.').last;
  if (w.date != null) return '$k(${w.date.toString().split(' ').first})';
  return k;
}

Item _t(String title,
    {WhenStart start = WhenStart.anytime, DateTime? createdAt}) {
  final now = DateTime.now();
  return Item(
    id: title,
    userId: 'u',
    type: ItemType.task,
    title: title,
    start: start,
    createdAt: createdAt ?? now,
    updatedAt: now,
  );
}

Item _p(String title, {DateTime? createdAt}) {
  final now = DateTime.now();
  return Item(
    id: title,
    userId: 'u',
    type: ItemType.project,
    title: title,
    start: WhenStart.anytime,
    createdAt: createdAt ?? now,
    updatedAt: now,
  );
}
