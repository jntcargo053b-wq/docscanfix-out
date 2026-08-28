import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/scan_preview.dart';

/// Horizontal carousel showing scanned pages with an "add more" card at the end.
class ScanPageCarousel extends StatelessWidget {
  const ScanPageCarousel({
    super.key,
    required this.imagePaths,
    required this.onRemove,
    required this.onAddMore,
    this.onEdit,
  });

  final List<String> imagePaths;
  final void Function(int index) onRemove;
  final VoidCallback onAddMore;
  // Menghubungkan Image Editor ke Scan Flow: tap thumbnail halaman ke-[index]
  // untuk membuka Image Editor. Opsional supaya carousel ini tetap bisa
  // dipakai tanpa fitur edit.
  final void Function(int index)? onEdit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Extra slot for the "add more" card
        itemCount: imagePaths.length + 1,
        separatorBuilder: (_, __) => const Gap(12),
        itemBuilder: (ctx, i) {
          if (i == imagePaths.length) return _AddMoreCard(onTap: onAddMore);

          return ScanPreview(
            imagePath: imagePaths[i],
            pageNumber: i + 1,
            onRemove: () => onRemove(i),
            onTap: onEdit == null ? null : () => onEdit!(i),
          );
        },
      ),
    );
  }
}

class _AddMoreCard extends StatelessWidget {
  const _AddMoreCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 120,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.surfaceLight,
              width: 1.5,
            ),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined, color: AppTheme.primary, size: 28),
              Gap(10),
              Text(
                'Tambah',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
