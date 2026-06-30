import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'ai_config.dart';
import 'model_connection.dart';

/// AI 配置的本地持久化（shared_preferences）。
///
/// v2：保存一组「模型连接」+ 当前选中的连接/模型，支持多 Key / 多模型并存。
/// 兼容 v1：若检测到旧的单配置键（[_kApiKey] 等），自动迁移成一条连接。
/// 注意：API Key 以明文存于本机偏好设置，仅作单机便利之用。
class AiSettingsStore {
  static const _kSettings = 'ai_settings_v2';

  // v1（旧单配置）键，仅用于迁移。
  static const _kProvider = 'ai_provider';
  static const _kModel = 'ai_model';
  static const _kBaseUrl = 'ai_base_url';
  static const _kApiKey = 'ai_api_key';

  /// 读取设置；未保存过任何连接则返回空 [AiSettings]（调用方再回退到环境变量）。
  static Future<AiSettings> load() async {
    final p = await SharedPreferences.getInstance();

    final raw = p.getString(_kSettings);
    if (raw != null && raw.isNotEmpty) {
      try {
        return AiSettings.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {
        // 损坏则当作空，避免崩溃。
      }
    }

    // 迁移 v1 单配置。
    final migrated = await _migrateV1(p);
    if (migrated != null) {
      await save(migrated);
      return migrated;
    }

    return const AiSettings();
  }

  static Future<AiSettings?> _migrateV1(SharedPreferences p) async {
    final key = p.getString(_kApiKey);
    if (key == null || key.trim().isEmpty) return null;

    final providerName = p.getString(_kProvider) ?? AiProvider.gemini.name;
    final provider = AiProvider.values.firstWhere(
      (e) => e.name == providerName,
      orElse: () => AiProvider.gemini,
    );
    final model = p.getString(_kModel);
    final baseUrl = p.getString(_kBaseUrl);

    var conn = ModelConnection.fromProvider(
      provider,
      id: 'migrated-${DateTime.now().millisecondsSinceEpoch}',
      apiKey: key,
      baseUrl: (baseUrl != null && baseUrl.isNotEmpty) ? baseUrl : null,
    );
    if (model != null && model.isNotEmpty) {
      conn = conn.copyWith(models: {model, ...conn.models}.toList());
    }
    return AiSettings(
      connections: [conn],
      activeConnectionId: conn.id,
      activeModel: (model != null && model.isNotEmpty) ? model : conn.primaryModel,
    );
  }

  static Future<void> save(AiSettings settings) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSettings, jsonEncode(settings.toJson()));
    // 迁移完成后清掉旧键，避免下次重复迁移。
    await p.remove(_kProvider);
    await p.remove(_kModel);
    await p.remove(_kBaseUrl);
    await p.remove(_kApiKey);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSettings);
  }
}
