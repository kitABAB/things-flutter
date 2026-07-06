import 'package:flutter_test/flutter_test.dart';
import 'package:things3_clone/ai/config/ai_config.dart';
import 'package:things3_clone/ai/config/model_connection.dart';

void main() {
  group('AI 策略卡配置', () {
    test('云模型草稿缺 Key 时不生效', () {
      final card = ModelConnection.fromProvider(
        AiProvider.openai,
        id: 'draft',
        apiKey: '',
      );

      expect(card.primaryModel, isNotEmpty);
      expect(card.isReady, isFalse);
    });

    test('自定义网关可以无 Key，但必须有 URL 和模型', () {
      final draftGateway = const ModelConnection(
        id: 'gateway-draft',
        label: '本地网关',
        provider: AiProvider.custom,
        baseUrl: 'http://localhost:11434/v1',
        apiKey: '',
      );
      final readyGateway = draftGateway.copyWith(models: ['llama3.1']);

      expect(draftGateway.isReady, isFalse);
      expect(readyGateway.isReady, isTrue);
    });

    test('策略组只按顺序暴露配置完整的卡片', () {
      final draft = const ModelConnection(
        id: 'draft',
        label: '',
        provider: AiProvider.openai,
        baseUrl: 'https://api.openai.com/v1',
        apiKey: '',
        models: ['gpt-4.1-mini'],
      );
      final primary = ModelConnection.fromProvider(
        AiProvider.gemini,
        id: 'gemini',
        apiKey: 'g-key',
      );
      final backup = ModelConnection.fromProvider(
        AiProvider.deepseek,
        id: 'deepseek',
        apiKey: 'd-key',
      );

      final settings = AiSettings(connections: [draft, primary, backup]);

      expect(settings.readyConnections.map((e) => e.id), [
        'gemini',
        'deepseek',
      ]);
      expect(settings.activeConfig.model, primary.primaryModel);
      expect(settings.activeConfigs.map((e) => e.model), [
        primary.primaryModel,
        backup.primaryModel,
      ]);
    });
  });
}
