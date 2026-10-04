import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';

import '../../../theme/app_theme.dart';

/// Shows OCR progress or a compact result with actions.
/// OCR processing itself remains owned by [ScanController]/[OcrService].
class ScanOcrSection extends StatelessWidget {
  const ScanOcrSection({
    super.key,
    required this.isRunning,
    required this.extractedText,
    required this.onRerun,
  });

  final bool isRunning;
  final String? extractedText;
  final VoidCallback onRerun;

  @override
  Widget build(BuildContext context) {
    if (isRunning) return const _OcrLoadingRow();
    if (extractedText != null && extractedText!.trim().isNotEmpty) {
      return _OcrResultCard(text: extractedText!, onRerun: onRerun);
    }
    return const SizedBox.shrink();
  }
}

class _OcrLoadingRow extends StatelessWidget {
  const _OcrLoadingRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceLight),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primary,
            ),
          ),
          Gap(10),
          Text(
            'Mengenali teks…',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _OcrResultCard extends StatelessWidget {
  const _OcrResultCard({
    required this.text,
    required this.onRerun,
  });

  final String text;
  final VoidCallback onRerun;

  Future<void> _copyText(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Teks OCR berhasil disalin.')),
    );
  }

  Future<void> _showFullText(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Hasil OCR'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                    ),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => _copyText(dialogContext),
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Salin'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.text_fields,
                size: 18,
                color: AppTheme.primary,
              ),
              const Gap(8),
              Expanded(
                child: Text(
                  'Hasil OCR',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'OCR ulang',
                onPressed: onRerun,
                icon: const Icon(Icons.refresh, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const Gap(8),
          Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.45,
                ),
          ),
          const Gap(8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => _showFullText(context),
                icon: const Icon(Icons.open_in_full, size: 17),
                label: const Text('Lihat Semua'),
              ),
              TextButton.icon(
                onPressed: () => _copyText(context),
                icon: const Icon(Icons.copy_outlined, size: 17),
                label: const Text('Salin'),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}
