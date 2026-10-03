import 'dart:io';

import 'package:docscan/services/pdf_service.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
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


    test('cleans earlier chunks when a later chunk fails', () async {
      final tempDir = await getTemporaryDirectory();
      final pdfDir = Directory('${tempDir.path}/docscan_pdf_temp');
      await pdfDir.create(recursive: true);

      final workDir = await Directory(
        '${tempDir.path}/docscan-pdf-test-${DateTime.now().microsecondsSinceEpoch}',
      ).create();

      final imagePaths = <String>[];
      final testTitle =
          'Partial failure cleanup ${DateTime.now().microsecondsSinceEpoch}';
      try {
        final bytes = img.encodeJpg(img.Image(width: 2, height: 2));
        for (int i = 0; i < 31; i++) {
          final path = '${workDir.path}/page_${i + 1}.jpg';
          await File(path).writeAsBytes(bytes);
          imagePaths.add(path);
        }

        await expectLater(
          PdfService().generatePdfChunked(
            title: testTitle,
            imagePaths: imagePaths,
            pagesPerChunk: 30,
            temporaryOutput: true,
            beforeChunkWrite: (chunkIndex) async {
              if (chunkIndex == 1) {
                throw Exception('Injected second-chunk failure');
              }
            },
          ),
          throwsA(isA<Exception>()),
        );

        final leftovers = await pdfDir
            .list()
            .where(
              (entity) => entity.path.contains('Partial_failure_cleanup'),
            )
            .toList();
        expect(leftovers, isEmpty);
      } finally {
        await workDir.delete(recursive: true);
        final stale = pdfDir.list().where(
              (entity) =>
                  entity.path.contains('Partial_failure_cleanup_'),
            );
        await for (final entity in stale) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
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

  group('PdfService.generatePdf', () {
    test('rejects a batch when all image paths are missing', () async {
      await expectLater(
        PdfService().generatePdf(
          title: 'Missing images',
          imagePaths: const ['/path/that/does/not/exist/docscan-single-test.jpg'],
          temporaryOutput: true,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
