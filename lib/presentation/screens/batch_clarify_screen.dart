import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_providers.dart';
import '../../ai/capture/capture_parser.dart';
import '../../ai/clarify/clarify_models.dart';
import '../../ai/core/llm_exception.dart';
import '../../domain/models/item.dart';
import '../providers/item_providers.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/clarify_card.dart';

/// 批量理清队列：逐条对收件箱条目跑 AI 理清，支持应用/跳过/编辑，
/// 以及「自动应用高置信度建议」。
class BatchClarifyScreen extends ConsumerStatefulWidget {
  final List<Item> items;
  const BatchClarifyScreen({super.key, required this.items});

  @override
  ConsumerState<BatchClarifyScreen> createState() => _BatchClarifyScreenState();
}

enum _Phase { loading, ready, error, done }

class _BatchClarifyScreenState extends ConsumerState<BatchClarifyScreen> {
  int _index = 0;
  _Phase _phase = _Phase.loading;
  String? _error;
  ClarifyResult? _result;
  ClarifyEdit? _edit;
  bool _busy = false;
  bool _autoApply = false;

  int _applied = 0;
  int _skipped = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    _edit?.dispose();
    super.dispose();
  }

  Item get _current => widget.items[_index];

  CaptureContext _ctx() => CaptureContext(
        now: DateTime.now(),
        projectNames:
            (ref.read(projectsProvider).value ?? []).map((e) => e.title).toList(),
        areaNames:
            (ref.read(areasProvider).value ?? []).map((e) => e.title).toList(),
        tagNames:
            (ref.read(tagsProvider).value ?? []).map((e) => e.title).toList(),
      );

  Future<void> _loadCurrent() async {
    if (_index >= widget.items.length) {
      setState(() => _phase = _Phase.done);
      return;
    }
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    final service = ref.read(clarifyServiceProvider);
    ClarifyResult result;
    try {
      result = await service.clarify(_current.title, _ctx());
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
    _edit?.dispose();
    _edit = ClarifyEdit.fromDraft(
      result.suggestion!,
      projects: ref.read(projectsProvider).value ?? [],
      areas: ref.read(areasProvider).value ?? [],
      tags: ref.read(tagsProvider).value ?? [],
    );

    // 自动应用高置信度建议（无追问且 confidence >= 0.8）。
    if (_autoApply && result.autoApplicable) {
      await _apply(auto: true);
      return;
    }
    setState(() => _phase = _Phase.ready);
  }

  Future<void> _apply({bool auto = false}) async {
    if (_edit == null) return;
    if (!auto) setState(() => _busy = true);
    try {
      await applyClarifyEdit(ref, original: _current, edit: _edit!);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('应用失败：$e')));
      return;
    }
    _applied++;
    _next();
  }

  void _skip() {
    _skipped++;
    _next();
  }

  void _next() {
    _index++;
    _busy = false;
    _loadCurrent();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('批量理清'),
        bottom: _phase == _Phase.done
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: widget.items.isEmpty
                      ? 0
                      : _index / widget.items.length,
                  minHeight: 3,
                  backgroundColor: AppTheme.backgroundLight,
                  color: AppTheme.primaryBlue,
                ),
              ),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.done:
        return _doneView();
      case _Phase.loading:
        return _loadingView();
      case _Phase.error:
        return _errorView();
      case _Phase.ready:
        return _readyView();
    }
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          Text('第 ${_index + 1} / ${widget.items.length} 条',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
          const Spacer(),
          const Text('自动应用高置信度', style: TextStyle(fontSize: 12.5)),
          Switch(
            value: _autoApply,
            activeThumbColor: AppTheme.primaryBlue,
            onChanged: (v) => setState(() => _autoApply = v),
          ),
        ],
      ),
    );
  }

  Widget _loadingView() {
    return Column(
      children: [
        _header(),
        Expanded(
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
        ),
      ],
    );
  }

  Widget _errorView() {
    return Column(
      children: [
        _header(),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? '出错了',
                    style: const TextStyle(color: AppTheme.deadlineRed)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  children: [
                    OutlinedButton(
                        onPressed: _skip, child: const Text('跳过这条')),
                    FilledButton(
                      onPressed: _loadCurrent,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _readyView() {
    return Column(
      children: [
        _header(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('原文：${_current.title}',
                style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                    height: 1.4)),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _skip,
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('跳过'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _busy ? null : () => _apply(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('应用并下一条'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _doneView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 64, color: Color(0xFF53B25B)),
            const SizedBox(height: 18),
            const Text('收件箱理清完成',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('已理清 $_applied 条 · 跳过 $_skipped 条',
                style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style:
                  FilledButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }
}
