import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_providers.dart';
import '../../ai/config/ai_config.dart';
import '../../ai/core/llm_exception.dart';
import '../../ai/core/llm_message.dart';
import '../../ai/providers/openai_compat_client.dart';
import '../shared/theme/app_theme.dart';

/// AI 模型设置：选厂商、填模型与 API Key，保存到本地（填一次就记住）。
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  late AiProvider _provider;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _baseUrlCtrl;

  bool _obscure = true;
  bool _busy = false;
  String? _message;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(aiConfigProvider);
    _provider = cfg.provider;
    _modelCtrl = TextEditingController(text: cfg.model);
    _keyCtrl = TextEditingController(text: cfg.apiKey);
    _baseUrlCtrl = TextEditingController(text: cfg.baseUrl);
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _keyCtrl.dispose();
    _baseUrlCtrl.dispose();
    super.dispose();
  }

  /// 根据当前表单拼出一份配置。
  AiConfig _buildConfig() {
    final preset = AiConfig.preset(_provider,
        apiKey: _keyCtrl.text.trim(),
        model: _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim());
    final base = _baseUrlCtrl.text.trim();
    return base.isEmpty ? preset : preset.copyWith(baseUrl: base);
  }

  /// 切换厂商时，带出该厂商的默认模型 / baseUrl，方便用户。
  void _onProviderChanged(AiProvider? p) {
    if (p == null) return;
    final preset = AiConfig.preset(p, apiKey: '');
    setState(() {
      _provider = p;
      _modelCtrl.text = preset.model;
      _baseUrlCtrl.text = preset.baseUrl;
      _message = null;
    });
  }

  Future<void> _save() async {
    await ref.read(aiConfigProvider.notifier).save(_buildConfig());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存，下次启动自动生效')));
  }

  Future<void> _clear() async {
    await ref.read(aiConfigProvider.notifier).clear();
    if (!mounted) return;
    final cfg = ref.read(aiConfigProvider);
    setState(() {
      _provider = cfg.provider;
      _modelCtrl.text = cfg.model;
      _keyCtrl.text = cfg.apiKey;
      _baseUrlCtrl.text = cfg.baseUrl;
      _message = null;
      _ok = false;
    });
  }

  /// 连接测试：用当前表单直接发一次最小请求，确认 Key / 模型 / 端点可用。
  Future<void> _test() async {
    final cfg = _buildConfig();
    if (!cfg.isReady) {
      setState(() {
        _ok = false;
        _message = '请先填写 API Key';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final client = OpenAiCompatClient(cfg);
      final reply = await client.complete(
        [const LlmMessage.user('reply with the single word: ok')],
        timeout: const Duration(seconds: 15),
      );
      setState(() {
        _ok = true;
        _message = '连接成功：${reply.trim()}';
      });
    } on LlmException catch (e) {
      setState(() {
        _ok = false;
        _message = '连接失败：${e.message}';
      });
    } catch (e) {
      setState(() {
        _ok = false;
        _message = '连接失败：$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = _provider == AiProvider.custom;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 模型')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('智能拆解',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            '配置后，新建任务时可用「✨ 一句话拆解」把整段文字整理成结构化待办。'
            'Key 保存在本机，仅用于直接调用模型。',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<AiProvider>(
            initialValue: _provider,
            decoration: const InputDecoration(
              labelText: '模型厂商',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final p in AiProvider.values)
                DropdownMenuItem(value: p, child: Text(p.label)),
            ],
            onChanged: _onProviderChanged,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _modelCtrl,
            decoration: const InputDecoration(
              labelText: '模型',
              hintText: '如 gemini-2.5-flash',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _keyCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'API Key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (isCustom) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _baseUrlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Base URL（OpenAI 兼容端点）',
                hintText: 'https://.../v1',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _test,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bolt_outlined),
                label: const Text('测试'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _busy ? null : _clear,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('清除已保存的 Key'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _ok ? AppTheme.primaryBlue : Colors.red),
            ),
          ],
        ],
      ),
    );
  }
}
