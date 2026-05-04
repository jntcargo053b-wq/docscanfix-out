import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../widgets/scan_preview.dart';

/// Horizontal carousel showing scanned pages with an "add more" card at the end.
class ScanPageCarousel extends StatelessWidget {
  const ScanPageCarousel({
    super.key,
    required this.imagePaths,
    required this.onRemove,
    required this.onAddMore,
  });

  final List<String> imagePaths;
  final void Function(int index) onRemove;
  final VoidCallback onAddMore;

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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300, width: 2),
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey.shade50,
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, color: Colors.grey),
            Gap(8),
            Text('Tambah', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
