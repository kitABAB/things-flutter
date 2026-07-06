import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture/capture_parser.dart';
import 'clarify/clarify_service.dart';
import 'config/ai_config.dart';
import 'config/ai_settings_store.dart';
import 'config/model_connection.dart';
import 'core/llm_client.dart';
import 'core/llm_exception.dart';
import 'core/llm_message.dart';
import 'providers/openai_compat_client.dart';
import 'review/review_service.dart';

/// 全部 AI 设置：一组可切换的「模型连接」+ 当前选中的连接/模型。
///
/// 解析优先级：本地持久化（设置页保存的连接）> 编译期环境变量（--dart-define，
/// 作为没有任何连接时的兜底）。用户填一次 Key 后每次启动自动生效。
class AiSettingsNotifier extends Notifier<AiSettings> {
  @override
  AiSettings build() {
    // 先返回空设置（其 activeConfig 会回退到环境变量），再异步加载持久化值。
    _restore();
    return const AiSettings();
  }

  Future<void> _restore() async {
    state = await AiSettingsStore.load();
  }

  Future<void> _persist() => AiSettingsStore.save(state);

  Future<void> renameStrategy(String name) async {
    final trimmed = name.trim();
    state = state.copyWith(strategyName: trimmed.isEmpty ? '策略组 1' : trimmed);
    await _persist();
  }

  /// 新增或更新一条连接。首次新增（或显式要求）时设为当前。
  Future<void> upsertConnection(
    ModelConnection conn, {
    bool makeActive = false,
  }) async {
    final list = [...state.connections];
    final i = list.indexWhere((e) => e.id == conn.id);
    if (i >= 0) {
      list[i] = conn;
    } else {
      list.add(conn);
    }
    var next = state.copyWith(connections: list);
    final activatingThis = conn.id == state.activeConnectionId;
    if (makeActive || state.activeConnectionId == null) {
      next = next.copyWith(
        activeConnectionId: conn.id,
        activeModel: conn.primaryModel,
      );
    } else if (activatingThis && !conn.models.contains(state.activeModel)) {
      // 当前连接被编辑后，原模型已不存在则回退到首选模型。
      next = next.copyWith(activeModel: conn.primaryModel);
    }
    state = next;
    await _persist();
  }

  Future<void> replaceConnections(List<ModelConnection> connections) async {
    state = state.copyWith(connections: connections);
    await _persist();
  }

  Future<void> reorderConnection(int oldIndex, int newIndex) async {
    final list = [...state.connections];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final item = list.removeAt(oldIndex);
    final target = newIndex.clamp(0, list.length);
    list.insert(target, item);
    state = state.copyWith(connections: list);
    await _persist();
  }

  Future<void> removeConnection(String id) async {
    final list = state.connections.where((e) => e.id != id).toList();
    if (state.activeConnectionId == id) {
      state = list.isEmpty
          ? const AiSettings()
          : AiSettings(
              connections: list,
              activeConnectionId: list.first.id,
              activeModel: list.first.primaryModel,
            );
    } else {
      state = state.copyWith(connections: list);
    }
    await _persist();
  }

  /// 切换当前使用的连接与模型。
  Future<void> setActive(String connectionId, String model) async {
    state = state.copyWith(
      activeConnectionId: connectionId,
      activeModel: model,
    );
    await _persist();
  }

  /// 清空所有连接，回退到环境变量。
  Future<void> clearAll() async {
    state = const AiSettings();
    await AiSettingsStore.clear();
  }
}

final aiSettingsProvider = NotifierProvider<AiSettingsNotifier, AiSettings>(
  AiSettingsNotifier.new,
);

/// 当前生效的运行期配置（由当前连接 + 当前模型派生）。
/// 业务层与 [llmClientProvider] 仍只依赖这一份扁平配置，多连接对它们透明。
final aiConfigProvider = Provider<AiConfig>(
  (ref) => ref.watch(aiSettingsProvider).activeConfig,
);

final aiConfigsProvider = Provider<List<AiConfig>>((ref) {
  final settings = ref.watch(aiSettingsProvider);
  final configs = settings.activeConfigs;
  return configs.isEmpty ? [settings.activeConfig] : configs;
});

/// 厂商无关的对话客户端。所有厂商都走 OpenAI 兼容协议，故统一用一个实现。
final llmClientProvider = Provider<LlmClient>((ref) {
  final configs = ref.watch(aiConfigsProvider).where((c) => c.isReady).toList();
  return _FallbackLlmClient(configs);
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

class _FallbackLlmClient implements LlmClient {
  final List<AiConfig> configs;

  const _FallbackLlmClient(this.configs);

  @override
  bool get isConfigured => configs.any((c) => c.isReady);

  @override
  Future<String> complete(
    List<LlmMessage> messages, {
    bool jsonMode = false,
    double temperature = 0.2,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!isConfigured) {
      throw const LlmException.notConfigured();
    }

    LlmException? last;
    for (var i = 0; i < configs.length; i += 1) {
      final config = configs[i];
      try {
        return await OpenAiCompatClient(config).complete(
          messages,
          jsonMode: jsonMode,
          temperature: temperature,
          timeout: timeout,
        );
      } on LlmException catch (e) {
        last = e;
        final next = i + 1 < configs.length ? configs[i + 1] : null;
        if (next == null || !_canTryNext(e, config, next)) rethrow;
      }
    }
    throw last ?? const LlmException.notConfigured();
  }

  @override
  Future<List<String>> listModels({
    Duration timeout = const Duration(seconds: 15),
  }) {
    if (!isConfigured) {
      throw const LlmException.notConfigured();
    }
    return OpenAiCompatClient(configs.first).listModels(timeout: timeout);
  }

  bool _canTryNext(LlmException error, AiConfig current, AiConfig next) {
    if (error.retryable) return true;
    if (error.statusCode == 401 || error.statusCode == 403) {
      return current.apiKey != next.apiKey || current.baseUrl != next.baseUrl;
    }
    return false;
  }
}
