/// 与具体厂商无关的对话消息抽象。
///
/// 之所以自定义而不直接用某家 SDK 的类型：所有主流厂商（OpenAI / Gemini
/// 兼容端点 / DeepSeek / Kimi / OpenRouter …）的 Chat Completions 都用
/// system / user / assistant 三种角色，统一在这里即可一处定义、处处复用。
enum LlmRole { system, user, assistant }

class LlmMessage {
  final LlmRole role;
  final String content;
  const LlmMessage(this.role, this.content);

  const LlmMessage.system(this.content) : role = LlmRole.system;
  const LlmMessage.user(this.content) : role = LlmRole.user;
  const LlmMessage.assistant(this.content) : role = LlmRole.assistant;

  Map<String, dynamic> toJson() => {'role': role.name, 'content': content};
}
