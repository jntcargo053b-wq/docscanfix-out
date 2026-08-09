import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import 'scan_controller.dart';
import 'widgets/scan_title_input.dart';
import 'widgets/scan_page_carousel.dart';
import 'widgets/scan_ocr_section.dart';
import 'widgets/scan_action_buttons.dart';
import '../image_editor_screen.dart';

class ScanBody extends StatelessWidget {
  const ScanBody({
    super.key,
    required this.controller,
    required this.onSave,
    required this.onAddMore,
    required this.onShare,
    required this.onScanBarcode,
  });

  final ScanController controller;
  final VoidCallback onSave;
  final VoidCallback onAddMore;
  final VoidCallback onShare;
  final Future<void> Function() onScanBarcode;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScanTitleInput(
            controller: controller.titleController,
            onAutoName: controller.useAutoTitle,
            onScanBarcode: onScanBarcode,
          ),
          const Gap(20),
          ScanPageCarousel(
            imagePaths: controller.imagePaths,
            onRemove: controller.removeImage,
            onAddMore: onAddMore,
            onEdit: (index) => _handleEdit(context, index),
          ),
          const Gap(16),
          ScanOcrSection(
            isRunning: controller.isOcrRunning,
            extractedText: controller.extractedText,
          ),
          const Gap(24),
          ScanActionButtons(
            enabled: controller.hasImages && !controller.isProcessing,
            onSave: onSave,
            onExportPdf: () => controller.exportPdf(),
            onShare: onShare,
          ),
          const Gap(32),
        ],
      ),
    );
  }

  /// Menghubungkan Image Editor ke Scan Flow: buka ImageEditorScreen untuk
  /// halaman ke-[index], lalu terapkan hasilnya (jika user menekan
  /// "Simpan" di editor) ke ScanController lewat replaceImage().
  Future<void> _handleEdit(BuildContext context, int index) async {
    final imagePaths = controller.imagePaths;
    if (index < 0 || index >= imagePaths.length) return;

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditorScreen(
          imagePath: imagePaths[index],
          pageNumber: index + 1,
        ),
      ),
    );

    // result null berarti user membatalkan (tombol close) — tidak ada
    // perubahan yang perlu diterapkan.
    if (result == null) return;
    controller.replaceImage(index, result);
  }
}
