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

enum _EditorTab { transform, enhance }

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  final _enhanceService = ImageEnhanceService();

  late String _currentPath;
  late String _originalPath;
  bool _isProcessing = false;

  _EditorTab _tab = _EditorTab.transform;

  // Crop state
  bool _isCropping = false;
  Offset _cropStart = Offset.zero;
  Offset _cropEnd = Offset.zero;
  final GlobalKey _imageKey = GlobalKey();

  // Compare-hold state — tekan-tahan tombol untuk lihat foto asli
  bool _showingOriginal = false;

  // Manual enhance state — nilai berjalan dari titik netral (1.0/false)
  // sejak "Terapkan" terakhir dipanggil. Lihat _applyManualEnhance().
  double _brightness = 1.0;
  double _contrast = 1.0;
  double _saturation = 1.0;
  bool _sharpen = false;
  bool _grayscale = false;

  bool get _hasPendingManualChanges =>
      _brightness != 1.0 ||
      _contrast != 1.0 ||
      _saturation != 1.0 ||
      _sharpen ||
      _grayscale;

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

  // ── ENHANCE ─────────────────────────────────────────

  /// Terapkan histogram-based auto enhance (lihat ImageEnhanceService).
  /// Adaptif terhadap kecerahan foto asli — tidak akan membakar foto yang
  /// sudah cerah jadi makin putih seperti implementasi lama.
  Future<void> _applyAutoEnhance() async {
    setState(() => _isProcessing = true);
    try {
      final result = await _enhanceService.autoEnhance(_currentPath);
      setState(() => _currentPath = result);
    } catch (e) {
      _showError('Gagal menerapkan enhance otomatis: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// "Bakar" nilai slider saat ini ke file baru lewat manualEnhance(),
  /// lalu reset slider ke titik netral. Supaya slider berikutnya selalu
  /// mulai dari 1.0/false relatif terhadap hasil yang baru saja disimpan
  /// (bukan menumpuk dari file asli setiap kali).
  Future<void> _applyManualEnhance() async {
    if (!_hasPendingManualChanges) return;

    setState(() => _isProcessing = true);
    try {
      final result = await _enhanceService.manualEnhance(
        _currentPath,
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
        sharpen: _sharpen,
        grayscale: _grayscale,
      );
      setState(() {
        _currentPath = result;
        _brightness = 1.0;
        _contrast = 1.0;
        _saturation = 1.0;
        _sharpen = false;
        _grayscale = false;
      });
    } catch (e) {
      _showError('Gagal menerapkan enhancement: $e');
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
      _brightness = 1.0;
      _contrast = 1.0;
      _saturation = 1.0;
      _sharpen = false;
      _grayscale = false;
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

          // Tab switcher + controls
          _buildTabBar(),
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
                File(_showingOriginal ? _originalPath : _currentPath),
                fit: BoxFit.contain,
                key: ValueKey(_showingOriginal ? _originalPath : _currentPath),
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

        // Tombol tekan-tahan untuk bandingkan dengan foto asli.
        // Disembunyikan saat sedang crop supaya tidak bentrok gesture.
        if (!_isCropping && _currentPath != _originalPath)
          Positioned(
            bottom: 24,
            child: GestureDetector(
              onLongPressStart: (_) => setState(() => _showingOriginal = true),
              onLongPressEnd: (_) => setState(() => _showingOriginal = false),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showingOriginal
                          ? Icons.visibility
                          : Icons.compare,
                      color: Colors.white,
                      size: 16,
                    ),
                    const Gap(6),
                    Text(
                      _showingOriginal ? 'Foto asli' : 'Tahan untuk lihat asli',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
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

  Widget _buildTabBar() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              label: 'Transform',
              icon: Icons.crop_rotate,
              selected: _tab == _EditorTab.transform,
              onTap: () => setState(() => _tab = _EditorTab.transform),
            ),
          ),
          const Gap(8),
          Expanded(
            child: _buildTabButton(
              label: 'Enhance',
              icon: Icons.tune,
              selected: _tab == _EditorTab.enhance,
              onTap: () => setState(() => _tab = _EditorTab.enhance),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withValues(alpha: 0.15) : null,
          border: Border(
            bottom: BorderSide(
              color: selected ? AppTheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? AppTheme.primary : AppTheme.textSecondary),
            const Gap(6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(0)),
      ),
      child: _tab == _EditorTab.transform
          ? _buildTransformControls()
          : _buildEnhanceControls(),
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

  Widget _buildEnhanceControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Auto enhance — histogram-based, aman untuk foto yang sudah putih
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isProcessing ? null : _applyAutoEnhance,
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('Enhance Otomatis'),
          ),
        ),
        const Gap(4),
        const Text(
          'Menyesuaikan kontras berdasarkan foto ini — aman dipakai '
          'berkali-kali, tidak akan membuat foto makin putih.',
          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
        const Gap(16),

        _buildSlider(
          label: 'Kecerahan',
          value: _brightness,
          min: 0.5,
          max: 1.5,
          onChanged: (v) => setState(() => _brightness = v),
        ),
        _buildSlider(
          label: 'Kontras',
          value: _contrast,
          min: 0.5,
          max: 1.5,
          onChanged: (v) => setState(() => _contrast = v),
        ),
        if (!_grayscale)
          _buildSlider(
            label: 'Saturasi',
            value: _saturation,
            min: 0.0,
            max: 2.0,
            onChanged: (v) => setState(() => _saturation = v),
          ),

        Row(
          children: [
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Hitam Putih',
                    style: TextStyle(fontSize: 13)),
                value: _grayscale,
                activeColor: AppTheme.primary,
                onChanged: (v) => setState(() => _grayscale = v),
              ),
            ),
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Tajamkan',
                    style: TextStyle(fontSize: 13)),
                value: _sharpen,
                activeColor: AppTheme.primary,
                onChanged: (v) => setState(() => _sharpen = v),
              ),
            ),
          ],
        ),
        const Gap(8),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_isProcessing || !_hasPendingManualChanges)
                ? null
                : _applyManualEnhance,
            child: const Text('Terapkan'),
          ),
        ),
        const Gap(8),

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

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
            Text(value.toStringAsFixed(2),
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ),
        SizedBox(
          height: 32,
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: AppTheme.primary,
            onChanged: _isProcessing ? null : onChanged,
          ),
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
