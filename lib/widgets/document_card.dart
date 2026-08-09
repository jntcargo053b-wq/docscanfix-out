import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../models/scanned_document.dart';
import '../theme/app_theme.dart';

class DocumentCard extends StatelessWidget {
  final ScannedDocument document;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  // FEATURE: dukungan mode pilih-banyak (multi-select) dari halaman list.
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelectToggle;

  const DocumentCard({
    super.key,
    required this.document,
    required this.onTap,
    required this.onDelete,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onLongPress,
    this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isSelectionMode ? onSelectToggle : onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.surfaceLight,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            if (isSelectionMode) ...[
              _buildCheckbox(),
              const Gap(10),
            ],
            _buildThumbnail(context),
            const Gap(14),
            Expanded(child: _buildInfo(context)),
            if (!isSelectionMode) _buildMenu(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckbox() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? AppTheme.primary : Colors.transparent,
        border: Border.all(
          color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
          width: 1.5,
        ),
      ),
      child: isSelected
          ? const Icon(Icons.check, size: 14, color: Colors.black)
          : null,
    );
  }

  // FIX (perf #1): sebelumnya pakai FileImage(File(firstImage)) langsung ke
  // DecorationImage tanpa resize sama sekali — jadi tiap row daftar dokumen
  // men-decode file JPEG resolusi kamera penuh (bisa 12–48 MP) hanya untuk
  // ditampilkan di kotak 60x60. Berat di CPU & memori tiap scroll, apalagi
  // untuk daftar dokumen panjang.
  //
  // Sekarang: (1) utamakan document.thumbnailPath — file KECIL hasil
  // ImageEnhanceService.generateThumbnail() (200x200) yang sekarang benar-
  // benar dibuat saat dokumen disimpan (lihat DocumentStorageService.
  // saveImages) — dengan fallback ke halaman pertama kalau thumbnail belum
  // ada (dokumen lama sebelum fix ini) atau filenya sudah hilang; (2) tetap
  // batasi ukuran decode lewat ResizeImage/cacheWidth sebagai jaring
  // pengaman kedua, supaya walau suatu saat thumbnailPath kosong dan jatuh
  // balik ke gambar full-res, decoder tidak pernah memuat piksel lebih
  // banyak dari yang benar-benar ditampilkan.
  Widget _buildThumbnail(BuildContext context) {
    final thumb = document.thumbnailPath;
    final fallback =
        document.imagePaths.isNotEmpty ? document.imagePaths.first : null;
    final imagePath =
        (thumb != null && File(thumb).existsSync()) ? thumb : fallback;

    ImageProvider? provider;
    if (imagePath != null) {
      // Target ukuran decode: 60dp x devicePixelRatio, dibulatkan ke atas.
      // Ini cuma jaring pengaman kedua (thumbnail asli sudah 200x200), tapi
      // tetap murah dan menghindari decode besar kalau fallback ke full-res.
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final targetPx = (60 * dpr).round();
      provider = ResizeImage(
        FileImage(File(imagePath)),
        width: targetPx,
        height: targetPx,
      );
    }

    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: AppTheme.surfaceLight,
        image: provider != null
            ? DecorationImage(image: provider, fit: BoxFit.cover)
            : null,
      ),
      child: provider == null
          ? const Icon(Icons.image_outlined, color: AppTheme.textSecondary)
          : null,
    );
  }

  Widget _buildInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          document.title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const Gap(4),
        Text(
          '${document.imagePaths.length} halaman',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        if (document.extractedText != null) ...[
          const Gap(4),
          Text(
            document.extractedText!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildMenu(BuildContext context) {
    return PopupMenuButton(
      icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
      onSelected: (value) {
        if (value == 'delete') onDelete();
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, color: AppTheme.error),
              Gap(8),
              Text('Hapus', style: TextStyle(color: AppTheme.error)),
            ],
          ),
        ),
      ],
    );
  }
}
