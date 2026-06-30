import 'dart:async';
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
    } on TimeoutException {
      throw LlmException(
        '请求超时（${timeout.inSeconds}s 未响应），请检查网络或稍后重试',
        retryable: true,
      );
    } on Exception catch (e) {
      // 网络层错误（断网 / DNS / 证书等）一律视为可重试。
      throw LlmException(
        '网络连接失败，请检查网络后重试（${_briefCause(e)}）',
        retryable: true,
      );
    }

    if (resp.statusCode >= 400) {
      throw LlmException(
        _friendlyHttpError(resp.statusCode, _extractError(resp.bodyBytes)),
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
  String? _extractError(List<int> bytes) {
    try {
      final m = jsonDecode(utf8.decode(bytes));
      if (m is Map && m['error'] is Map) {
        return m['error']['message'] as String?;
      }
      if (m is Map && m['message'] is String) {
        return m['message'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// 把 HTTP 状态码翻译成「人话」提示，并尽量带上厂商返回的细节。
  String _friendlyHttpError(int code, String? detail) {
    final d = (detail != null && detail.trim().isNotEmpty)
        ? '：${detail.trim()}'
        : '';
    switch (code) {
      case 400:
        return '请求被拒绝（400），可能是模型名或参数不被支持，请检查模型名$d';
      case 401:
        return 'API Key 无效或已失效（401），请检查 Key 是否填写正确（注意不要多粘贴或带空格）$d';
      case 403:
        return '没有访问权限（403），请确认该 Key 已开通所选模型/接口$d';
      case 404:
        return '接口地址或模型不存在（404），请检查 Base URL 与模型名$d';
      case 408:
        return '服务端处理超时（408），请稍后重试';
      case 429:
        return '请求过于频繁、已被限流（429）。免费额度有限，请等待 30~60 秒后重试';
      default:
        if (code >= 500) {
          return '模型服务暂时不可用（$code），通常是对方服务器的问题，请稍后重试$d';
        }
        return '请求失败（$code）$d';
    }
  }

  /// 取异常的简短描述，避免把超长堆栈塞进提示。
  static String _briefCause(Object e) {
    final s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  static String _trimSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;
}
