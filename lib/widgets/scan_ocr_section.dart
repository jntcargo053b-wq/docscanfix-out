import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';

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
    return Row(
      children: const [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        Gap(10),
        Text(
          'Mengenali teks…',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
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
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.text_fields, size: 18, color: Colors.blue),
              Gap(8),
              Text(
                'Hasil OCR',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Gap(8),
          Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}
