import 'package:docscan/services/ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('reports each failed page without aborting the batch', () async {
    final service = OcrService();
    final completed = <int, OcrPageResult>{};

    final text = await service.extractTextFromImages(
      const [
        '/docscan/missing-page-1.jpg',
        '/docscan/missing-page-2.jpg',
        '/docscan/missing-page-3.jpg',
      ],
      onPageCompleted: (index, result) {
        completed[index] = result;
      },
    );

    expect(text, isEmpty);
    expect(completed.keys, {0, 1, 2});

    for (final result in completed.values) {
      expect(result.success, isFalse);
      expect(result.text, isEmpty);
      expect(result.errorMessage, isNotNull);
    }
  });
}
