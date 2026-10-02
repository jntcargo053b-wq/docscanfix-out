import 'package:docscan/services/pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PdfService.generatePdfChunked', () {
    test('rejects a non-positive pagesPerChunk before filesystem work', () async {
      await expectLater(
        PdfService().generatePdfChunked(
          title: 'Invalid chunk size',
          imagePaths: const ['unused-image.jpg'],
          pagesPerChunk: 0,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a batch when all image paths are missing', () async {
      await expectLater(
        PdfService().generatePdfChunked(
          title: 'Missing images',
          imagePaths: const ['/path/that/does/not/exist/docscan-test.jpg'],
          temporaryOutput: true,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
