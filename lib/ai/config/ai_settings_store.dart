import 'package:shared_preferences/shared_preferences.dart';

import 'ai_config.dart';

/// AI 配置的本地持久化（shared_preferences）。
///
/// 让用户「填一次就记住」：保存后下次启动自动读取，无需每次 --dart-define。
/// 注意：API Key 以明文存于本机偏好设置，仅作单机便利之用。
class AiSettingsStore {
  static const _kProvider = 'ai_provider';
  static const _kModel = 'ai_model';
  static const _kBaseUrl = 'ai_base_url';
  static const _kApiKey = 'ai_api_key';

  /// 读取已保存的配置；未保存过 Key 则返回 null（由调用方回退到环境变量）。
  static Future<AiConfig?> load() async {
    final p = await SharedPreferences.getInstance();
    final key = p.getString(_kApiKey);
    if (key == null || key.trim().isEmpty) return null;

    final providerName = p.getString(_kProvider) ?? AiProvider.gemini.name;
    final provider = AiProvider.values.firstWhere(
      (e) => e.name == providerName,
      orElse: () => AiProvider.gemini,
    );
    final model = p.getString(_kModel);
    final baseUrl = p.getString(_kBaseUrl);

    var cfg = AiConfig.preset(
      provider,
      apiKey: key,
      model: (model != null && model.isNotEmpty) ? model : null,
    );
    if (baseUrl != null && baseUrl.isNotEmpty) {
      cfg = cfg.copyWith(baseUrl: baseUrl);
    }
    return cfg;
  }

  static Future<void> save(AiConfig config) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kProvider, config.provider.name);
    await p.setString(_kModel, config.model);
    await p.setString(_kBaseUrl, config.baseUrl);
    await p.setString(_kApiKey, config.apiKey);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kProvider);
    await p.remove(_kModel);
    await p.remove(_kBaseUrl);
    await p.remove(_kApiKey);
  }
}
