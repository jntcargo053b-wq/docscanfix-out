import 'dart:io';

import 'package:docscan/services/pdf_service.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
      final tempDir = await Directory.systemTemp.createTemp('docscan-pdf-test-root-');
      final pathProviderChannel =
          const MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        pathProviderChannel,
        (call) async {
          if (call.method == 'getTemporaryDirectory') {
            return tempDir.path;
          }
          return null;
        },
      );

      final pdfDir = Directory('${tempDir.path}/docscan_pdf_temp');
      await pdfDir.create(recursive: true);

      final workDir = await Directory(
        '${tempDir.path}/docscan-pdf-test-${DateTime.now().microsecondsSinceEpoch}',
      ).create();

      final imagePaths = <String>[];
      final generatedChunks = <String>[];

      try {
        final bytes = img.encodeJpg(img.Image(width: 2, height: 2));

        for (int i = 0; i < 31; i++) {
          final path = '${workDir.path}/page_${i + 1}.jpg';
          await File(path).writeAsBytes(bytes);
          imagePaths.add(path);
        }

        await expectLater(
          PdfService().generatePdfChunked(
            title: 'Partial failure cleanup',
            imagePaths: imagePaths,
            pagesPerChunk: 30,
            temporaryOutput: true,
            onChunkGenerated: generatedChunks.add,
            beforeChunkWrite: (chunkIndex) async {
              if (chunkIndex == 1) {
                throw Exception('Injected second-chunk failure');
              }
            },
          ),
          throwsA(isA<Exception>()),
        );

        // Chunk pertama harus sudah berhasil dibuat.
        expect(generatedChunks, hasLength(1));

        final firstChunk = File(generatedChunks.single);

        expect(firstChunk.existsSync(), isTrue);
        expect(firstChunk.path, contains('_part1of2_'));
        expect(firstChunk.path, endsWith('.pdf'));

        // Tidak boleh ada partial file untuk chunk kedua.
        final partialFiles = await pdfDir
            .list()
            .where((entity) => entity is File)
            .where((entity) => (entity as File).path.endsWith('.part'))
            .toList();

        expect(partialFiles, isEmpty);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null);
        await workDir.delete(recursive: true);
        await tempDir.delete(recursive: true);

        for (final path in generatedChunks) {
          try {
            final file = File(path);
            if (await file.exists()) {
              await file.delete();
            }
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
