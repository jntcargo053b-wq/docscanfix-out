import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../theme/app_theme.dart';

/// Text field nama dokumen, dilengkapi 3 pilihan sumber penamaan:
/// - Otomatis: judul berbasis tanggal/jam saat ini (default)
/// - Manual: user ketik sendiri
/// - Scan Barcode: nama diambil dari hasil scan barcode/QR (mis. nomor
///   resi, nomor invoice, kode barang) — tetap bisa diedit manual setelahnya
class ScanTitleInput extends StatefulWidget {
  const ScanTitleInput({
    super.key,
    required this.controller,
    required this.onAutoName,
    required this.onScanBarcode,
  });

  final TextEditingController controller;

  /// Dipanggil saat user memilih opsi "Otomatis" — isi ulang field dengan
  /// judul berbasis waktu saat ini.
  final VoidCallback onAutoName;

  /// Dipanggil saat user memilih opsi "Scan Barcode" — pemanggil
  /// bertanggung jawab membuka layar scanner dan mengisi [controller]
  /// kalau berhasil.
  final Future<void> Function() onScanBarcode;

  @override
  State<ScanTitleInput> createState() => _ScanTitleInputState();
}

class _ScanTitleInputState extends State<ScanTitleInput> {
  final _focusNode = FocusNode();
  bool _isScanningBarcode = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleScanBarcode() async {
    if (_isScanningBarcode) return;
    setState(() => _isScanningBarcode = true);
    try {
      await widget.onScanBarcode();
    } finally {
      if (mounted) setState(() => _isScanningBarcode = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nama dokumen dari',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const Gap(8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _NamingSourceChip(
              icon: Icons.auto_awesome_outlined,
              label: 'Otomatis',
              onTap: widget.onAutoName,
            ),
            _NamingSourceChip(
              icon: Icons.edit_outlined,
              label: 'Manual',
              onTap: () => _focusNode.requestFocus(),
            ),
            _NamingSourceChip(
              icon: Icons.qr_code_scanner_outlined,
              label: 'Scan Barcode',
              isLoading: _isScanningBarcode,
              onTap: _handleScanBarcode,
            ),
          ],
        ),
        const Gap(10),
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Nama Dokumen',
            prefixIcon: const Icon(Icons.drive_file_rename_outline, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _NamingSourceChip extends StatelessWidget {
  const _NamingSourceChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceLight,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary,
                  ),
                )
              else
                Icon(icon, size: 15, color: AppTheme.primary),
              const Gap(6),
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
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
