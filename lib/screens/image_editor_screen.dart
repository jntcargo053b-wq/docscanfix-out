import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../services/image_enhance_service.dart';
import '../theme/app_theme.dart';

class ImageEditorScreen extends StatefulWidget {
  final String imagePath;
  final int pageNumber;

  const ImageEditorScreen({
    super.key,
    required this.imagePath,
    required this.pageNumber,
  });

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}


class _ImageEditorScreenState extends State<ImageEditorScreen> {
  final _enhanceService = ImageEnhanceService();

  late String _currentPath;
  late String _originalPath;
  bool _isProcessing = false;

  // Crop state
  bool _isCropping = false;
  Offset _cropStart = Offset.zero;
  Offset _cropEnd = Offset.zero;
  final GlobalKey _imageKey = GlobalKey();


  @override
  void initState() {
    super.initState();
    _currentPath = widget.imagePath;
    _originalPath = widget.imagePath;
    _cropStart = Offset.zero;
    _cropEnd = const Offset(1, 1);
  }

  // ── TRANSFORM ──────────────────────────────────────

  Future<void> _rotate(bool clockwise) async {
    setState(() => _isProcessing = true);
    try {
      final result = clockwise
          ? await _enhanceService.rotate90(_currentPath)
          : await _enhanceService.rotate90CCW(_currentPath);
      setState(() => _currentPath = result);
    } catch (e) {
      _showError('Gagal rotate: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _flip() async {
    setState(() => _isProcessing = true);
    try {
      final result = await _enhanceService.flipHorizontal(_currentPath);
      setState(() => _currentPath = result);
    } catch (e) {
      _showError('Gagal flip: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _applyCrop() async {
    // Validasi area crop minimal 10%
    final w = (_cropEnd.dx - _cropStart.dx).abs();
    final h = (_cropEnd.dy - _cropStart.dy).abs();
    if (w < 0.1 || h < 0.1) {
      _showError('Area crop terlalu kecil');
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final left   = _cropStart.dx.clamp(0.0, 1.0);
      final top    = _cropStart.dy.clamp(0.0, 1.0);
      final right  = _cropEnd.dx.clamp(0.0, 1.0);
      final bottom = _cropEnd.dy.clamp(0.0, 1.0);

      final result = await _enhanceService.crop(
        _currentPath,
        left:   left < right ? left : right,
        top:    top < bottom ? top : bottom,
        right:  left < right ? right : left,
        bottom: top < bottom ? bottom : top,
      );
      setState(() {
        _currentPath = result;
        _isCropping = false;
        _cropStart = Offset.zero;
        _cropEnd = const Offset(1, 1);
      });
    } catch (e) {
      _showError('Gagal crop: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _resetToOriginal() {
    setState(() {
      _currentPath = _originalPath;
      _isCropping = false;
      _cropStart = Offset.zero;
      _cropEnd = const Offset(1, 1);
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.error),
    );
  }

  // ── BUILD ───────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Edit Foto ${widget.pageNumber}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, null),
        ),
        actions: [
          TextButton(
            onPressed: _isProcessing
                ? null
                : () => Navigator.pop(context, _currentPath),
            child: const Text(
              'Simpan',
              style: TextStyle(
                  color: AppTheme.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Preview foto
          Expanded(child: _buildPreview()),

          // Controls
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Stack(
      alignment: Alignment.center,
      children: [
        GestureDetector(
          onPanStart: _isCropping
              ? (d) {
                  final box = _imageKey.currentContext?.findRenderObject()
                      as RenderBox?;
                  if (box == null) return;
                  final local = box.globalToLocal(d.globalPosition);
                  setState(() {
                    _cropStart = Offset(
                      (local.dx / box.size.width).clamp(0.0, 1.0),
                      (local.dy / box.size.height).clamp(0.0, 1.0),
                    );
                    _cropEnd = _cropStart;
                  });
                }
              : null,
          onPanUpdate: _isCropping
              ? (d) {
                  final box = _imageKey.currentContext?.findRenderObject()
                      as RenderBox?;
                  if (box == null) return;
                  final local = box.globalToLocal(d.globalPosition);
                  setState(() {
                    _cropEnd = Offset(
                      (local.dx / box.size.width).clamp(0.0, 1.0),
                      (local.dy / box.size.height).clamp(0.0, 1.0),
                    );
                  });
                }
              : null,
          child: Container(
            key: _imageKey,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 12,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_currentPath),
                fit: BoxFit.contain,
                key: ValueKey(_currentPath),
              ),
            ),
          ),
        ),

        // Crop overlay
        if (_isCropping)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final imgBox = _imageKey.currentContext?.findRenderObject()
                    as RenderBox?;
                if (imgBox == null) return const SizedBox();

                final imgPos = imgBox.localToGlobal(Offset.zero);
                final boxPos = (ctx.findRenderObject() as RenderBox?)
                    ?.localToGlobal(Offset.zero) ?? Offset.zero;
                final relativePos = imgPos - boxPos;

                final left   = relativePos.dx + _cropStart.dx * imgBox.size.width;
                final top    = relativePos.dy + _cropStart.dy * imgBox.size.height;
                final right  = relativePos.dx + _cropEnd.dx   * imgBox.size.width;
                final bottom = relativePos.dy + _cropEnd.dy   * imgBox.size.height;

                return CustomPaint(
                  painter: _CropOverlayPainter(
                    left: left, top: top, right: right, bottom: bottom,
                  ),
                );
              },
            ),
          ),

        if (_isProcessing)
          Container(
            color: Colors.black.withValues(alpha: 0.5),
            child: const CircularProgressIndicator(color: AppTheme.primary),
          ),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: _buildTransformControls(),
    );
  }

  Widget _buildTransformControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Rotate & Flip buttons
        Row(
          children: [
            Expanded(
              child: _buildActionBtn(
                icon: Icons.rotate_left,
                label: 'Putar Kiri',
                onTap: _isProcessing ? null : () => _rotate(false),
              ),
            ),
            const Gap(8),
            Expanded(
              child: _buildActionBtn(
                icon: Icons.rotate_right,
                label: 'Putar Kanan',
                onTap: _isProcessing ? null : () => _rotate(true),
              ),
            ),
            const Gap(8),
            Expanded(
              child: _buildActionBtn(
                icon: Icons.flip,
                label: 'Balik',
                onTap: _isProcessing ? null : _flip,
              ),
            ),
          ],
        ),
        const Gap(12),

        // Crop button
        if (!_isCropping)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isProcessing
                  ? null
                  : () => setState(() {
                        _isCropping = true;
                        _cropStart = Offset.zero;
                        _cropEnd = const Offset(1, 1);
                      }),
              icon: const Icon(Icons.crop, size: 18),
              label: const Text('Mulai Crop'),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _isCropping = false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: const BorderSide(color: AppTheme.textSecondary),
                  ),
                  child: const Text('Batal'),
                ),
              ),
              const Gap(8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _applyCrop,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Terapkan Crop'),
                ),
              ),
            ],
          ),
        const Gap(8),

        // Reset
        TextButton.icon(
          onPressed: _isProcessing ? null : _resetToOriginal,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Reset ke Asli'),
          style: TextButton.styleFrom(
              foregroundColor: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.primary, size: 22),
            const Gap(4),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }

}


