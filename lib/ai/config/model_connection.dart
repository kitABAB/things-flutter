import 'ai_config.dart';

/// 一个「模型连接」：一把 Key + 一个 OpenAI 兼容端点，可挂多个模型。
///
/// 设计要点：一把 Key 通常支持同厂商的多个模型（如 Gemini 的 flash / pro），
/// 因此连接里维护一份 [models] 列表（用户手填或一键拉取），上层再从中选一个
/// 当前模型。多把 Key / 多厂商则表现为多条 [ModelConnection]。
class ModelConnection {
  final String id;
  final String label;
  final AiProvider provider;
  final String baseUrl;
  final String apiKey;

  /// 该连接已知的模型 id 列表（手填或从 /models 拉取）。
  final List<String> models;

  const ModelConnection({
    required this.id,
    required this.label,
    required this.provider,
    required this.baseUrl,
    required this.apiKey,
    this.models = const [],
  });

  bool get isReady => apiKey.trim().isNotEmpty && baseUrl.isNotEmpty;

  /// 取一个「默认/首选」模型：优先列表第一项，否则回退到厂商预设模型。
  String get primaryModel =>
      models.isNotEmpty ? models.first : AiConfig.preset(provider, apiKey: '').model;

  /// 用本连接 + 指定模型拼出一份运行期 [AiConfig]。
  AiConfig configFor(String? model) => AiConfig(
        provider: provider,
        baseUrl: baseUrl,
        model: (model != null && model.trim().isNotEmpty) ? model.trim() : primaryModel,
        apiKey: apiKey,
      );

  ModelConnection copyWith({
    String? label,
    AiProvider? provider,
    String? baseUrl,
    String? apiKey,
    List<String>? models,
  }) {
    return ModelConnection(
      id: id,
      label: label ?? this.label,
      provider: provider ?? this.provider,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'provider': provider.name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'models': models,
      };

  factory ModelConnection.fromJson(Map<String, dynamic> j) {
    final providerName = j['provider'] as String? ?? AiProvider.gemini.name;
    return ModelConnection(
      id: j['id'] as String,
      label: (j['label'] as String?)?.trim().isNotEmpty == true
          ? j['label'] as String
          : providerName,
      provider: AiProvider.values.firstWhere(
        (p) => p.name == providerName,
        orElse: () => AiProvider.gemini,
      ),
      baseUrl: j['baseUrl'] as String? ?? '',
      apiKey: j['apiKey'] as String? ?? '',
      models: (j['models'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }

  /// 以厂商预设（baseUrl + 默认模型）初始化一条新连接。
  factory ModelConnection.fromProvider(
    AiProvider provider, {
    required String id,
    String? label,
    String apiKey = '',
    String? baseUrl,
  }) {
    final preset = AiConfig.preset(provider, apiKey: apiKey);
    return ModelConnection(
      id: id,
      label: (label != null && label.trim().isNotEmpty) ? label : provider.label,
      provider: provider,
      baseUrl: (baseUrl != null && baseUrl.trim().isNotEmpty)
          ? baseUrl.trim()
          : preset.baseUrl,
      apiKey: apiKey,
      models: preset.model.isNotEmpty ? [preset.model] : const [],
    );
  }
}

/// AI 的全部可切换设置：一组连接 + 当前选中的连接与模型。
class AiSettings {
  final List<ModelConnection> connections;
  final String? activeConnectionId;
  final String? activeModel;

  const AiSettings({
    this.connections = const [],
    this.activeConnectionId,
    this.activeModel,
  });

  ModelConnection? get activeConnection {
    if (connections.isEmpty) return null;
    for (final c in connections) {
      if (c.id == activeConnectionId) return c;
    }
    return connections.first;
  }

  /// 当前生效的运行期配置；无连接时回退到编译期环境变量（可能为空）。
  AiConfig get activeConfig {
    final c = activeConnection;
    if (c == null) return AiConfig.fromEnvironment();
    return c.configFor(activeModel);
  }

  bool get isReady => activeConfig.isReady;

  AiSettings copyWith({
    List<ModelConnection>? connections,
    String? activeConnectionId,
    String? activeModel,
    bool clearActive = false,
  }) {
    return AiSettings(
      connections: connections ?? this.connections,
      activeConnectionId:
          clearActive ? null : (activeConnectionId ?? this.activeConnectionId),
      activeModel: clearActive ? null : (activeModel ?? this.activeModel),
    );
  }

  Map<String, dynamic> toJson() => {
        'connections': connections.map((c) => c.toJson()).toList(),
        'activeConnectionId': activeConnectionId,
        'activeModel': activeModel,
      };

  factory AiSettings.fromJson(Map<String, dynamic> j) {
    return AiSettings(
      connections: (j['connections'] as List?)
              ?.map((e) =>
                  ModelConnection.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      activeConnectionId: j['activeConnectionId'] as String?,
      activeModel: j['activeModel'] as String?,
    );
  }
}
