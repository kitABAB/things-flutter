import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:things3_clone/ai/config/ai_config.dart';
import 'package:things3_clone/ai/core/llm_exception.dart';
import 'package:things3_clone/ai/core/llm_message.dart';
import 'package:things3_clone/ai/providers/openai_compat_client.dart';

void main() {
  test('Gemini 数组错误体里的日配额 429 会转成准确文案', () async {
    final client = OpenAiCompatClient(
      AiConfig.preset(AiProvider.gemini, apiKey: 'test-key'),
      httpClient: MockClient((_) async {
        return http.Response.bytes(
          utf8.encode('''
          [{
            "error": {
              "code": 429,
              "message": "Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, quotaId: GenerateRequestsPerDayPerProjectPerModel-FreeTier",
              "status": "RESOURCE_EXHAUSTED"
            }
          }]
          '''),
          429,
        );
      }),
    );

    expect(
      client.complete(const [LlmMessage.user('hi')]),
      throwsA(
        isA<LlmException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having((e) => e.retryable, 'retryable', true)
            .having((e) => e.message, 'message', contains('免费额度已用完')),
      ),
    );
  });
}
