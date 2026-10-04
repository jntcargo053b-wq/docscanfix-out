import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/scanned_document.dart';
import '../services/document_storage_service.dart';
import '../services/image_enhance_service.dart';
import '../services/pdf_service.dart';
import '../theme/app_theme.dart';
import '../widgets/image_grid.dart';

class DocumentDetailScreen extends StatefulWidget {
  final ScannedDocument document;
  const DocumentDetailScreen({super.key, required this.document});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  late ScannedDocument _doc;
  final _storageService = DocumentStorageService();
  final _pdfService = PdfService();
  final _enhanceService = ImageEnhanceService();
  bool _isSharing = false;
  bool _isExportingPdf = false;

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
  }

  // ── Share as Images ──────────────────────────────────────────────

  Future<void> _shareAsImages() async {
    // FIX: guard race condition — sebelumnya tidak ada, jadi tap cepat 2x
    // bisa memicu Share.shareXFiles() dobel sekaligus.
    if (_isSharing || _isExportingPdf) return;
    setState(() => _isSharing = true);
    try {
      // FIX (integrasi penamaan): sebelumnya XFile dibuat tanpa `name:`,
      // jadi nama file yang sampai ke aplikasi tujuan cuma ikut basename
      // aslinya di storage ("page_1.jpg", "page_2.jpg", dst — lihat
      // DocumentStorageService.saveImages) alih-alih judul dokumen. Judul
      // tidak kepakai sama sekali. Sekarang dibangun dari judul dokumen +
      // nomor urut, sama seperti pola di BulkShareService & ScanController.
      //
      // FEATURE (hilangkan label "Hal N" dari nama file saat share):
      // suffix "_hal${i+1}" sebelumnya cuma dekoratif — nomor urut biasa
      // sudah cukup untuk keunikan nama antar halaman dokumen ini.
      //
      // BUG FIX (share: "file yang dikirim bukan foto"): _doc.imagePaths
      // untuk dokumen yang disimpan SEBELUM fix di
      // DocumentStorageService.saveImages() masih bisa berupa
      // PNG/WEBP/HEIC yang cuma diberi nama "page_N.jpg" — mimeType
      // 'image/jpeg' yang di-hardcode di bawah jadi klaim salah, dan
      // aplikasi tujuan sering menampilkannya sebagai file/dokumen
      // generik, bukan foto. ensureJpeg() jadi jaring pengaman untuk
      // dokumen lama itu (fast path, tanpa decode, untuk halaman yang
      // memang sudah JPEG asli — lihat ImageEnhanceService.ensureJpeg()).
      final safeTitle = _safeFileName(_doc.title);
      final imagePaths =
          _doc.imagePaths.where((p) => File(p).existsSync()).toList();
      final generatedTempFiles = <String>{};
      final existingFiles = <XFile>[];

      for (int i = 0; i < imagePaths.length; i++) {
        final normalizedPath =
            await _enhanceService.ensureJpeg(imagePaths[i]);
        if (normalizedPath != imagePaths[i]) {
          generatedTempFiles.add(normalizedPath);
        }
        existingFiles.add(
          XFile(
            normalizedPath,
            mimeType: 'image/jpeg',
            name: '${safeTitle}_${i + 1}.jpg',
          ),
        );
      }

      try {
        if (existingFiles.isEmpty) {
          _showError('Tidak ada gambar yang tersedia');
          return;
        }

        // FEATURE (hilangkan caption "Dokumen: <judul>" saat share): subject
        // tetap dipertahankan (judul dokumen di kolom subject/email/dsb
        // masih berguna sebagai identitas), tapi text caption yang
        // mengulang "Dokumen: " dihapus — dianggap noise di atas subject
        // yang sudah ada.
        await Share.shareXFiles(existingFiles, subject: _doc.title);
      } finally {
        for (final path in generatedTempFiles) {
          try {
            await File(path).delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      _showError('Gagal berbagi gambar: $e');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  // ── Export as PDF ────────────────────────────────────────────────

  Future<void> _exportAsPdf() async {
    if (_isExportingPdf || _isSharing) return;
    setState(() => _isExportingPdf = true);
    try {
      // PERF FIX (review keseluruhan — PDF RAM untuk dokumen sangat
      // panjang): sebelumnya method ini SELALU lewat generatePdf() satu-
      // Document, tanpa pernah cek jumlah halaman — beda dari
      // BulkShareService.shareAsPdf() yang sudah benar mengalihkan
      // dokumen > PdfService.chunkPageThreshold ke generatePdfChunked().
      // Dokumen di layar detail ini justru yang paling berisiko kena
      // kasus ini: bisa terakumulasi banyak halaman dari beberapa sesi
      // "Tambah dari Galeri" (tidak ada batas jumlah di image_picker,
      // beda dari batas 10 halaman/sesi kamera scan) — closure
      // pw.Document menahan SEMUA pw.MemoryImage tiap halaman sampai
      // save() (lihat catatan lengkap di PdfService.generatePdf()), jadi
      // dokumen ratusan halaman bisa OOM di HP RAM rendah kalau tetap
      // lewat jalur satu-Document. Fix: pola sama persis dengan
      // BulkShareService.shareAsPdf() — di atas threshold, pakai
      // generatePdfChunked() (beberapa file PDF kecil, RAM per-chunk)
      // dan share semuanya sekaligus, TANPA cache ke _doc.pdfPath (satu
      // field itu cuma bisa menampung satu path — cache path pertama
      // saja akan bikin share berikutnya salah kira dokumen ini "siap"
      // padahal cuma sebagian tersimpan, sama alasan seperti di
      // BulkShareService). Regenerate tiap share untuk dokumen sepanjang
      // ini adalah trade-off yang lebih aman daripada state pdfPath yang
      // menyesatkan.
      if (_doc.pageCount > PdfService.chunkPageThreshold) {
        final chunkPaths = await _pdfService.generatePdfChunked(
          title: _doc.title,
          imagePaths: _doc.imagePaths,
          temporaryOutput: true,
        );
        final safeTitle = _safeFileName(_doc.title);
        try {
          await Share.shareXFiles(
            [
              for (int c = 0; c < chunkPaths.length; c++)
                XFile(
                  chunkPaths[c],
                  mimeType: 'application/pdf',
                  name: '${safeTitle}_bag${c + 1}dari${chunkPaths.length}.pdf',
                ),
            ],
            subject: _doc.title,
          );
        } finally {
          for (final path in chunkPaths) {
            try {
              await _pdfService.deletePdf(path);
            } catch (_) {}
          }
        }
        return;
      }

      String pdfPath;
      if (_doc.pdfPath != null && File(_doc.pdfPath!).existsSync()) {
        pdfPath = _doc.pdfPath!;
      } else {
        pdfPath = await _pdfService.generatePdf(
          title: _doc.title,
          imagePaths: _doc.imagePaths,
          extractedText: _doc.extractedText,
        );
        final updated = _doc.copyWith(pdfPath: pdfPath);
        // FIX (P1 — updateDocument() critical masih deferred): sama
        // seperti BulkShareService.shareAsPdf() — pdfPath ini hasil
        // generatePdf() yang baru selesai, immediate: true supaya tidak
        // hilang kalau app di-kill sebelum debounce jalan.
        await _storageService.updateDocument(updated, immediate: true);
        // BUG (setState setelah await tanpa mounted): baris ini sebelumnya
        // tidak dijaga mounted, beda dari setState di finally block yang
        // sudah benar — kalau user keluar dari layar detail dokumen saat
        // updateDocument() masih berjalan, setState ini bisa dipanggil
        // setelah widget di-dispose dan melempar runtime exception.
        if (!mounted) return;
        setState(() => _doc = updated);
      }

      await Share.shareXFiles(
        [
          XFile(
            pdfPath,
            mimeType: 'application/pdf',
            name: '${_safeFileName(_doc.title)}.pdf',
          ),
        ],
        subject: _doc.title,
        text: 'PDF: ${_doc.title}',
      );
    } catch (e) {
      _showError('Gagal mengekspor PDF: $e');
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  /// Bersihkan judul supaya aman dipakai sebagai nama file — sama seperti
  /// BulkShareService._safeFileName & ScanController._safeFileName, dipakai
  /// di sini juga supaya perilaku penamaan konsisten di semua jalur share
  /// (layar Scan, detail dokumen, bulk share).
  static String _safeFileName(String title) {
    final cleaned = title.trim().replaceAll(RegExp(r'[^\w\s-]'), '_');
    return cleaned.isEmpty ? 'Dokumen' : cleaned;
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.error),
    );
  }

  Future<void> _copyOcrText() async {
    final text = _doc.extractedText;
    if (text == null || text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Teks OCR berhasil disalin.')),
    );
  }

  Future<void> _showOcrText() async {
    final text = _doc.extractedText;
    if (text == null || text.trim().isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hasil OCR'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                  ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('Teks OCR berhasil disalin.')),
              );
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Salin'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: AppTheme.surface,
        titleSpacing: 0,
        actions: [
          IconButton(
            tooltip: 'Bagikan',
            icon: const Icon(Icons.share_outlined),
            onPressed: _isSharing ? null : _shareAsImages,
          ),
          IconButton(
            tooltip: 'Ekspor PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _isExportingPdf ? null : _exportAsPdf,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.layers_outlined, size: 15, color: AppTheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        '${_doc.imagePaths.length} halaman',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_doc.extractedText != null &&
                _doc.extractedText!.trim().isNotEmpty) ...[
              _OcrPreviewCard(
                text: _doc.extractedText!,
                onViewAll: _showOcrText,
                onCopy: _copyOcrText,
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: ImageGrid(
                imagePaths: _doc.imagePaths,
                onTap: (index) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _FullScreenImageViewer(
                        imagePaths: _doc.imagePaths,
                        initialIndex: index,
                        title: _doc.title,
                      ),
                      fullscreenDialog: true,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _OcrPreviewCard extends StatelessWidget {
  const _OcrPreviewCard({
    required this.text,
    required this.onViewAll,
    required this.onCopy,
  });

  final String text;
  final VoidCallback onViewAll;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.text_fields, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Teks OCR',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'Salin',
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined, size: 19),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onViewAll,
              child: const Text('Lihat Semua'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen page viewer: keeps the complete scanned page visible (no crop),
/// supports pinch-to-zoom/pan, and lets users move between document pages.
class _FullScreenImageViewer extends StatefulWidget {
  const _FullScreenImageViewer({
    required this.imagePaths,
    required this.initialIndex,
    required this.title,
  });

  final List<String> imagePaths;
  final int initialIndex;
  final String title;

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          if (widget.imagePaths.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '${_currentIndex + 1}/${widget.imagePaths.length}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imagePaths.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          return Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.file(
                File(widget.imagePaths[index]),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_outlined,
                          color: Colors.white70, size: 56),
                      SizedBox(height: 12),
                      Text(
                        'Foto tidak dapat ditampilkan',
                        style: TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
