import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'receipt_parser.dart';

/// Which API shape to speak. Provider-agnostic on purpose (ADR-049): the user
/// connects whichever LLM they prefer.
enum LlmProvider {
  /// Anthropic Messages API (api.anthropic.com/v1/messages).
  anthropic,

  /// Any OpenAI-compatible chat-completions endpoint (OpenAI, OpenRouter,
  /// Together, a local server, …). The user supplies the base URL + model.
  openAiCompatible,
}

/// AI fallback for receipt extraction (ADR-049). When the on-device read is
/// weak, send the receipt *image* to the user's chosen LLM and get the same
/// structured fields back. Opt-in, bring-your-own-key, extraction-only —
/// never posts or submits anything. A failure (no network, bad key, refusal)
/// returns null so the capture falls back to the local result.
class LlmReceiptExtractor {
  LlmReceiptExtractor({
    required this.provider,
    required this.endpoint,
    required this.model,
    required this.apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final LlmProvider provider;

  /// Base URL. Anthropic: `https://api.anthropic.com`. OpenAI-compatible: the
  /// provider's base including any version segment, e.g. `https://api.openai.com/v1`.
  final String endpoint;
  final String model;
  final String apiKey;
  final http.Client _client;

  /// Default base URLs offered in settings.
  static const anthropicBaseUrl = 'https://api.anthropic.com';
  static const openAiBaseUrl = 'https://api.openai.com/v1';

  static const _instruction =
      'You extract fields from a receipt or invoice image for bookkeeping. '
      'Return only the requested JSON. Use null for anything not clearly '
      'present — never guess. Dates as YYYY-MM-DD. Amounts as plain numbers '
      'with a dot decimal and no currency symbols or thousands separators. '
      'currency_code is the ISO code (EUR/USD/GBP) if shown.';

  /// JSON schema for the structured response. Every field nullable so the model
  /// can omit what it can't read.
  static Map<String, dynamic> get _schema => {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          for (final k in const [
            'merchant_name',
            'document_date',
            'invoice_no',
            'currency_code',
          ])
            k: {
              'type': ['string', 'null']
            },
          for (final k in const ['net_total', 'vat_total', 'grand_total'])
            k: {
              'type': ['number', 'null']
            },
        },
        'required': const [
          'merchant_name',
          'document_date',
          'invoice_no',
          'currency_code',
          'net_total',
          'vat_total',
          'grand_total',
        ],
      };

  /// Extract structured fields from [imageBytes]. Returns null on any failure
  /// (network, auth, refusal, malformed response) — the caller keeps the local
  /// parse. [ocrText] is sent as a hint when available.
  Future<ParsedReceipt?> extract({
    required Uint8List imageBytes,
    required String mimeType,
    String? ocrText,
  }) async {
    try {
      final fields = switch (provider) {
        LlmProvider.anthropic =>
          await _callAnthropic(imageBytes, mimeType, ocrText),
        LlmProvider.openAiCompatible =>
          await _callOpenAi(imageBytes, mimeType, ocrText),
      };
      if (fields == null) return null;
      return _fromJson(fields);
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();

  // — Anthropic Messages API —

  Future<Map<String, dynamic>?> _callAnthropic(
      Uint8List bytes, String mimeType, String? ocrText) async {
    final response = await _client.post(
      Uri.parse('$endpoint/v1/messages'),
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 1024,
        'system': _instruction,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': mimeType,
                  'data': base64Encode(bytes),
                },
              },
              {'type': 'text', 'text': _userText(ocrText)},
            ],
          },
        ],
        'output_config': {
          'format': {'type': 'json_schema', 'schema': _schema},
        },
      }),
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['content'];
    if (content is! List) return null;
    for (final block in content) {
      if (block is Map && block['type'] == 'text' && block['text'] is String) {
        final decoded = jsonDecode(block['text'] as String);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    }
    return null;
  }

  // — OpenAI-compatible chat completions —

  Future<Map<String, dynamic>?> _callOpenAi(
      Uint8List bytes, String mimeType, String? ocrText) async {
    final response = await _client.post(
      Uri.parse('$endpoint/chat/completions'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 1024,
        // json_object is the widely-supported response mode; the schema lives in
        // the prompt so providers without json_schema support still comply.
        'response_format': {'type': 'json_object'},
        'messages': [
          {'role': 'system', 'content': '$_instruction\n\nReturn a JSON object with keys: merchant_name, document_date, invoice_no, currency_code, net_total, vat_total, grand_total.'},
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': _userText(ocrText)},
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:$mimeType;base64,${base64Encode(bytes)}',
                },
              },
            ],
          },
        ],
      }),
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final content = (choices.first as Map)['message']?['content'];
    if (content is! String) return null;
    final decoded = jsonDecode(content);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  String _userText(String? ocrText) => ocrText == null || ocrText.trim().isEmpty
      ? 'Extract the receipt fields from this image.'
      : 'Extract the receipt fields from this image. '
          'On-device OCR read the following text, which may be partial or noisy:\n$ocrText';

  static ParsedReceipt _fromJson(Map<String, dynamic> json) {
    double? num_(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.'));
      return null;
    }

    String? str(Object? v) =>
        (v is String && v.trim().isNotEmpty) ? v.trim() : null;

    final grand = num_(json['grand_total']);
    return ParsedReceipt(
      merchantName: str(json['merchant_name']),
      documentDate: str(json['document_date']),
      invoiceNo: str(json['invoice_no']),
      currencyCode: str(json['currency_code']),
      netTotal: num_(json['net_total']),
      vatTotal: num_(json['vat_total']),
      grandTotal: grand,
      // An LLM read with a total is high-confidence; without one, low.
      confidence: grand != null ? 0.9 : 0.3,
    );
  }
}
