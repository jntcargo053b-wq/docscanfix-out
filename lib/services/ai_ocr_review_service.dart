import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Optional AI review of recognized text via a trusted application backend.
///
/// The Hugging Face token must remain on the backend; this client never stores
/// or sends provider credentials. Only OCR text is sent, never image bytes.
class AiOcrReviewService {
  AiOcrReviewService({
    String endpoint = const String.fromEnvironment('DOCSCAN_AI_OCR_ENDPOINT'),
    http.Client? client,
    Duration timeout = const Duration(seconds: 45),
  })  : _endpoint = endpoint.trim(),
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _timeout = timeout;

  final String _endpoint;
  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;

  bool get isConfigured {
    final uri = Uri.tryParse(_endpoint);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        !uri.host.toLowerCase().endsWith('.example');
  }

  Future<String> reviewText(String text) async {
    if (!isConfigured) {
      throw StateError('Endpoint AI OCR belum dikonfigurasi dengan HTTPS.');
    }
    final input = text.trim();
    if (input.isEmpty) throw ArgumentError.value(text, 'text', 'Tidak boleh kosong.');

    final response = await _client
        .post(
          Uri.parse(_endpoint),
          headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({'text': input, 'language': 'id', 'task': 'review_ocr_text'}),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw HttpException('AI endpoint mengembalikan status ${response.statusCode}.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic> || decoded['text'] is! String) {
      throw const FormatException('Respons AI harus berupa objek JSON dengan field text.');
    }
    final result = (decoded['text'] as String).trim();
    if (result.isEmpty) throw const FormatException('Saran AI kosong.');
    return result;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
