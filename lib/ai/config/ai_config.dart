/// 支持的模型厂商。新增厂商只需在这里加一项 + 给一个默认 [AiConfig.preset]。
enum AiProvider {
  gemini,
  openai,
  deepseek,
  custom,
}

extension AiProviderX on AiProvider {
  String get label {
    switch (this) {
      case AiProvider.gemini:
        return 'Gemini';
      case AiProvider.openai:
        return 'OpenAI';
      case AiProvider.deepseek:
        return 'DeepSeek';
      case AiProvider.custom:
        return '自定义';
    }
  }
}

/// 一份「连到哪个模型」的完整配置。
///
/// 关键设计：所有厂商都通过 **OpenAI 兼容的 Chat Completions 协议** 接入，
/// 因此一份配置只需三要素——baseUrl / model / apiKey。换厂商 = 换这三个值，
/// 业务代码与解析逻辑完全不动。
///   - Gemini 官方兼容端点：https://generativelanguage.googleapis.com/v1beta/openai/
///   - OpenAI / DeepSeek / Kimi / OpenRouter / Groq 等均原生兼容此协议。
class AiConfig {
  final AiProvider provider;
  final String baseUrl;
  final String model;
  final String apiKey;

  const AiConfig({
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  bool get isReady => apiKey.trim().isNotEmpty && baseUrl.isNotEmpty;

  AiConfig copyWith({
    AiProvider? provider,
    String? baseUrl,
    String? model,
    String? apiKey,
  }) {
    return AiConfig(
      provider: provider ?? this.provider,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  /// 各厂商的默认 baseUrl / 默认模型。apiKey 由调用方补齐。
  static AiConfig preset(AiProvider provider, {required String apiKey, String? model}) {
    switch (provider) {
      case AiProvider.gemini:
        return AiConfig(
          provider: provider,
          baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
          model: model ?? 'gemini-2.5-flash',
          apiKey: apiKey,
        );
      case AiProvider.openai:
        return AiConfig(
          provider: provider,
          baseUrl: 'https://api.openai.com/v1',
          model: model ?? 'gpt-4o-mini',
          apiKey: apiKey,
        );
      case AiProvider.deepseek:
        return AiConfig(
          provider: provider,
          baseUrl: 'https://api.deepseek.com/v1',
          model: model ?? 'deepseek-chat',
          apiKey: apiKey,
        );
      case AiProvider.custom:
        return AiConfig(
          provider: provider,
          baseUrl: const String.fromEnvironment('AI_BASE_URL'),
          model: model ?? const String.fromEnvironment('AI_MODEL'),
          apiKey: apiKey,
        );
    }
  }

  /// 从编译期环境变量解析配置（构建时用 --dart-define 注入，绝不写进源码 / git）：
  ///   flutter run --dart-define=AI_API_KEY=xxx
  ///   可选：--dart-define=AI_PROVIDER=gemini --dart-define=AI_MODEL=gemini-2.5-flash
  ///   自定义厂商再加：--dart-define=AI_BASE_URL=https://.../v1
  factory AiConfig.fromEnvironment() {
    const key = String.fromEnvironment('AI_API_KEY');
    const providerName =
        String.fromEnvironment('AI_PROVIDER', defaultValue: 'gemini');
    const model = String.fromEnvironment('AI_MODEL');
    final provider = AiProvider.values.firstWhere(
      (p) => p.name == providerName,
      orElse: () => AiProvider.gemini,
    );
    return AiConfig.preset(
      provider,
      apiKey: key,
      model: model.isEmpty ? null : model,
    );
  }
}
