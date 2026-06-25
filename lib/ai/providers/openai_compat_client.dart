import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/ai_config.dart';
import '../core/llm_client.dart';
import '../core/llm_exception.dart';
import '../core/llm_message.dart';

/// 基于 OpenAI 兼容 Chat Completions 协议的统一客户端。
///
/// 由于 Gemini / OpenAI / DeepSeek / Kimi / OpenRouter 等都遵循同一套
/// `POST {baseUrl}/chat/completions` 的请求/响应结构，一个实现即可服务全部厂商，
/// 差异只体现在 [AiConfig] 的 baseUrl / model 上。
class OpenAiCompatClient implements LlmClient {
  final AiConfig config;
  final http.Client _http;

  OpenAiCompatClient(this.config, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  @override
  bool get isConfigured => config.isReady;

  @override
  Future<String> complete(
    List<LlmMessage> messages, {
    bool jsonMode = false,
    double temperature = 0.2,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!config.isReady) {
      throw const LlmException.notConfigured();
    }

    final uri = Uri.parse('${_trimSlash(config.baseUrl)}/chat/completions');
    final body = <String, dynamic>{
      'model': config.model,
      'temperature': temperature,
      'messages': messages.map((m) => m.toJson()).toList(),
      if (jsonMode) 'response_format': {'type': 'json_object'},
    };

    http.Response resp;
    try {
      resp = await _http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiKey}',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on Exception catch (e) {
      // 网络层错误（超时 / 断网 / DNS）一律视为可重试。
      throw LlmException('网络请求失败：$e', retryable: true);
    }

    if (resp.statusCode >= 400) {
      throw LlmException(
        _extractError(resp.body) ?? 'HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
        retryable: resp.statusCode >= 500 || resp.statusCode == 429,
      );
    }

    final decoded = _decodeBody(resp.bodyBytes);
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const LlmException('模型未返回任何内容');
    }
    final content = choices.first['message']?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const LlmException('模型返回内容为空');
    }
    return content;
  }

  /// 强制按 UTF-8 解码，避免中文返回乱码。
  Map<String, dynamic> _decodeBody(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const LlmException('无法解析模型响应');
    }
  }

  /// 尽量从厂商的错误响应里抽出可读信息（OpenAI 风格 {error:{message}}）。
  String? _extractError(String body) {
    try {
      final m = jsonDecode(body);
      if (m is Map && m['error'] is Map) {
        return m['error']['message'] as String?;
      }
    } catch (_) {}
    return null;
  }

  static String _trimSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;
}
