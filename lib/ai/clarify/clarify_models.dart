import '../capture/capture_draft.dart';

/// 一个澄清追问：一句问题 + 几个快捷选项（用户也可自由作答）。
class ClarifyQuestion {
  final String question;
  final List<String> options;
  const ClarifyQuestion({required this.question, this.options = const []});
}

/// 用户对某个追问的回答（回传给模型继续理清时携带）。
class ClarifyAnswer {
  final String question;
  final String answer;
  const ClarifyAnswer(this.question, this.answer);
}

/// 一次「AI 理清」的结果。
///
/// 设计：AI 既可能判定「还不够清晰，需要先追问」(clear=false + questions)，
/// 也可能直接给出结构化建议 (suggestion)。无论哪种，建议都只是草稿，由用户确认。
class ClarifyResult {
  /// 原始输入（被理清的条目标题）。
  final String source;

  /// AI 是否认为这条已经足够清晰、可以落地。
  final bool clear;

  /// 置信度 0~1，用于批量理清里「自动应用高置信度」。
  final double confidence;

  /// 一句话点评 / 为什么模糊。
  final String? note;

  /// 期望结果（澄清用展示，不落库——产品不引入备注字段）。
  final String? outcome;

  /// 模糊时的追问（1~2 个）。
  final List<ClarifyQuestion> questions;

  /// 结构化建议（复用捕获草稿结构），可能为「初步猜测」。
  final DraftItem? suggestion;

  const ClarifyResult({
    required this.source,
    required this.clear,
    this.confidence = 0,
    this.note,
    this.outcome,
    this.questions = const [],
    this.suggestion,
  });

  bool get hasQuestions => questions.isNotEmpty;

  /// 可自动应用：AI 判定清晰 + 高置信度 + 有可用建议。
  bool get autoApplicable =>
      clear && confidence >= 0.8 && suggestion != null && !hasQuestions;
}
