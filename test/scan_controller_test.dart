import 'package:flutter_test/flutter_test.dart';
import 'package:docscan/screens/Scan/scan_controller.dart';

void main() {
  group('ScanController basic state and title handling', () {
    late ScanController controller;

    setUp(() {
      controller = ScanController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('starts in idle state without images or OCR running', () {
      expect(controller.status, ScanStatus.idle);
      expect(controller.imagePaths, isEmpty);
      expect(controller.hasImages, isFalse);
      expect(controller.isOcrRunning, isFalse);
      expect(controller.extractedText, isNull);
    });

    test('barcode title collapses whitespace and trims edges', () {
      controller.useBarcodeTitle('  INV-001\n  CUSTOMER   MALANG  ');

      expect(controller.titleController.text, 'INV-001 CUSTOMER MALANG');
    });

    test('empty barcode result does not erase the current title', () {
      controller.titleController.text = 'Existing title';

      controller.useBarcodeTitle('  \n  ');

      expect(controller.titleController.text, 'Existing title');
    });

    test('auto title uses a zero-padded date and time including seconds', () {
      controller.useAutoTitle();

      expect(
        controller.titleController.text,
        matches(RegExp(r'^Scan \d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}$')),
      );
    });

    test('save reports the current validation error, not a stale one', () async {
      controller.titleController.clear();

      expect(await controller.saveDocument(), isFalse);
      expect(controller.errorMessage, 'Masukkan judul dokumen');

      controller.titleController.text = 'Dokumen baru';

      expect(await controller.saveDocument(), isFalse);
      expect(controller.errorMessage, 'Tidak ada gambar untuk disimpan');
    });

    test('clearError removes the current validation error', () async {
      controller.titleController.clear();

      expect(await controller.saveDocument(), isFalse);
      expect(controller.errorMessage, isNotNull);

      controller.clearError();

      expect(controller.errorMessage, isNull);
    });
  });
}
