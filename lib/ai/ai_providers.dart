import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture/capture_parser.dart';
import 'clarify/clarify_service.dart';
import 'config/ai_config.dart';
import 'config/ai_settings_store.dart';
import 'core/llm_client.dart';
import 'providers/openai_compat_client.dart';
import 'review/review_service.dart';

/// 当前 AI 配置。
///
/// 解析优先级：本地持久化（设置页保存的）> 编译期环境变量（--dart-define）。
/// 因此用户在设置页填一次 Key 后，每次启动自动生效，无需再贴。
class AiConfigNotifier extends Notifier<AiConfig> {
  @override
  AiConfig build() {
    // 先同步返回环境变量配置，再异步用持久化值覆盖（加载完 UI 自动刷新）。
    _restore();
    return AiConfig.fromEnvironment();
  }

  Future<void> _restore() async {
    final stored = await AiSettingsStore.load();
    if (stored != null) state = stored;
  }

  /// 保存配置（持久化 + 立即生效）。
  Future<void> save(AiConfig config) async {
    await AiSettingsStore.save(config);
    state = config;
  }

  /// 清除已保存配置，回退到环境变量。
  Future<void> clear() async {
    await AiSettingsStore.clear();
    state = AiConfig.fromEnvironment();
  }
}

final aiConfigProvider =
    NotifierProvider<AiConfigNotifier, AiConfig>(AiConfigNotifier.new);

/// 厂商无关的对话客户端。所有厂商都走 OpenAI 兼容协议，故统一用一个实现。
final llmClientProvider = Provider<LlmClient>((ref) {
  final config = ref.watch(aiConfigProvider);
  return OpenAiCompatClient(config);
});

/// 「一句话拆解捕获」解析器。
final captureParserProvider = Provider<CaptureParser>((ref) {
  return CaptureParser(ref.watch(llmClientProvider));
});

/// 「AI 理清」教练（单条 + 批量复用）。
final clarifyServiceProvider = Provider<ClarifyService>((ref) {
  return ClarifyService(ref.watch(llmClientProvider));
});

/// 「一键回顾」服务（本地扫描 + 可选 AI 建议）。
final reviewServiceProvider = Provider<ReviewService>((ref) {
  return ReviewService(ref.watch(llmClientProvider));
});

/// AI 功能是否就绪（决定 UI 入口是否点亮）。Key 未配置时整体优雅隐藏。
final aiEnabledProvider = Provider<bool>((ref) {
  return ref.watch(llmClientProvider).isConfigured;
});
