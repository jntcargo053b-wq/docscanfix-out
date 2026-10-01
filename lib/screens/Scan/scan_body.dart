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
    required this.onExportPdf,
    required this.onScanBarcode,
  });

  final ScanController controller;
  final VoidCallback onSave;
  final VoidCallback onAddMore;
  final VoidCallback onShare;
  final VoidCallback onExportPdf;
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
          const Gap(12),
          _ScanLocationCard(controller: controller),
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
            onExportPdf: onExportPdf,
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


class _ScanLocationCard extends StatelessWidget {
  const _ScanLocationCard({required this.controller});

  final ScanController controller;

  @override
  Widget build(BuildContext context) {
    final location = controller.scanLocation;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on_outlined, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: location == null
                ? const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Koordinat lokasi belum tersedia', style: TextStyle(fontWeight: FontWeight.w600)),
                      SizedBox(height: 3),
                      Text('Aktifkan GPS dan izinkan akses lokasi. Scan tetap dapat disimpan tanpa koordinat.',
                          style: TextStyle(fontSize: 12)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Lokasi pemindaian', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      SelectableText(
                        '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Akurasi ±${location.accuracyMeters.toStringAsFixed(0)} m',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
