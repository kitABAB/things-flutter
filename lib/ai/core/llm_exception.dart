/// AI 调用的统一异常类型。UI 层只需 catch 这一个类型即可给出友好降级。
class LlmException implements Exception {
  final String message;

  /// HTTP 状态码（若有）。null 表示网络层/解析层错误。
  final int? statusCode;

  /// 是否值得重试（超时、5xx、限流等瞬时错误）。
  final bool retryable;

  const LlmException(this.message, {this.statusCode, this.retryable = false});

  /// 未配置 API Key 时的语义化错误（UI 可据此引导用户去配置）。
  const LlmException.notConfigured()
      : message = '尚未配置 AI 模型的 API Key',
        statusCode = null,
        retryable = false;

  bool get isNotConfigured => statusCode == null && message.contains('API Key');

  @override
  String toString() =>
      'LlmException(${statusCode ?? '-'}): $message';
}
