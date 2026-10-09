import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/scanned_document.dart';
import '../services/document_storage_service.dart';
import '../services/image_enhance_service.dart';
import '../services/ocr_service.dart';
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
  bool _isFullOcrRunning = false;
  final Set<int> _ocrPageRetries = <int>{};
  late List<String> _pageOcrTexts;

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
    _pageOcrTexts = List<String>.generate(
      _doc.imagePaths.length,
      (index) => index < _doc.pageTexts.length ? _doc.pageTexts[index] : '',
    );
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
          pageTexts: _doc.pageTexts,
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
          pageTexts: _doc.pageTexts,
          extractedText: _doc.extractedText,
          includeTextLayer: _doc.pageTexts.length == _doc.imagePaths.length,
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

  Future<void> _rerunOcrPage(int index, {VoidCallback? refreshDialog}) async {
    if (_ocrPageRetries.contains(index) ||
        index < 0 ||
        index >= _doc.imagePaths.length ||
        _doc.pageTexts.length != _doc.imagePaths.length) {
      return;
    }

    setState(() => _ocrPageRetries.add(index));
    try {
      final prepared =
          await _enhanceService.prepareForOcr(_doc.imagePaths[index]);
      String text;
      try {
        text = await OcrService().extractTextFromImage(prepared);
        if (text.trim().isEmpty) {
          String? enhanced;
          try {
            final enhancedPath =
                await _enhanceService.prepareForOcrEnhanced(_doc.imagePaths[index]);
            try {
              enhanced = await OcrService().extractTextFromImage(enhancedPath);
            } finally {
              try {
                await File(enhancedPath).delete();
              } catch (_) {}
            }
          } catch (_) {}
          text = enhanced?.trim().isNotEmpty == true
              ? enhanced!
              : await OcrService().extractTextFromImage(_doc.imagePaths[index]);
        }
      } finally {
        try {
          await File(prepared).delete();
        } catch (_) {}
      }
      final updatedPages = List<String>.from(_pageOcrTexts);
      updatedPages[index] = text;
      final aggregate = <String>[];
      for (var pageIndex = 0; pageIndex < updatedPages.length; pageIndex++) {
        final pageText = updatedPages[pageIndex].trim();
        if (pageText.isNotEmpty) {
          aggregate.add(
            '--- Halaman ${pageIndex + 1} ---\n$pageText',
          );
        }
      }
      final updated = _doc.copyWith(
        pageTexts: updatedPages,
        extractedText: aggregate.isEmpty ? null : aggregate.join('\n\n'),
      );
      await _storageService.updateDocument(updated, immediate: true);
      if (!mounted) return;
      setState(() {
        _doc = updated;
        _pageOcrTexts = updatedPages;
      });
      refreshDialog?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'OCR halaman ${index + 1} gagal: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _ocrPageRetries.remove(index));
        refreshDialog?.call();
      }
    }
  }

  Future<void> _rerunOcrAllPages() async {
    if (_isFullOcrRunning || _isSharing || _isExportingPdf) return;

    setState(() => _isFullOcrRunning = true);
    final originalPaths = List<String>.from(_doc.imagePaths);
    final preparedPaths = <String>[];
    final tempPaths = <String>{};

    try {
      for (final path in originalPaths) {
        final prepared = await _enhanceService.prepareForOcr(path);
        preparedPaths.add(prepared);
        tempPaths.add(prepared);
        if (!mounted) return;
      }

      final pageTexts = List<String>.filled(originalPaths.length, '');
      await OcrService().extractTextFromImages(
        preparedPaths,
        isCancelled: () => !mounted,
        onPageCompleted: (index, result) {
          if (index < pageTexts.length) pageTexts[index] = result.text;
        },
      );

      final fallbackPaths = <String>[];
      final fallbackIndexes = <int>[];
      for (var i = 0; i < pageTexts.length; i++) {
        if (pageTexts[i].trim().isEmpty) {
          fallbackPaths.add(originalPaths[i]);
          fallbackIndexes.add(i);
        }
      }
      if (fallbackPaths.isNotEmpty) {
        final enhancedPaths = <String>[];
        try {
          for (final path in fallbackPaths) {
            if (!mounted) return;
            enhancedPaths.add(
              await _enhanceService.prepareForOcrEnhanced(path),
            );
          }
          await OcrService().extractTextFromImages(
            enhancedPaths,
            isCancelled: () => !mounted,
            onPageCompleted: (index, result) {
              if (index < fallbackIndexes.length) {
                pageTexts[fallbackIndexes[index]] = result.text;
              }
            },
          );

          final originalRetryPaths = <String>[];
          final originalRetryIndexes = <int>[];
          for (var i = 0; i < fallbackIndexes.length; i++) {
            final pageIndex = fallbackIndexes[i];
            if (pageTexts[pageIndex].trim().isEmpty) {
              originalRetryPaths.add(fallbackPaths[i]);
              originalRetryIndexes.add(pageIndex);
            }
          }
          if (originalRetryPaths.isNotEmpty) {
            await OcrService().extractTextFromImages(
              originalRetryPaths,
              isCancelled: () => !mounted,
              onPageCompleted: (index, result) {
                if (index < originalRetryIndexes.length) {
                  pageTexts[originalRetryIndexes[index]] = result.text;
                }
              },
            );
          }
        } finally {
          await Future.wait(
            enhancedPaths.map(
              (path) async {
                try {
                  await File(path).delete();
                } catch (_) {}
              },
            ),
          );
        }
      }

      if (!mounted) return;
      final aggregate = <String>[];
      for (var i = 0; i < pageTexts.length; i++) {
        final text = pageTexts[i].trim();
        if (text.isNotEmpty) {
          aggregate.add('--- Halaman ' + (i + 1).toString() + '\n' + text);
        }
      }

      final oldPdfPath = _doc.pdfPath;
      final updated = _doc.copyWith(
        pageTexts: pageTexts,
        extractedText: aggregate.isEmpty ? null : aggregate.join('\n\n'),
        clearPdfPath: true,
      );
      await _storageService.updateDocument(updated, immediate: true);
      if (!mounted) return;

      setState(() {
        _doc = updated;
        _pageOcrTexts = pageTexts;
      });

      if (oldPdfPath != null) {
        try {
          await File(oldPdfPath).delete();
        } catch (_) {}
      }

      if (aggregate.isEmpty) {
        _showError('OCR selesai, tetapi tidak ada teks yang terdeteksi.');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OCR seluruh dokumen berhasil diperbarui.')),
        );
      }
    } catch (e) {
      if (mounted) _showError('OCR seluruh dokumen gagal: $e');
    } finally {
      for (final path in tempPaths) {
        try { await File(path).delete(); } catch (_) {}
      }
      if (mounted) setState(() => _isFullOcrRunning = false);
    }
  }

  Future<void> _showPageOcr() async {
    final hasPageData = _doc.pageTexts.length == _doc.imagePaths.length;
    if (!hasPageData) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('OCR per halaman'),
          content: const Text(
            'Dokumen ini dibuat sebelum OCR per halaman disimpan. '
            'Semua foto halaman masih tersedia, jadi OCR dapat dijalankan '
            'langsung dari sini tanpa kembali ke layar Scan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _rerunOcrAllPages();
              },
              icon: const Icon(Icons.text_snippet_outlined),
              label: const Text('OCR Semua Halaman'),
            ),
          ],
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('OCR per halaman'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _doc.imagePaths.length,
            separatorBuilder: (_, __) => const Divider(height: 16),
            itemBuilder: (context, index) {
              final text = _pageOcrTexts[index].trim();
              final retrying = _ocrPageRetries.contains(index);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 16,
                  child: Text('${index + 1}'),
                ),
                title: Text(
                  text.isEmpty ? 'Tidak ada teks terdeteksi' : text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  text.isEmpty ? 'Belum ada hasil OCR' : 'OCR tersedia',
                ),
                trailing: IconButton(
                  tooltip: 'OCR ulang halaman ini',
                  onPressed: retrying
                      ? null
                      : () => _rerunOcrPage(
                            index,
                            refreshDialog: () => setDialogState(() {}),
                          ),
                  icon: retrying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Tutup'),
          ),
        ],
        ),
      ),
    );
  }
  Future<void> _managePages() async {
    if (_isSharing || _isExportingPdf || _doc.imagePaths.length < 2) return;

    final hasPageTexts = _doc.pageTexts.length == _doc.imagePaths.length;
    final workingPaths = List<String>.from(_doc.imagePaths);
    final workingTexts = hasPageTexts
        ? List<String>.from(_doc.pageTexts)
        : <String>[];

    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Atur halaman'),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.sizeOf(dialogContext).height * 0.62,
              child: ReorderableListView.builder(
                buildDefaultDragHandles: true,
                itemCount: workingPaths.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final path = workingPaths.removeAt(oldIndex);
                  workingPaths.insert(newIndex, path);
                  if (hasPageTexts) {
                    final text = workingTexts.removeAt(oldIndex);
                    workingTexts.insert(newIndex, text);
                  }
                  setDialogState(() {});
                },
                itemBuilder: (context, index) {
                  final path = workingPaths[index];
                  return ListTile(
                    key: ValueKey(path),
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    leading: SizedBox(
                      width: 54,
                      height: 72,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_outlined,
                          ),
                        ),
                      ),
                    ),
                    title: Text('Halaman ${index + 1}'),
                    subtitle: hasPageTexts &&
                            workingTexts[index].trim().isNotEmpty
                        ? const Text('OCR tersedia')
                        : const Text('Geser untuk mengurutkan'),
                    trailing: IconButton(
                      tooltip: 'Hapus halaman',
                      onPressed: workingPaths.length <= 1
                          ? null
                          : () {
                              workingPaths.removeAt(index);
                              if (hasPageTexts) workingTexts.removeAt(index);
                              setDialogState(() {});
                            },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );

    if (changed != true || !mounted) return;
    if (workingPaths.length == _doc.imagePaths.length &&
        workingPaths.join('|') == _doc.imagePaths.join('|')) {
      return;
    }

    setState(() => _isExportingPdf = true);
    try {
      final newThumbnail =
          await _enhanceService.generateThumbnail(workingPaths.first);
      final oldThumbnail = _doc.thumbnailPath;
      final oldPdf = _doc.pdfPath;
      final updated = _doc.copyWith(
        imagePaths: workingPaths,
        pageTexts: hasPageTexts ? workingTexts : const [],
        clearPdfPath: true,
        thumbnailPath: newThumbnail,
      );

      await _storageService.updateDocument(updated, immediate: true);

      final removedPaths = _doc.imagePaths
          .where((path) => !workingPaths.contains(path))
          .toList(growable: false);
      for (final path in removedPaths) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (oldPdf != null) {
        try {
          await File(oldPdf).delete();
        } catch (_) {}
      }
      if (oldThumbnail != null && oldThumbnail != newThumbnail) {
        try {
          await File(oldThumbnail).delete();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _doc = updated;
        _pageOcrTexts = List<String>.generate(
          workingPaths.length,
          (index) => hasPageTexts ? workingTexts[index] : '',
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Urutan halaman berhasil diperbarui.')),
      );
    } catch (e) {
      try {
        final generatedThumbnail =
            await _enhanceService.generateThumbnail(workingPaths.first);
        await File(generatedThumbnail).delete();
      } catch (_) {}
      if (mounted) {
        _showError('Gagal memperbarui halaman: $e');
      }
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  Future<void> _renameDocument() async {
    if (_isSharing || _isExportingPdf) return;

    // The dialog owns its TextEditingController. Do not dispose a controller
    // while the closing dialog route may still have its TextField mounted.
    final newTitle = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDocumentDialog(initialTitle: _doc.title),
    );

    if (newTitle == null || !mounted || newTitle == _doc.title) return;

    setState(() => _isExportingPdf = true);
    try {
      final oldPdf = _doc.pdfPath;
      final updated = _doc.copyWith(
        title: newTitle,
        clearPdfPath: true,
      );

      // Commit metadata first so a successful rename cannot leave the
      // document pointing at a PDF whose embedded title is stale.
      await _storageService.updateDocument(updated, immediate: true);

      // The cached PDF is now invalid. Cleanup is best-effort; metadata no
      // longer references it even if the filesystem delete fails.
      if (oldPdf != null && oldPdf.isNotEmpty) {
        try {
          await File(oldPdf).delete();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _doc = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama dokumen berhasil diperbarui.')),
      );
    } catch (e) {
      if (mounted) {
        _showError('Gagal mengganti nama dokumen: $e');
      }
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
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
            tooltip: 'Ganti nama',
            icon: const Icon(Icons.edit_outlined),
            onPressed: (_isSharing || _isExportingPdf) ? null : _renameDocument,
          ),
          IconButton(
            tooltip: 'Bagikan',
            icon: const Icon(Icons.share_outlined),
            onPressed: _isSharing ? null : _shareAsImages,
          ),
          IconButton(
            tooltip: 'Atur halaman',
            icon: const Icon(Icons.view_list_outlined),
            onPressed: _isExportingPdf || _isSharing || _doc.imagePaths.length < 2
                ? null
                : _managePages,
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
                onPageOcr: _showPageOcr,
              ),
              const SizedBox(height: 12),
            ] else ...[
              _OcrUnavailableCard(
                isRunning: _isFullOcrRunning,
                enabled: _doc.imagePaths.isNotEmpty &&
                    !_isSharing &&
                    !_isExportingPdf,
                onRunOcr: _rerunOcrAllPages,
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




class _OcrUnavailableCard extends StatelessWidget {
  const _OcrUnavailableCard({
    required this.isRunning,
    required this.enabled,
    required this.onRunOcr,
  });

  final bool isRunning;
  final bool enabled;
  final VoidCallback onRunOcr;

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
      child: Row(
        children: [
          const Icon(
            Icons.text_snippet_outlined,
            color: AppTheme.primary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Teks OCR belum tersedia',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Jalankan OCR dari foto dokumen ini tanpa memindai ulang.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: enabled && !isRunning ? onRunOcr : null,
            icon: isRunning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.document_scanner_outlined, size: 18),
            label: Text(isRunning ? 'Memproses' : 'Jalankan OCR'),
          ),
        ],
      ),
    );
  }
}

class _OcrPreviewCard extends StatelessWidget {
  const _OcrPreviewCard({
    required this.text,
    required this.onViewAll,
    required this.onCopy,
    required this.onPageOcr,
  });

  final String text;
  final VoidCallback onViewAll;
  final VoidCallback onCopy;
  final VoidCallback onPageOcr;

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
              IconButton(
                tooltip: 'OCR per halaman',
                onPressed: onPageOcr,
                icon: const Icon(Icons.view_list_outlined, size: 19),
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

/// Owns the text controller for the rename route, so the controller is only
/// disposed when the dialog widget itself is removed from the widget tree.
class _RenameDocumentDialog extends StatefulWidget {
  const _RenameDocumentDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameDocumentDialog> createState() => _RenameDocumentDialogState();
}

class _RenameDocumentDialogState extends State<_RenameDocumentDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ganti nama dokumen'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Nama dokumen',
          hintText: 'Masukkan nama dokumen',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

