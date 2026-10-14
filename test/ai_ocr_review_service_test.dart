import 'dart:convert';

import 'package:docscan/services/ai_ocr_review_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('is disabled without a trusted HTTPS endpoint', () {
    final service = AiOcrReviewService(endpoint: '');
    expect(service.isConfigured, isFalse);
    service.dispose();
  });

  test('sends OCR text only and returns the backend suggestion', () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({'text': 'Saran yang sudah ditinjau'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = AiOcrReviewService(
      endpoint: 'https://ai-backend.example.org/review',
      client: client,
    );

    final result = await service.reviewText('Nomor invoice: 12345');

    expect(result, 'Saran yang sudah ditinjau');
    expect(captured!.method, 'POST');
    expect(captured!.headers['content-type'], contains('application/json'));
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body['text'], 'Nomor invoice: 12345');
    expect(body['language'], 'id');
    expect(body['task'], 'review_ocr_text');
    expect(body.containsKey('image'), isFalse);
    service.dispose();
    client.close();
  });

  test('rejects invalid backend responses', () async {
    final client = MockClient((_) async => http.Response('{"unexpected":true}', 200));
    final service = AiOcrReviewService(
      endpoint: 'https://ai-backend.example.org/review',
      client: client,
    );
    expect(service.reviewText('OCR text'), throwsFormatException);
    service.dispose();
    client.close();
  });

  test('rejects non-HTTPS endpoints', () {
    final service = AiOcrReviewService(endpoint: 'http://insecure.example.org/review');
    expect(service.isConfigured, isFalse);
    service.dispose();
  });
}
