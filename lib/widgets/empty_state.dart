import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../theme/app_theme.dart';

export 'scan_preview.dart' show ScanPreview;
export 'scan_preview.dart' show ScanEmptyState;
export 'scan_preview.dart' show ActionButton;
export 'document_card.dart';

/// Empty state generik (ikon + judul + subjudul) dipakai di halaman
/// daftar dokumen (home_screen.dart) saat belum ada / tidak ketemu dokumen.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                icon,
                size: 48,
                color: AppTheme.textSecondary,
              ),
            ),
            const Gap(20),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const Gap(8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
