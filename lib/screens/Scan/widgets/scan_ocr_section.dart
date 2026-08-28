import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';

import '../../../theme/app_theme.dart';

/// Shows either an OCR loading indicator or the extracted text snippet.
/// Renders nothing when neither state is active.
class ScanOcrSection extends StatelessWidget {
  const ScanOcrSection({
    super.key,
    required this.isRunning,
    required this.extractedText,
  });

  final bool isRunning;
  final String? extractedText;

  @override
  Widget build(BuildContext context) {
    if (isRunning) return _OcrLoadingRow();
    if (extractedText != null) return _OcrResultCard(text: extractedText!);
    return const SizedBox.shrink();
  }
}

class _OcrLoadingRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceLight),
      ),
      child: Row(
        children: const [
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
  const _OcrResultCard({required this.text});

  final String text;

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
              Text(
                'Hasil OCR',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}
