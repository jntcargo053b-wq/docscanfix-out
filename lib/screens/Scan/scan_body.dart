import 'package:flutter/material.dart';

class ScanBody extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onScan;

  const ScanBody({
    super.key,
    required this.isLoading,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: isLoading ? null : onScan,
        child: Text(
          isLoading ? 'Processing...' : 'Scan Document',
        ),
      ),
    );
  }
}          ScanOcrSection(
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
