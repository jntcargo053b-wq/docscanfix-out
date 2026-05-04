import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../theme/app_theme.dart';

/// Primary CTA + secondary action row at the bottom of the scan preview.
class ScanActionButtons extends StatelessWidget {
  const ScanActionButtons({
    super.key,
    required this.enabled,
    required this.onSave,
    required this.onExportPdf,
    required this.onShare,
  });

  final bool enabled;
  final VoidCallback onSave;
  final VoidCallback onExportPdf;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SaveButton(enabled: enabled, onPressed: onSave),
        const Gap(12),
        _SecondaryRow(
          enabled: enabled,
          onExportPdf: onExportPdf,
          onShare: onShare,
        ),
      ],
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.save_alt_rounded),
      label: const Text('SIMPAN KE GALERI'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: AppTheme.primary,
      ),
    );
  }
}

class _SecondaryRow extends StatelessWidget {
  const _SecondaryRow({
    required this.enabled,
    required this.onExportPdf,
    required this.onShare,
  });

  final bool enabled;
  final VoidCallback onExportPdf;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: enabled ? onExportPdf : null,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Ekspor PDF'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const Gap(12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: enabled ? onShare : null,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Bagikan'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
