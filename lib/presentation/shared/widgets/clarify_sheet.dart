import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_providers.dart';
import '../../../ai/capture/capture_parser.dart';
import '../../../ai/clarify/clarify_models.dart';
import '../../../ai/core/llm_exception.dart';
import '../../../domain/models/item.dart';
import '../../providers/item_providers.dart';
import '../theme/app_theme.dart';
import 'clarify_card.dart';

/// 单条「AI 理清」面板：对一条既有条目追问澄清并整理成可执行草稿，
/// 用户确认后**原地更新**该条目。
class ClarifySheet {
  static Future<bool?> show(BuildContext context, Item item) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ClarifyBody(item: item),
    );
  }
}

enum _Phase { loading, questions, card, error }

class _ClarifyBody extends ConsumerStatefulWidget {
  final Item item;
  const _ClarifyBody({required this.item});

  @override
  ConsumerState<_ClarifyBody> createState() => _ClarifyBodyState();
}

class _ClarifyBodyState extends ConsumerState<_ClarifyBody> {
  _Phase _phase = _Phase.loading;
  String? _error;
  ClarifyResult? _result;
  ClarifyEdit? _edit;
  bool _applying = false;

  /// 当前追问的回答收集（每个问题一个输入框）。
  final Map<int, TextEditingController> _answerCtrls = {};
  final Map<int, String> _picked = {};

  @override
  void initState() {
    super.initState();
    _run(const []);
  }

  @override
  void dispose() {
    for (final c in _answerCtrls.values) {
      c.dispose();
    }
    _edit?.dispose();
    super.dispose();
  }

  CaptureContext _ctx() => CaptureContext(
        now: DateTime.now(),
        projectNames:
            (ref.read(projectsProvider).value ?? []).map((e) => e.title).toList(),
        areaNames:
            (ref.read(areasProvider).value ?? []).map((e) => e.title).toList(),
        tagNames:
            (ref.read(tagsProvider).value ?? []).map((e) => e.title).toList(),
      );

  Future<void> _run(List<ClarifyAnswer> answers) async {
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    final service = ref.read(clarifyServiceProvider);
    ClarifyResult result;
    try {
      result = await service.clarify(widget.item.title, _ctx(), answers: answers);
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.isNotConfigured ? '尚未配置 AI 的 API Key' : '理清失败：${e.message}';
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '理清失败：$e';
      });
      return;
    }
    if (!mounted) return;

    _result = result;
    if (result.hasQuestions) {
      for (final c in _answerCtrls.values) {
        c.dispose();
      }
      _answerCtrls.clear();
      _picked.clear();
      setState(() => _phase = _Phase.questions);
    } else {
      _buildEditFromResult(result);
      setState(() => _phase = _Phase.card);
    }
  }

  void _buildEditFromResult(ClarifyResult result) {
    final draft = result.suggestion!;
    _edit?.dispose();
    _edit = ClarifyEdit.fromDraft(
      draft,
      projects: ref.read(projectsProvider).value ?? [],
      areas: ref.read(areasProvider).value ?? [],
      tags: ref.read(tagsProvider).value ?? [],
    );
  }

  void _submitAnswers() {
    final qs = _result!.questions;
    final answers = <ClarifyAnswer>[];
    for (var i = 0; i < qs.length; i++) {
      final picked = _picked[i];
      final typed = _answerCtrls[i]?.text.trim();
      final ans = (typed != null && typed.isNotEmpty) ? typed : (picked ?? '');
      if (ans.isNotEmpty) answers.add(ClarifyAnswer(qs[i].question, ans));
    }
    _run(answers);
  }

  Future<void> _apply() async {
    if (_edit == null) return;
    setState(() => _applying = true);
    try {
      await applyClarifyEdit(ref, original: widget.item, edit: _edit!);
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('应用失败：$e')));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('已理清并更新')));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxH = math.min(640.0, mq.size.height * 0.86);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 600, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 6),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 18, color: AppTheme.primaryBlue),
                  const SizedBox(width: 8),
                  const Text('AI 理清',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppTheme.textSecondary,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Text(
                '原文：${widget.item.title}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
              ),
            ),
            const Divider(height: 16),
            Flexible(child: _phaseBody()),
          ],
        ),
      ),
    );
  }

  Widget _phaseBody() {
    switch (_phase) {
      case _Phase.loading:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: AppTheme.primaryBlue),
                ),
                const SizedBox(height: 14),
                Text('AI 正在理清…',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ],
            ),
          ),
        );
      case _Phase.error:
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? '出错了',
                  style: const TextStyle(color: AppTheme.deadlineRed)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _run(const []),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue),
                child: const Text('重试'),
              ),
            ],
          ),
        );
      case _Phase.questions:
        return _questionsView();
      case _Phase.card:
        return _cardView();
    }
  }

  Widget _questionsView() {
    final qs = _result!.questions;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            shrinkWrap: true,
            children: [
              if (_result!.note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_result!.note!,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppTheme.textSecondary)),
                ),
              for (var i = 0; i < qs.length; i++) _questionBlock(i, qs[i]),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          child: Row(
            children: [
              const Spacer(),
              FilledButton(
                onPressed: _submitAnswers,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
                child: const Text('继续'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _questionBlock(int i, ClarifyQuestion q) {
    _answerCtrls.putIfAbsent(i, () => TextEditingController());
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q.question,
              style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.4)),
          const SizedBox(height: 8),
          if (q.options.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final opt in q.options)
                  _optionChip(opt, _picked[i] == opt, () {
                    setState(() {
                      _picked[i] = opt;
                      _answerCtrls[i]?.clear();
                    });
                  }),
              ],
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _answerCtrls[i],
            decoration: InputDecoration(
              hintText: '或自由补充…',
              isDense: true,
              filled: true,
              fillColor: AppTheme.backgroundLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (v) {
              if (v.trim().isNotEmpty && _picked[i] != null) {
                setState(() => _picked.remove(i));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _optionChip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryBlue
              : AppTheme.primaryBlue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppTheme.primaryBlue)),
      ),
    );
  }

  Widget _cardView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            shrinkWrap: true,
            children: [
              ClarifyCard(
                edit: _edit!,
                onChanged: () => setState(() {}),
                note: _result!.note,
                outcome: _result!.outcome,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          child: Row(
            children: [
              TextButton(
                onPressed: _applying ? null : () => _run(const []),
                child: const Text('重新理清'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _applying ? null : _apply,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
                child: _applying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('应用'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
