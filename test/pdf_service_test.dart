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
  });
}
