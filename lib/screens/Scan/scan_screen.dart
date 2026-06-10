import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/app_theme.dart';
import 'scan_controller.dart';
import 'widgets/scan_loading_overlay.dart';
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
    if (!_controller.hasImages) Navigator.pop(context);
  }

  Future<void> _handleSave() async {
    final success = await _controller.saveDocument();
    if (!mounted) return;                          // ← cek setelah setiap async gap

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Berhasil disimpan ke galeri!'),
          backgroundColor: Colors.green,
        ),
      );
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
    // share sheet tidak memicu Navigator — tidak perlu cek mounted
  }

  Future<void> _handleAddMore() async {
    if (!mounted) return;
    await _controller.startScan(context);
    // startScan tidak melakukan Navigator call — tidak perlu cek mounted setelah ini
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
          TextButton(
            onPressed: _controller.isProcessing ? null : _handleSave,
            child: const Text(
              'SIMPAN',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
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
    );
  }
}
