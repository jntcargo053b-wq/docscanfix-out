import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'dart:io';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────
// ScanPreview - page thumbnail with remove button
// ─────────────────────────────────────────────
class ScanPreview extends StatelessWidget {
  final String imagePath;
  final int pageNumber;
  final VoidCallback onRemove;
  // Menghubungkan Image Editor ke Scan Flow: tap thumbnail untuk edit
  // halaman ini. Opsional supaya ScanPreview tetap bisa dipakai di tempat
  // lain tanpa fitur edit (mis. konteks read-only).
  final VoidCallback? onTap;

  const ScanPreview({
    super.key,
    required this.imagePath,
    required this.pageNumber,
    required this.onRemove,
    this.onTap,
  });

  // PERF FIX: sebelumnya Image.file(file, fit: BoxFit.cover) tanpa
  // cacheWidth/cacheHeight — thumbnail carousel ini dipakai selama Scan
  // Flow AKTIF, saat imagePath masih file kamera resolusi asli (bisa
  // 12–48 MP, belum lewat ImageEnhanceService.prepareForPdf/compress).
  // Kotak tampilnya cuma 110x160dp, tapi decoder tetap decode piksel
  // penuh tiap kali widget ini dibangun (mis. tiap scroll carousel di
  // ScanPageCarousel, atau tiap kali daftar halaman berubah) — pola bug
  // yang sama seperti yang sudah difix di DocumentCard._buildThumbnail()
  // dan ImageGrid, cuma kelewat di sini.
  // Fix: cacheWidth membatasi decoder cuma memuat piksel selebar target
  // tampil (dikali devicePixelRatio), sama seperti pola yang sudah ada di
  // DocumentCard.
  @override
  Widget build(BuildContext context) {
    final file = File(imagePath);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheW = (110 * dpr).round();
    final cacheH = (160 * dpr).round();
    return Stack(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 110,
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.surfaceLight, width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: file.existsSync()
                  ? Image.file(
                      file,
                      fit: BoxFit.cover,
                      cacheWidth: cacheW,
                      cacheHeight: cacheH,
                    )
                  : Container(
                      color: AppTheme.surface,
                      child: const Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: AppTheme.textSecondary),
                      ),
                    ),
            ),
          ),
        ),
        // Indikator kecil supaya user tahu thumbnail bisa di-tap untuk edit.
        if (onTap != null)
          Positioned(
            right: 4,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.edit, color: Colors.white, size: 12),
            ),
          ),
        // Page number badge
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Hal $pageNumber',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        // Remove button
        Positioned(
          right: 4,
          top: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: AppTheme.error,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// ScanEmptyState
// ─────────────────────────────────────────────
class ScanEmptyState extends StatelessWidget {
  final bool isSearching;
  final VoidCallback onScanPressed;
  final bool scanEnabled;

  const ScanEmptyState({
    super.key,
    required this.isSearching,
    required this.onScanPressed,
    this.scanEnabled = true,
  });

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
                isSearching
                    ? Icons.search_off_outlined
                    : Icons.document_scanner_outlined,
                size: 48,
                color: AppTheme.textSecondary,
              ),
            ),
            const Gap(20),
            Text(
              isSearching ? 'Dokumen tidak ditemukan' : 'Belum ada dokumen',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const Gap(8),
            Text(
              isSearching
                  ? 'Coba kata kunci lain'
                  : 'Tap tombol scan untuk memulai\nmemindai dokumen pertama Anda',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (!isSearching) ...[
              const Gap(28),
              ElevatedButton.icon(
                onPressed: scanEnabled ? onScanPressed : null,
                icon: const Icon(Icons.document_scanner_outlined, size: 18),
                label: const Text('Mulai Scan'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ActionButton - small icon+label button
// ─────────────────────────────────────────────
class ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;
  final Color color;
  final Color textColor;

  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
    this.color = AppTheme.primary,
    this.textColor = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: textColor,
                ),
              )
            else
              Icon(icon, size: 15, color: textColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
