import 'dart:io';

import 'package:docscan/services/pdf_service.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

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

    test('preserves earlier chunks when a later chunk fails', () async {
      final tempDir = await getTemporaryDirectory();
      final pdfDir = Directory('${tempDir.path}/docscan_pdf_temp');
      await pdfDir.create(recursive: true);

      final workDir = await Directory(
        '${tempDir.path}/docscan-pdf-test-${DateTime.now().microsecondsSinceEpoch}',
      ).create();

      final imagePaths = <String>[];
      final uniqueId = DateTime.now().microsecondsSinceEpoch;
      final testTitle = 'Partial failure cleanup $uniqueId';

      // Snapshot the directory so the assertion is based on files actually
      // created by this invocation, not on the production filename sanitizer.
      final beforePaths = <String>{
        ...await pdfDir
            .list()
            .whereType<File>()
            .map((file) => file.path)
            .toList(),
      };

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

        final afterPaths = <String>{
          ...await pdfDir
              .list()
              .whereType<File>()
              .map((file) => file.path)
              .toList(),
        };
        final createdPaths = afterPaths.difference(beforePaths);

        expect(createdPaths, hasLength(1));
        expect(createdPaths.single, contains('_part1of2_'));
        expect(createdPaths.single, endsWith('.pdf'));

        final createdPartialFiles = createdPaths
            .where((path) => path.endsWith('.part'))
            .toList();
        expect(createdPartialFiles, isEmpty);
      } finally {
        await workDir.delete(recursive: true);
        final afterCleanupPaths = <String>{
          ...await pdfDir
              .list()
              .whereType<File>()
              .map((file) => file.path)
              .toList(),
        };
        for (final path in afterCleanupPaths.difference(beforePaths)) {
          try {
            await File(path).delete();
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
