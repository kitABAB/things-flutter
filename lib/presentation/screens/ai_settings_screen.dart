import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../ai/ai_providers.dart';
import '../../ai/config/ai_config.dart';
import '../../ai/config/model_connection.dart';
import '../../ai/core/llm_exception.dart';
import '../../ai/core/llm_message.dart';
import '../../ai/providers/openai_compat_client.dart';
import '../shared/theme/app_theme.dart';

/// AI 模型设置：管理多个「模型连接」（多 Key / 多厂商），并选择当前使用的模型。
/// 一把 Key 可挂多个模型，可一键从 `/models` 拉取该 Key 支持的模型列表。
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  bool _busyTest = false;
  String? _testMsg;
  bool _testOk = false;

  Future<void> _test() async {
    final cfg = ref.read(aiConfigProvider);
    if (!cfg.isReady) {
      setState(() {
        _testOk = false;
        _testMsg = '请先添加并选择一个模型连接';
      });
      return;
    }
    setState(() {
      _busyTest = true;
      _testMsg = null;
    });
    try {
      final reply = await OpenAiCompatClient(cfg).complete(
        [const LlmMessage.user('reply with the single word: ok')],
        timeout: const Duration(seconds: 15),
      );
      setState(() {
        _testOk = true;
        _testMsg = '连接成功（${cfg.model}）：${reply.trim()}';
      });
    } on LlmException catch (e) {
      setState(() {
        _testOk = false;
        _testMsg = '连接失败：${e.message}';
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testMsg = '连接失败：$e';
      });
    } finally {
      if (mounted) setState(() => _busyTest = false);
    }
  }

  Future<void> _openEditor({ModelConnection? existing}) async {
    final result = await showModalBottomSheet<ModelConnection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ConnectionEditorSheet(existing: existing),
    );
    if (result == null) return;
    await ref
        .read(aiSettingsProvider.notifier)
        .upsertConnection(result, makeActive: existing == null);
    if (mounted) setState(() => _testMsg = null);
  }

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清除全部连接？'),
        content: const Text('将删除所有已保存的模型连接与 Key，AI 功能会回到未配置状态。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清除')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(aiSettingsProvider.notifier).clearAll();
      if (mounted) {
        setState(() {
          _testMsg = null;
          _testOk = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);
    final active = settings.activeConnection;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 模型'),
        actions: [
          IconButton(
            tooltip: '新增连接',
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _intro(context),
          const SizedBox(height: 18),
          _currentCard(context, settings, active),
          const SizedBox(height: 22),
          Row(
            children: [
              Text('模型连接',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (settings.connections.isNotEmpty)
                Text('${settings.connections.length} 个',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          if (settings.connections.isEmpty)
            _emptyConnections(context)
          else ...[
            for (final c in settings.connections)
              _connectionTile(context, settings, c),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增连接'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _confirmClearAll,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('清除全部连接'),
              style:
                  TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _intro(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('智能拆解 · 理清 · 回顾',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          '可保存多把 Key / 多个厂商，每把 Key 下可挂多个模型，随时切换当前使用的模型。'
          'Key 保存在本机，仅用于直接调用模型。',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _currentCard(
      BuildContext context, AiSettings settings, ModelConnection? active) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18),
              const SizedBox(width: 6),
              Text('当前使用',
                  style:
                      theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          if (active == null)
            Text('尚未添加任何模型连接，点右下角「新增连接」开始。',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppTheme.textSecondary))
          else ...[
            _activeSelectors(context, settings, active),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _busyTest ? null : _test,
                  icon: _busyTest
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bolt_outlined),
                  label: const Text('测试连接'),
                ),
              ],
            ),
            if (_testMsg != null) ...[
              const SizedBox(height: 8),
              Text(_testMsg!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: _testOk ? AppTheme.primaryBlue : Colors.red)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _activeSelectors(
      BuildContext context, AiSettings settings, ModelConnection active) {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: active.id,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '连接',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final c in settings.connections)
              DropdownMenuItem(
                value: c.id,
                child: Text('${c.label} · ${c.provider.label}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) {
            if (id == null) return;
            final c = settings.connections.firstWhere((e) => e.id == id);
            ref
                .read(aiSettingsProvider.notifier)
                .setActive(c.id, c.primaryModel);
            setState(() => _testMsg = null);
          },
        ),
        const SizedBox(height: 12),
        if (active.models.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text('该连接还没有模型，去下方「编辑」里添加或拉取。',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.textSecondary)),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: active.models.contains(settings.activeModel)
                ? settings.activeModel
                : active.models.first,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '模型',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final m in active.models)
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (m) {
              if (m == null) return;
              ref.read(aiSettingsProvider.notifier).setActive(active.id, m);
              setState(() => _testMsg = null);
            },
          ),
      ],
    );
  }

  Widget _emptyConnections(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Icon(Icons.cable_outlined,
              size: 32, color: AppTheme.textSecondary),
          const SizedBox(height: 8),
          Text('还没有模型连接',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text('填入厂商与 API Key 即可开始',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
            label: const Text('新增连接'),
          ),
        ],
      ),
    );
  }

  Widget _connectionTile(
      BuildContext context, AiSettings settings, ModelConnection c) {
    final isActive = c.id == settings.activeConnectionId;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive
              ? AppTheme.primaryBlue
              : Theme.of(context).dividerColor,
          width: isActive ? 1.4 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(c.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          if (isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('当前',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 11)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('${c.provider.label} · ${_maskKey(c.apiKey)}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) => _onTileAction(v, c),
                  itemBuilder: (_) => [
                    if (!isActive)
                      const PopupMenuItem(
                          value: 'active', child: Text('设为当前')),
                    const PopupMenuItem(value: 'edit', child: Text('编辑 / 拉取模型')),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
            if (c.models.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in c.models)
                    _ModelChip(
                      label: m,
                      selected: isActive && m == settings.activeModel,
                      onTap: () {
                        ref
                            .read(aiSettingsProvider.notifier)
                            .setActive(c.id, m);
                        setState(() => _testMsg = null);
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _onTileAction(String v, ModelConnection c) async {
    switch (v) {
      case 'active':
        await ref
            .read(aiSettingsProvider.notifier)
            .setActive(c.id, c.primaryModel);
        if (mounted) setState(() => _testMsg = null);
        break;
      case 'edit':
        await _openEditor(existing: c);
        break;
      case 'delete':
        await ref.read(aiSettingsProvider.notifier).removeConnection(c.id);
        if (mounted) setState(() => _testMsg = null);
        break;
    }
  }

  static String _maskKey(String key) {
    final k = key.trim();
    if (k.length <= 8) return '••••';
    return '${k.substring(0, 4)}••••${k.substring(k.length - 4)}';
  }
}

class _ModelChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModelChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryBlue
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : null,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// 连接编辑（新增 / 修改）：厂商、名称、Key、Base URL、模型列表（手填 + 一键拉取）。
class _ConnectionEditorSheet extends StatefulWidget {
  final ModelConnection? existing;
  const _ConnectionEditorSheet({this.existing});

  @override
  State<_ConnectionEditorSheet> createState() => _ConnectionEditorSheetState();
}

class _ConnectionEditorSheetState extends State<_ConnectionEditorSheet> {
  late AiProvider _provider;
  late final TextEditingController _label;
  late final TextEditingController _key;
  late final TextEditingController _baseUrl;
  late final TextEditingController _modelInput;
  late List<String> _models;

  bool _obscure = true;
  bool _fetching = false;
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _provider = e?.provider ?? AiProvider.gemini;
    final preset = AiConfig.preset(_provider, apiKey: '');
    _label = TextEditingController(text: e?.label ?? '');
    _key = TextEditingController(text: e?.apiKey ?? '');
    _baseUrl = TextEditingController(text: e?.baseUrl ?? preset.baseUrl);
    _modelInput = TextEditingController();
    _models = [...?e?.models];
    if (_models.isEmpty && preset.model.isNotEmpty) _models = [preset.model];
  }

  @override
  void dispose() {
    _label.dispose();
    _key.dispose();
    _baseUrl.dispose();
    _modelInput.dispose();
    super.dispose();
  }

  void _onProviderChanged(AiProvider? p) {
    if (p == null) return;
    final preset = AiConfig.preset(p, apiKey: '');
    setState(() {
      _provider = p;
      _baseUrl.text = preset.baseUrl;
      if (_models.isEmpty && preset.model.isNotEmpty) {
        _models = [preset.model];
      }
    });
  }

  void _addModel() {
    final m = _modelInput.text.trim();
    if (m.isEmpty) return;
    if (!_models.contains(m)) {
      setState(() => _models = [..._models, m]);
    }
    _modelInput.clear();
  }

  Future<void> _fetchModels() async {
    final key = _key.text.trim();
    final base = _baseUrl.text.trim();
    if (key.isEmpty || base.isEmpty) {
      _snack('请先填写 API Key 和 Base URL');
      return;
    }
    setState(() => _fetching = true);
    try {
      final cfg = AiConfig(
        provider: _provider,
        baseUrl: base,
        model: _models.isNotEmpty ? _models.first : 'placeholder',
        apiKey: key,
      );
      final ids = await OpenAiCompatClient(cfg).listModels();
      if (ids.isEmpty) {
        _snack('未拉取到模型，可手动输入');
      } else {
        setState(() {
          // 拉取结果优先，合并已有手填项去重。
          final merged = <String>[...ids];
          for (final m in _models) {
            if (!merged.contains(m)) merged.add(m);
          }
          _models = merged;
        });
        _snack('已拉取 ${ids.length} 个模型');
      }
    } on LlmException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('拉取失败：$e');
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _confirm() {
    final key = _key.text.trim();
    if (key.isEmpty) {
      _snack('请填写 API Key');
      return;
    }
    final base = _baseUrl.text.trim();
    if (base.isEmpty) {
      _snack('请填写 Base URL');
      return;
    }
    final conn = ModelConnection(
      id: widget.existing?.id ?? _uuid.v4(),
      label: _label.text.trim().isNotEmpty ? _label.text.trim() : _provider.label,
      provider: _provider,
      baseUrl: base,
      apiKey: key,
      models: _models,
    );
    Navigator.pop(context, conn);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(widget.existing == null ? '新增连接' : '编辑连接',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            DropdownButtonFormField<AiProvider>(
              initialValue: _provider,
              decoration: const InputDecoration(
                labelText: '模型厂商',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final p in AiProvider.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: _onProviderChanged,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              decoration: InputDecoration(
                labelText: '名称（可选）',
                hintText: _provider.label,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'API Key',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baseUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Base URL（OpenAI 兼容端点）',
                hintText: 'https://.../v1',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text('模型',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _fetching ? null : _fetchModels,
                  icon: _fetching
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_download_outlined, size: 18),
                  label: const Text('拉取该 Key 的模型'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_models.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in _models)
                    InputChip(
                      label: Text(m, style: const TextStyle(fontSize: 12)),
                      onDeleted: () =>
                          setState(() => _models = _models.where((e) => e != m).toList()),
                    ),
                ],
              )
            else
              Text('暂无模型，可手动输入或点上方拉取',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textSecondary)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _modelInput,
                    onSubmitted: (_) => _addModel(),
                    decoration: const InputDecoration(
                      labelText: '手动添加模型',
                      hintText: '如 gemini-2.5-pro',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _addModel,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.check),
                label: const Text('保存连接'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
