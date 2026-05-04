import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';
import '../services/scanner_service.dart';
import '../services/ocr_service.dart';
import '../services/pdf_service.dart';
import '../services/document_storage_service.dart';
import '../models/scanned_document.dart';
import '../theme/app_theme.dart';
import 'image_editor_screen.dart';
import '../widgets/scan_preview.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _scannerService = ScannerService();
  final _ocrService = OcrService();
  final _pdfService = PdfService();
  final _storageService = DocumentStorageService();

  List<String> _scannedImages = [];
  String? _extractedText;
  bool _isScanning = false;
  bool _isProcessing = false;
  bool _isOcrRunning = false;
  String _processingStatus = '';
  String _documentTitle = '';
  bool _includeTextInPdf = false;

  final _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _documentTitle =
        'Scan ${now.day}-${now.month}-${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    _titleController.text = _documentTitle;
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    try {
      final images = await _scannerService.scanDocument();
      if (images != null && images.isNotEmpty) {
        setState(() {
          _scannedImages = images;
          _isScanning = false;
        });
        _runOcr();
      } else {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isScanning = false);
      if (!mounted) return;
      final errStr = e.toString();
      if (errStr.contains('PERMISSION_PERMANENTLY_DENIED')) {
        _showPermissionDialog(permanent: true);
      } else if (errStr.contains('PERMISSION_DENIED')) {
        _showPermissionDialog(permanent: false);
      } else {
        _showError('Gagal scan: $e');
        Navigator.pop(context);
      }
    }
  }

  void _showPermissionDialog({required bool permanent}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Izin Kamera Diperlukan'),
        content: Text(permanent
            ? 'Izin kamera ditolak permanen.\n\nBuka Pengaturan → Aplikasi → DocScan → Izin → aktifkan Kamera.'
            : 'Aplikasi butuh izin kamera untuk scan dokumen.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (permanent) {
                await openAppSettings();
                if (mounted) Navigator.pop(context);
              } else {
                _startScan();
              }
            },
            child: Text(permanent ? 'Buka Pengaturan' : 'Coba Lagi'),
          ),
        ],
      ),
    );
  }

  Future<void> _runOcr() async {
    setState(() {
      _isOcrRunning = true;
      _processingStatus = 'Membaca teks...';
    });
    try {
      final text = await _ocrService.extractTextFromImages(_scannedImages);
      setState(() {
        _extractedText = text;
        _isOcrRunning = false;
        _processingStatus = '';
      });
    } catch (e) {
      setState(() {
        _isOcrRunning = false;
        _processingStatus = '';
      });
    }
  }

  Future<void> _addMorePages() async {
    try {
      final images = await _scannerService.scanDocument();
      if (images != null && images.isNotEmpty) {
        setState(() => _scannedImages.addAll(images));
        _runOcr();
      }
    } catch (e) {
      _showError('Gagal menambah halaman');
    }
  }

  Future<void> _saveDocument() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showError('Masukkan judul dokumen');
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingStatus = 'Menyimpan foto ke gallery...';
    });

    try {
      final id = _storageService.generateId();
      final saved = await _storageService.saveImages(id, _scannedImages);

      await _saveToGallery(saved.imagePaths);

      setState(() => _processingStatus = 'Menyimpan dokumen...');

      final doc = ScannedDocument(
        id: id,
        title: title,
        imagePaths: saved.imagePaths,
        extractedText: _extractedText,
        createdAt: DateTime.now(),
        pdfPath: null,
        thumbnailPath: saved.thumbnailPath,
      );

      await _storageService.addDocument(doc);

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
        _processingStatus = '';
      });

      // ── Flag untuk deteksi apakah user memilih Share ──
      bool didShare = false;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 26),
              SizedBox(width: 10),
              Text('Berhasil Disimpan'),
            ],
          ),
          content: Text(
            '${saved.imagePaths.length} foto berhasil disimpan ke gallery HP kamu.',
          ),
          actions: [
            // Tombol Share
            OutlinedButton.icon(
              onPressed: () {
                // Set flag SEBELUM pop agar Navigator.pop di bawah tahu
                didShare = true;
                Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.share_outlined, size: 16),
              label: const Text('Share'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
              ),
            ),
            // Tombol OK
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      // ── Setelah dialog tertutup, baru jalankan share atau pop screen ──
      if (!mounted) return;

      if (didShare) {
        // Jalankan share dulu, baru pop screen setelah selesai
        try {
          final xfiles = saved.imagePaths
              .map((path) => XFile(path, mimeType: 'image/jpeg'))
              .toList();
          await Share.shareXFiles(
            xfiles,
            text: title.isNotEmpty ? title : 'Hasil Scan DocScan',
          );
        } catch (e) {
          if (mounted) _showError('Gagal share: $e');
        }
        // Pop screen setelah share sheet ditutup user
        if (mounted) Navigator.pop(context, true);
      } else {
        // User tekan OK, langsung pop
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _processingStatus = '';
      });
      _showError('Gagal menyimpan: $e');
    }
  }

  Future<void> _saveToGallery(List<String> paths) async {
    await _requestGalleryPermission();

    for (int i = 0; i < paths.length; i++) {
      final file = File(paths[i]);
      if (!await file.exists()) {
        throw Exception('File tidak ditemukan: ${paths[i]}');
      }

      final fileName =
          'DocScan_${DateTime.now().millisecondsSinceEpoch}_${i + 1}';

      final result = await SaverGallery.saveFile(
        filePath: file.path,
        fileName: fileName,
        androidRelativePath: 'Pictures/DocScan',
        skipIfExists: false,
      );

      if (!result.isSuccess) {
        throw Exception('Gagal simpan foto ${i + 1}: ${result.errorMessage}');
      }
    }
  }

  Future<void> _requestGalleryPermission() async {
    if (!Platform.isAndroid) return;
    final sdk = await _getSdkVersion();
    if (sdk >= 33) {
      final status = await Permission.photos.request();
      if (!status.isGranted) {
        throw Exception(
            'Izin galeri ditolak. Buka Pengaturan > Izin > Media.');
      }
    } else if (sdk < 29) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception(
            'Izin storage ditolak. Buka Pengaturan > Izin > Storage.');
      }
    }
  }

  Future<int> _getSdkVersion() async {
    try {
      final r = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse(r.stdout.toString().trim()) ?? 29;
    } catch (_) {
      return 29;
    }
  }

  Future<void> _shareImages() async {
    if (_scannedImages.isEmpty) return;
    try {
      final xfiles = _scannedImages
          .map((path) => XFile(path, mimeType: 'image/jpeg'))
          .toList();
      await Share.shareXFiles(
        xfiles,
        text: _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : 'Hasil Scan DocScan',
      );
    } catch (e) {
      if (mounted) _showError('Gagal share: $e');
    }
  }

  Future<void> _exportPdf() async {
    final title = _titleController.text.trim().isEmpty
        ? _documentTitle
        : _titleController.text.trim();

    setState(() {
      _isProcessing = true;
      _processingStatus = 'Membuat PDF...';
    });

    try {
      final id = _storageService.generateId();
      final saved = await _storageService.saveImages(id, _scannedImages);

      final pdfPath = await _pdfService.generatePdf(
        title: title,
        imagePaths: saved.imagePaths,
        extractedText: _extractedText,
        includeTextLayer: _includeTextInPdf,
      );

      setState(() {
        _isProcessing = false;
        _processingStatus = '';
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('PDF Berhasil Dibuat'),
          content: const Text('PDF sudah siap. Mau dibuka atau dibagikan?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Nanti'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _pdfService.openPdf(pdfPath);
              },
              child: const Text('Buka'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _pdfService.sharePdf(pdfPath, title);
              },
              child: const Text('Bagikan'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _processingStatus = '';
      });
      _showError('Gagal buat PDF: $e');
    }
  }

  Future<void> _editImage(int index) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditorScreen(
          imagePath: _scannedImages[index],
          pageNumber: index + 1,
        ),
      ),
    );
    if (result != null) {
      setState(() => _scannedImages[index] = result);
    }
  }

  void _removeImage(int index) {
    setState(() => _scannedImages.removeAt(index));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isScanning) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppTheme.primary),
              const Gap(16),
              Text('Membuka kamera scan...',
                  style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Hasil Scan'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_scannedImages.isNotEmpty)
            TextButton.icon(
              onPressed: _isProcessing ? null : _saveDocument,
              icon: const Icon(Icons.save_alt_outlined, size: 18),
              label: const Text('Simpan'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
        ],
      ),
      body: _isProcessing ? _buildProcessingView() : _buildPreviewView(),
    );
  }

  Widget _buildProcessingView() {
    return Container(
      color: AppTheme.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.4)),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                    color: AppTheme.primary, strokeWidth: 3),
              ),
            ),
            const Gap(24),
            Text(
              _processingStatus.isNotEmpty
                  ? _processingStatus
                  : 'Memproses...',
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Gap(8),
            const Text(
              'Mohon tunggu sebentar...',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleInput(),
          const Gap(20),
          _buildPageSection(),
          const Gap(16),
          if (_extractedText != null) _buildOcrSection(),
          if (_isOcrRunning) _buildOcrLoading(),
          const Gap(8),
          _buildActionButtons(),
          const Gap(32),
        ],
      ),
    );
  }

  Widget _buildTitleInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: TextField(
        controller: _titleController,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        decoration: const InputDecoration(
          labelText: 'Nama File',
          labelStyle:
              TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          border: InputBorder.none,
          prefixIcon:
              Icon(Icons.title, color: AppTheme.primary, size: 18),
        ),
      ),
    );
  }

  Widget _buildPageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${_scannedImages.length} Foto',
                style: Theme.of(context).textTheme.titleMedium),
            TextButton.icon(
              onPressed: _addMorePages,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Tambah'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const Gap(12),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _scannedImages.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) => Stack(
              children: [
                ScanPreview(
                  imagePath: _scannedImages[i],
                  pageNumber: i + 1,
                  onRemove: () => _removeImage(i),
                ),
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: GestureDetector(
                    onTap: () => _editImage(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune, size: 12, color: Colors.black),
                          SizedBox(width: 3),
                          Text('Edit',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOcrSection() {
    final hasText = _extractedText!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasText
              ? AppTheme.primary.withValues(alpha: 0.3)
              : AppTheme.textSecondary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasText
                    ? Icons.text_snippet_outlined
                    : Icons.text_fields,
                color:
                    hasText ? AppTheme.primary : AppTheme.textSecondary,
                size: 18,
              ),
              const Gap(8),
              Text('Teks Terdeteksi (OCR)',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (hasText)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_extractedText!.split(' ').length} kata',
                    style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const Gap(12),
          if (hasText)
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: Text(_extractedText!,
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.6)),
              ),
            )
          else
            Text('Tidak ada teks terdeteksi',
                style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildOcrLoading() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                color: AppTheme.primary, strokeWidth: 2),
          ),
          const Gap(12),
          Text('Membaca teks dengan OCR...',
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _scannedImages.isEmpty || _isProcessing
                ? null
                : _saveDocument,
            icon: const Icon(Icons.photo_library_outlined, size: 20),
            label: const Text('Simpan ke Gallery'),
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
        ),
        const Gap(12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _scannedImages.isEmpty || _isProcessing
                ? null
                : _shareImages,
            icon: const Icon(Icons.share_outlined, size: 20),
            label: const Text('Share Foto'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              foregroundColor: AppTheme.primary,
              side: const BorderSide(color: AppTheme.primary),
            ),
          ),
        ),
        const Gap(12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _scannedImages.isEmpty || _isProcessing
                ? null
                : () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        title: const Text('Export PDF'),
                        content: StatefulBuilder(
                          builder: (ctx, setDialogState) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                  'Buat file PDF dari foto scan ini?'),
                              const Gap(12),
                              if (_extractedText != null &&
                                  _extractedText!.isNotEmpty)
                                Row(
                                  children: [
                                    Checkbox(
                                      value: _includeTextInPdf,
                                      onChanged: (v) {
                                        setDialogState(() =>
                                            _includeTextInPdf =
                                                v ?? false);
                                        setState(() =>
                                            _includeTextInPdf =
                                                v ?? false);
                                      },
                                      activeColor: AppTheme.primary,
                                    ),
                                    const Text('Sertakan teks OCR',
                                        style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Batal'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _exportPdf();
                            },
                            child: const Text('Buat PDF'),
                          ),
                        ],
                      ),
                    );
                  },
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
            label: const Text('Export PDF (Opsional)'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              foregroundColor: AppTheme.textSecondary,
              side: const BorderSide(color: AppTheme.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}
