import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Grid menampilkan thumbnail semua halaman dokumen yang sudah discan.
class ImageGrid extends StatelessWidget {
  const ImageGrid({
    super.key,
    required this.imagePaths,
    required this.onTap,
  });

  final List<String> imagePaths;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      itemCount: imagePaths.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemBuilder: (context, index) {
        final path = imagePaths[index];
        // FIX (perf #1): sebelumnya Image.file(File(path)) tanpa cacheWidth/
        // cacheHeight — grid 3-kolom ini men-decode file JPEG resolusi
        // kamera penuh (bisa 12–48 MP) per sel, padahal sel grid cuma
        // selebar ~1/3 layar. cacheWidth membatasi decoder cuma memuat
        // piksel sebesar yang benar-benar dirender (kali devicePixelRatio
        // untuk tetap tajam di layar high-DPI), jauh lebih hemat memori
        // & CPU terutama saat scroll dokumen berhalaman banyak.
        final cellWidthPx =
            (MediaQuery.of(context).size.width / 3 *
                    MediaQuery.of(context).devicePixelRatio)
                .round();
        return GestureDetector(
          onTap: () => onTap(index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    cacheWidth: cellWidthPx,
                  ),
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