// Crop overlay painter
class _CropOverlayPainter extends CustomPainter {
  final double left, top, right, bottom;
  _CropOverlayPainter({
    required this.left, required this.top,
    required this.right, required this.bottom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    final borderPaint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final cornerPaint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.fill;

    final l = left.clamp(0.0, size.width);
    final t = top.clamp(0.0, size.height);
    final r = right.clamp(0.0, size.width);
    final b = bottom.clamp(0.0, size.height);

    // Dim area luar crop
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, t), dimPaint);
    canvas.drawRect(Rect.fromLTWH(0, b, size.width, size.height - b), dimPaint);
    canvas.drawRect(Rect.fromLTWH(0, t, l, b - t), dimPaint);
    canvas.drawRect(Rect.fromLTWH(r, t, size.width - r, b - t), dimPaint);

    // Border crop
    canvas.drawRect(Rect.fromLTRB(l, t, r, b), borderPaint);

    // Grid lines 3x3
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;
    final w = r - l;
    final h = b - t;
    canvas.drawLine(Offset(l + w / 3, t), Offset(l + w / 3, b), gridPaint);
    canvas.drawLine(Offset(l + w * 2 / 3, t), Offset(l + w * 2 / 3, b), gridPaint);
    canvas.drawLine(Offset(l, t + h / 3), Offset(r, t + h / 3), gridPaint);
    canvas.drawLine(Offset(l, t + h * 2 / 3), Offset(r, t + h * 2 / 3), gridPaint);

    // Corner handles
    const cs = 12.0;
    for (final corner in [
      Offset(l, t), Offset(r, t), Offset(l, b), Offset(r, b)
    ]) {
      canvas.drawCircle(corner, cs / 2, cornerPaint);
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) =>
      old.left != left || old.top != top ||
      old.right != right || old.bottom != bottom;
}
