import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../scan_controller.dart';
import 'scan_title_input.dart';
import 'scan_page_carousel.dart';
import 'scan_ocr_section.dart';
import 'scan_action_buttons.dart';

/// Scrollable body shown once scanning is complete.
/// Purely presentational — all callbacks are passed in.
class ScanBody extends StatelessWidget {
  const ScanBody({
    super.key,
    required this.controller,
    required this.onSave,
  });

  final ScanController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScanTitleInput(controller: controller.titleController),
          const Gap(20),
          ScanPageCarousel(
            imagePaths: controller.imagePaths,
            onRemove: controller.removeImage,
            onAddMore: () => controller.startScan(context),
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
            onExportPdf: controller.exportPdf,
            onShare: controller.shareImages,
          ),
          const Gap(32), // bottom breathing room
        ],
      ),
    );
  }
}
