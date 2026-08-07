import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/bulk_share_service.dart';
import '../theme/app_theme.dart';

/// Dialog progres non-dismissible untuk operasi bulk (share/export) yang
/// berjalan di background. Didorong oleh [progress] (ValueNotifier) supaya
/// pemanggil cukup update notifier-nya tanpa perlu rebuild seluruh layar.
///
/// Menampilkan tombol Batal yang memanggil [onCancel] — proses sesungguhnya
/// baru berhenti di antara file berikutnya (lihat [BulkShareService.cancel]),
/// jadi dialog tetap terbuka sampai pemanggil menutupnya sendiri setelah
/// operasi benar-benar selesai/dibatalkan/gagal.
class BulkProgressDialog extends StatelessWidget {
  final String title;
  final ValueListenable<BulkShareProgress> progress;
  final VoidCallback onCancel;

  const BulkProgressDialog({
    super.key,
    required this.title,
    required this.progress,
    required this.onCancel,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required ValueListenable<BulkShareProgress> progress,
    required VoidCallback onCancel,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BulkProgressDialog(
        title: title,
        progress: progress,
        onCancel: onCancel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: ValueListenableBuilder<BulkShareProgress>(
          valueListenable: progress,
          builder: (context, p, _) {
            final ratio = p.total == 0 ? 0.0 : p.current / p.total;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: p.total == 0 ? null : ratio,
                    minHeight: 8,
                    backgroundColor: AppTheme.surfaceLight,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  p.total == 0
                      ? 'Menyiapkan…'
                      : '${p.current}/${p.total} • ${(ratio * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
                if (p.label.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    p.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Batalkan'),
          ),
        ],
      ),
    );
  }
}
