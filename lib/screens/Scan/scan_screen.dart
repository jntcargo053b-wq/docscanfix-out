// ✅ Correct location: lib/screens/scan/scan_screen.dart
//    (NOT lib/screens/scan_screen.dart)
//
// Final folder structure:
//   lib/screens/scan/
//   ├── scan_screen.dart         ← this file
//   ├── scan_controller.dart
//   └── widgets/
//       ├── scan_body.dart
//       ├── scan_title_input.dart
//       ├── scan_page_carousel.dart
//       ├── scan_ocr_section.dart
//       ├── scan_action_buttons.dart
//       └── scan_loading_overlay.dart

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/app_theme.dart';
import 'scan_controller.dart';               // same dir ✓
import 'widgets/scan_loading_overlay.dart';  // subdir ✓
import 'widgets/scan_body.dart';             // subdir ✓

/// Entry-point widget for the scan flow.
/// Owns the [ScanController] lifecycle and delegates all UI to sub-widgets.
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
    // Trigger camera as soon as the first frame is laid out
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialScan());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ─── Lifecycle Handlers ───────────────────────────────────────────────────────

  Future<void> _initialScan() async {
    await _controller.startScan();

    if (!mounted) return;

    // If user cancelled or scan errored without images, go back
    if (!_controller.hasImages) {
      Navigator.pop(context);
    }
  }

  Future<void> _handleSave() async {
    final success = await _controller.saveDocument();
    if (!mounted) return;

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

  // ─── Build ────────────────────────────────────────────────────────────────────

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
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
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
    );
  }
}
