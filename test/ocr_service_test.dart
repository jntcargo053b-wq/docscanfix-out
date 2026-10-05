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
  test('callback errors do not stop remaining OCR pages', () async {
    final service = OcrService();
    final completed = <int>{};

    await service.extractTextFromImages(
      const [
        '/docscan/missing-callback-1.jpg',
        '/docscan/missing-callback-2.jpg',
        '/docscan/missing-callback-3.jpg',
      ],
      onPageCompleted: (index, _) {
        completed.add(index);
        if (index == 0) throw StateError('simulated UI callback failure');
      },
    );

    expect(completed, {0, 1, 2});
  });

  test('reports cancelled pages without starting OCR work', () async {
    final service = OcrService();
    final completed = <int, OcrPageResult>{};

    await service.extractTextFromImages(
      const [
        '/docscan/cancelled-1.jpg',
        '/docscan/cancelled-2.jpg',
        '/docscan/cancelled-3.jpg',
      ],
      isCancelled: () => true,
      onPageCompleted: (index, result) {
        completed[index] = result;
      },
    );

    expect(completed.keys, {0, 1, 2});
    expect(
      completed.values.every(
        (result) =>
            result.success == false &&
            result.errorMessage == 'Dibatalkan sebelum diproses.',
      ),
      isTrue,
    );
  });
}
