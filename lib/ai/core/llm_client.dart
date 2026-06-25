import 'llm_message.dart';

/// 厂商无关的对话补全客户端接口。
///
/// 任何模型接入只要实现这一个接口，上层（捕获解析、未来的整理建议 / 计划助手）
/// 就完全不感知背后是 Gemini 还是别的模型——这就是「未来引入别的模型」时
/// 只换实现、不动业务的关键。
abstract class LlmClient {
  /// 一次性（非流式）对话补全，返回模型输出的纯文本。
  ///
  /// [jsonMode] 为 true 时尽量要求模型输出严格 JSON（厂商支持则走
  /// response_format，否则靠 system 提示约束 + 上层做兜底解析）。
  /// [temperature] 越低越稳定，结构化抽取建议用较低值。
  Future<String> complete(
    List<LlmMessage> messages, {
    bool jsonMode = false,
    double temperature = 0.2,
    Duration timeout = const Duration(seconds: 20),
  });

  /// 当前是否具备调用条件（主要看 API Key 是否就绪），供 UI 决定是否点亮入口。
  bool get isConfigured;
}
