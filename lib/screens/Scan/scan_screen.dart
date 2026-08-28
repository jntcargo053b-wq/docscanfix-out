import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/app_theme.dart';
import 'scan_controller.dart';
import 'widgets/scan_loading_overlay.dart';
import 'barcode_scan_screen.dart';
import 'scan_body.dart';

/// Entry-point widget untuk scan flow.
/// Memiliki lifecycle [ScanController] dan mendelegasikan seluruh UI ke sub-widget.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final ScanController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScanController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialScan());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ─── Lifecycle Handlers ────────────────────────────────────────────────────

  Future<void> _initialScan() async {
    if (!mounted) return;
    await _controller.startScan(context);

    if (!mounted) return;
    if (!_controller.hasImages) {
      // BUG: sebelumnya langsung Navigator.pop(context) begitu hasImages
      // false — kalau startScan() gagal karena error (izin kamera, kamera
      // dipakai app lain, dll, lihat catch di ScanController.startScan()),
      // _errorMessage sudah terisi tapi layar keburu ditutup SEBELUM pesan
      // errornya sempat ditampilkan ke user sama sekali. User cuma lihat
      // layar Scan kebuka lalu langsung ketutup lagi tanpa penjelasan.
      // Fix: kalau ada errorMessage, tampilkan dulu lewat SnackBar dan
      // JANGAN auto-pop — biarkan user baca pesannya, baru tutup manual
      // lewat tombol X. Auto-pop cuma untuk kasus user membatalkan sendiri
      // (images null, tanpa error).
      final error = _controller.errorMessage;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
        _controller.clearError();
        return;
      }
      Navigator.pop(context);
    }
  }

  Future<void> _handleSave() async {
    final success = await _controller.saveDocument();
    if (!mounted) return;                          // ← cek setelah setiap async gap

    if (success) {
      // FIX (terkait P1 — Save gallery bisa menghasilkan halaman parsial):
      // saveDocument() sekarang bisa return true (dokumen berhasil
      // dikomit ke app) SEKALIGUS mengisi errorMessage dengan warning
      // non-fatal kalau sebagian/semua salinan ke galeri publik gagal —
      // lihat komentar lengkap di ScanController.saveDocument(). Sebelum
      // fix ini, cabang `if (success)` di bawah SELALU menampilkan
      // snackbar hijau generik dan langsung pop, tidak pernah mengecek
      // errorMessage sama sekali di jalur sukses — warning itu jadi tidak
      // pernah sampai ke user meski sudah disiapkan controller-nya.
      final warning = _controller.errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(warning ?? 'Berhasil disimpan ke galeri!'),
          backgroundColor: warning != null ? Colors.orange : Colors.green,
        ),
      );
      if (warning != null) _controller.clearError();
      Navigator.pop(context, true);
    } else if (_controller.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_controller.errorMessage!),
          backgroundColor: Colors.red,
        ),
      );
      _controller.clearError();
    }
  }

  Future<void> _handleShare() async {
    await _controller.shareImages();
    if (!mounted) return;
    // BUG FIX (review keseluruhan): sebelumnya tidak ada pengecekan apa pun
    // setelah shareImages() — beda dari _handleExportPdf() di bawah yang
    // sudah benar mengecek errorMessage. Kalau shareImages() gagal (lihat
    // catatan lengkap di ScanController.shareImages() soal ensureJpeg()
    // yang bisa throw untuk format tidak dikenali seperti HEIC), user
    // sebelumnya tidak pernah tahu apa-apa terjadi — "Membagikan…" cuma
    // hilang begitu saja tanpa penjelasan.
    if (_controller.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_controller.errorMessage!),
          backgroundColor: Colors.red,
        ),
      );
      _controller.clearError();
    } else if (_controller.skippedShareCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_controller.skippedShareCount} halaman dilewati (format gambar tidak dikenali).',
          ),
        ),
      );
    }
    // share sheet tidak memicu Navigator — tidak perlu cek mounted untuk itu
  }

  Future<void> _handleExportPdf() async {
    await _controller.exportPdf();
    if (!mounted) return;
    if (_controller.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_controller.errorMessage!),
          backgroundColor: Colors.red,
        ),
      );
      _controller.clearError();
    }
  }

  Future<void> _handleAddMore() async {
    if (!mounted) return;
    await _controller.startScan(context);
    // startScan tidak melakukan Navigator call — tidak perlu cek mounted setelah ini
  }

  Future<void> _handleScanBarcode() async {
    if (!mounted) return;
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (result != null && result.isNotEmpty) {
      _controller.useBarcodeTitle(result);
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: _buildAppBar(),
          body: Stack(
            children: [
              _buildBody(),
              if (_controller.isProcessing)
                ScanLoadingOverlay(message: _controller.processingStatus),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Hasil Scan'),
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Tutup',
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        if (_controller.hasImages && !_controller.isScanning)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _controller.isProcessing ? null : _handleSave,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text(
                'SIMPAN',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_controller.isScanning) {
      return const Center(child: CircularProgressIndicator())
          .animate()
          .fadeIn(duration: 300.ms);
    }

    return ScanBody(
      controller: _controller,
      onSave: _handleSave,
      onAddMore: _handleAddMore,
      onShare: _handleShare,
      onExportPdf: _handleExportPdf,
      onScanBarcode: _handleScanBarcode,
    );
  }
}
