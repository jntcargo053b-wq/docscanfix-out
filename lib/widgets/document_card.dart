import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'dart:io';
import '../models/scanned_document.dart';
import '../theme/app_theme.dart';

class DocumentCard extends StatelessWidget {
  final ScannedDocument document;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const DocumentCard({
    super.key,
    required this.document,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.surfaceLight),
        ),
        child: Row(
          children: [
            // Thumbnail
            _buildThumbnail(),
            const Gap(14),
            // Info
            Expanded(child: _buildInfo(context)),
            // Menu
            _buildMenu(context),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    final firstImage = document.imagePaths.isNotEmpty
        ? document.imagePaths.first
        : null;
    final file = firstImage != null ? File(firstImage) : null;

    return Container(
      width: 56,
      height: 72,
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.surfaceLight),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: file != null && file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : Container(
                color: AppTheme.surfaceLight,
                child: const Center(
                  child: Icon(Icons.description_outlined,
                      color: AppTheme.textSecondary, size: 24),
                ),
              ),
      ),
    );
  }

  Widget _buildInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          document.title,
          style: Theme.of(context).textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const Gap(4),
        Row(
          children: [
            _badge('${document.pageCount} hal', Icons.layers_outlined),
            const Gap(8),
            if (document.extractedText?.isNotEmpty ?? false)
              _badge('OCR', Icons.text_snippet_outlined, color: AppTheme.primary),
            if (document.pdfPath != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _badge('PDF', Icons.picture_as_pdf_outlined,
                    color: AppTheme.warning),
              ),
          ],
        ),
        const Gap(6),
        Text(
          _formatDate(document.createdAt),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary, size: 20),
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'open',
          child: ListTile(
            leading: Icon(Icons.open_in_new_outlined, size: 18),
            title: Text('Buka', style: TextStyle(fontSize: 14)),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline,
                size: 18, color: AppTheme.error),
            title: Text('Hapus',
                style: TextStyle(fontSize: 14, color: AppTheme.error)),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
      onSelected: (val) {
        if (val == 'open') onTap();
        if (val == 'delete') onDelete();
      },
    );
  }

  Widget _badge(String label, IconData icon,
      {Color color = AppTheme.textSecondary}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Hari ini, ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    if (diff.inDays == 1) return 'Kemarin';
    return '${date.day}/${date.month}/${date.year}';
  }
}
