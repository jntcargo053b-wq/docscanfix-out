// Test profiling ON-DEVICE untuk investigasi bottleneck OCR multi-halaman
// & memori PDF generation. HARUS dijalankan di device/emulator fisik
// (bukan headless VM test) karena:
// - google_mlkit_text_recognition butuh native ML model (Play Services).
// - ProcessInfo.currentRss di PerfProbe cuma representatif di native run.
//
// Cara jalanin (lihat juga PERF_PROFILING.md):
//   flutter test integration_test/ocr_pdf_perf_test.dart -d <device_id>
//
// Disarankan device RAM rendah/menengah (2-4GB) supaya angka RSS relevan
// dengan skenario OOM yang jadi concern. Emulator RAM tinggi bisa
// menyembunyikan masalah yang nongol di HP kelas bawah.
//
// Semua gambar sintetis dibuang otomatis setelah test (tempDir dihapus di
// tearDownAll). Laporan PerfProbe dicetak ke console lewat print() —
// salin hasilnya dari output `flutter test` untuk dianalisis.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';

import 'package:docscan/services/image_enhance_service.dart';
import 'package:docscan/services/ocr_service.dart';
import 'package:docscan/services/pdf_service.dart';
import 'package:docscan/utils/perf_probe.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('OCR + PDF perf profiling (10/20/30 halaman)', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('docscan_perf_');
    });

    tearDownAll(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    /// Bikin N gambar sintetis mendekati resolusi foto kamera dokumen asli
    /// (~2480x3508, kira-kira A4 di 300dpi) dengan teks rendered supaya
    /// MLKit punya sesuatu buat dikenali — bukan sekadar noise kosong,
    /// supaya waktu OCR yang terukur representatif terhadap dokumen nyata.
    Future<List<String>> synthesizeImages(int count) async {
      final paths = <String>[];
      for (int i = 0; i < count; i++) {
        final image = img.Image(width: 2480, height: 3508);
        img.fill(image, color: img.ColorRgb8(255, 255, 255));
        for (int line = 0; line < 30; line++) {
          img.drawString(
            image,
            'Halaman ${i + 1} baris $line - Lorem ipsum dolor sit amet consectetur adipiscing',
            font: img.arial24,
            x: 80,
            y: 100 + line * 60,
            color: img.ColorRgb8(0, 0, 0),
          );
        }
        final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 90));
        final path = '${tempDir.path}/synth_${count}_$i.jpg';
        await File(path).writeAsBytes(bytes);
        paths.add(path);
      }
      return paths;
    }

    /// Replikasi persis pipeline pipelined di
    /// ScanController._prepareAndExtractPipelined() — dijalankan langsung
    /// di luar widget tree supaya bisa diprofilkan terisolasi dari OCR UI.
    Future<void> profileOcrPipeline(int pageCount) async {
      final paths = await synthesizeImages(pageCount);
      final enhance = ImageEnhanceService();
      final ocr = OcrService();

      final probe = PerfProbe('OCR_pipeline_${pageCount}pages');
      Future<String> prepare(String p) => enhance.prepareForOcr(p);

      try {
        Future<String>? nextPrepared = prepare(paths[0]);
        for (int i = 0; i < paths.length; i++) {
          final prepared = await nextPrepared!;
          probe.mark('page $i: prepare done');

          nextPrepared =
              (i + 1 < paths.length) ? prepare(paths[i + 1]) : null;

          final text = await ocr.extractTextFromImage(prepared);
          probe.mark('page $i: ocr done (${text.length} chars)');
        }
      } finally {
        probe.finish();
        ocr.dispose();
      }
    }

    /// Profiling generatePdf() satu-file (jalur BulkShareService untuk
    /// <30 halaman, dan DocumentDetailScreen._exportAsPdf()).
    Future<void> profilePdfSingle(int pageCount) async {
      final paths = await synthesizeImages(pageCount);
      final pdfService = PdfService();
      final probe = PerfProbe('PDF_single_${pageCount}pages');
      try {
        final pdfPath = await pdfService.generatePdf(
          title: 'PerfTest$pageCount',
          imagePaths: paths,
        );
        final size = await File(pdfPath).length();
        // ignore: avoid_print
        print('  → output: ${(size / (1024 * 1024)).toStringAsFixed(1)}MB @ $pdfPath');
        await File(pdfPath).delete();
      } finally {
        probe.finish();
      }
    }

    /// Profiling generatePdfChunked() — jalur BulkShareService untuk
    /// >= PdfService.chunkPageThreshold (30) halaman.
    Future<void> profilePdfChunked(int pageCount) async {
      final paths = await synthesizeImages(pageCount);
      final pdfService = PdfService();
      final probe = PerfProbe('PDF_chunked_${pageCount}pages');
      try {
        final chunkPaths = await pdfService.generatePdfChunked(
          title: 'PerfTestChunked$pageCount',
          imagePaths: paths,
        );
        for (final p in chunkPaths) {
          final size = await File(p).length();
          // ignore: avoid_print
          print('  → chunk: ${(size / (1024 * 1024)).toStringAsFixed(1)}MB @ $p');
          await File(p).delete();
        }
      } finally {
        probe.finish();
      }
    }

    for (final n in [10, 20, 30]) {
      testWidgets('OCR pipeline — $n halaman', (tester) async {
        await profileOcrPipeline(n);
      }, timeout: const Timeout(Duration(minutes: 5)));

      testWidgets('PDF generate (single-file) — $n halaman', (tester) async {
        await profilePdfSingle(n);
      }, timeout: const Timeout(Duration(minutes: 5)));
    }

    // 30 halaman = persis di chunkPageThreshold, ini jalur yang dipakai
    // BulkShareService.shareAsPdf() secara nyata pada N ini.
    testWidgets('PDF generateChunked — 30 halaman (di threshold)',
        (tester) async {
      await profilePdfChunked(30);
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
