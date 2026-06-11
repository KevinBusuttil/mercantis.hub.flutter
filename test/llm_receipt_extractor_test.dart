import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercantis_hub_app/capture/llm_receipt_extractor.dart';

/// ADR-049: the provider-agnostic AI fallback. Driven through MockClient so the
/// request shape and response parsing are verified without any network.
void main() {
  final image = Uint8List.fromList(List.filled(32, 7));
  const fields = {
    'merchant_name': 'BP Service Station',
    'document_date': '2026-03-14',
    'invoice_no': '4471',
    'currency_code': 'EUR',
    'net_total': 38.39,
    'vat_total': 6.91,
    'grand_total': 45.30,
  };

  test('Anthropic: posts to /v1/messages with the key and parses the result',
      () async {
    Uri? seenUrl;
    String? seenKey;
    final client = MockClient((req) async {
      seenUrl = req.url;
      seenKey = req.headers['x-api-key'];
      return http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': jsonEncode(fields)},
          ],
        }),
        200,
      );
    });

    final extractor = LlmReceiptExtractor(
      provider: LlmProvider.anthropic,
      endpoint: LlmReceiptExtractor.anthropicBaseUrl,
      model: 'claude-opus-4-8',
      apiKey: 'secret-key',
      client: client,
    );
    final result =
        await extractor.extract(imageBytes: image, mimeType: 'image/jpeg');

    expect(seenUrl.toString(), 'https://api.anthropic.com/v1/messages');
    expect(seenKey, 'secret-key');
    expect(result, isNotNull);
    expect(result!.merchantName, 'BP Service Station');
    expect(result.grandTotal, 45.30);
    expect(result.currencyCode, 'EUR');
    expect(result.confidence, 0.9);
  });

  test('OpenAI-compatible: posts to /chat/completions with a Bearer token',
      () async {
    Uri? seenUrl;
    String? seenAuth;
    final client = MockClient((req) async {
      seenUrl = req.url;
      seenAuth = req.headers['authorization'];
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': jsonEncode(fields)},
            },
          ],
        }),
        200,
      );
    });

    final extractor = LlmReceiptExtractor(
      provider: LlmProvider.openAiCompatible,
      endpoint: LlmReceiptExtractor.openAiBaseUrl,
      model: 'gpt-4o-mini',
      apiKey: 'sk-test',
      client: client,
    );
    final result =
        await extractor.extract(imageBytes: image, mimeType: 'image/png');

    expect(seenUrl.toString(), 'https://api.openai.com/v1/chat/completions');
    expect(seenAuth, 'Bearer sk-test');
    expect(result!.grandTotal, 45.30);
    expect(result.invoiceNo, '4471');
  });

  test('a non-200 response yields null (caller keeps the local read)', () async {
    final client = MockClient((_) async => http.Response('nope', 401));
    final extractor = LlmReceiptExtractor(
      provider: LlmProvider.anthropic,
      endpoint: LlmReceiptExtractor.anthropicBaseUrl,
      model: 'claude-opus-4-8',
      apiKey: 'k',
      client: client,
    );
    expect(
        await extractor.extract(imageBytes: image, mimeType: 'image/jpeg'),
        isNull);
  });

  test('a malformed body is swallowed and yields null', () async {
    final client = MockClient((_) async => http.Response('{not json', 200));
    final extractor = LlmReceiptExtractor(
      provider: LlmProvider.anthropic,
      endpoint: LlmReceiptExtractor.anthropicBaseUrl,
      model: 'claude-opus-4-8',
      apiKey: 'k',
      client: client,
    );
    expect(
        await extractor.extract(imageBytes: image, mimeType: 'image/jpeg'),
        isNull);
  });
}
