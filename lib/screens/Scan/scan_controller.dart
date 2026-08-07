import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/scanner_service.dart';
import '../../services/ocr_service.dart';
import '../../services/pdf_service.dart';
import '../../services/document_storage_service.dart';
import '../../services/image_enhance_service.dart';
import '../../models/scanned_document.dart';

enum ScanStatus { idle, scanning, ready, processing, done, error }

class ScanController extends ChangeNotifier {
  // ─── Dependencies ────────────────────────────────────────────────────────
  final ScannerService _scannerService;
  final OcrService _ocrService;
  final PdfService _pdfService;
  final DocumentStorageService _storageService;
  final ImageEnhanceService _enhanceService;

  ScanController({
    ScannerService? scannerService,
    OcrService? ocrService,
    PdfService? pdfService,
    DocumentStorageService? storageService,
    ImageEnhanceService? enhanceService,
  })  : _scannerService = scannerService ?? ScannerService(),
        _ocrService = ocrService ?? OcrService(),
        _pdfService = pdfService ?? PdfService(),
        _storageService = storageService ?? DocumentStorageService(),
        _enhanceService = enhanceService ?? ImageEnhanceService();

  // ─── State ──────────────────────────────────────────────────────────
  ScanStatus _status = ScanStatus.idle;
  List<String> _imagePaths = [];
  String? _extractedText;
  bool _isOcrRunning = false;
  String _processingStatus = '';
  String? _errorMessage;

  // ── Cache for prepared images to avoid reprocessing ──
  final Map<String, String> _preparedForOcrCache = {};
  final Map<String, String> _preparedForPdfCache = {};

  late final TextEditingController titleController = TextEditingController(
    text: _defaultTitle(),
  );

  // ─── Getters ─────────────────────────────────────────────────────────
  ScanStatus get status => _status;
  List<String> get imagePaths => List.unmodifiable(_imagePaths);
  String? get extractedText => _extractedText;
  bool get isOcrRunning => _isOcrRunning;
  bool get isScanning => _status == ScanStatus.scanning;
  bool get isProcessing => _status == ScanStatus.processing;
  bool get hasImages => _imagePaths.isNotEmpty;
  String get processingStatus => _processingStatus;
  String? get errorMessage => _errorMessage;

  // ─── Public Actions ───────────────────────────────────────────────────────

  Future<void> startScan(BuildContext context) async {
    _setStatus(ScanStatus.scanning);
    _errorMessage = null;

    try {
      final images = await _scannerService.scanDocument(context);

      if (images == null || images.isEmpty) {
        _setStatus(_imagePaths.isEmpty ? ScanStatus.idle : ScanStatus.ready);
        return;
      }

      // FIX: sebelumnya `_imagePaths = images` MENIMPA seluruh halaman yang
      // sudah ada — akibatnya tombol "Tambah Halaman" bukannya menambah,
      // malah membuang semua halaman sebelumnya. Sekarang halaman baru
      // digabung ke halaman lama, sambil tetap disaring dari duplikat
      // (jaga-jaga isi sama dengan halaman yang sudah ada di sesi ini).
      final newImages = await _dedupeAgainstExisting(images);
      _imagePaths = [..._imagePaths, ...newImages];
      _setStatus(ScanStatus.ready);
      _runOcr();
    } on ScannerException catch (e) {
      _errorMessage = e.toUserMessage();
      _setStatus(ScanStatus.error);
    } catch (e) {
      _errorMessage = 'Scan gagal. Coba lagi atau restart aplikasi.';
      _setStatus(ScanStatus.error);
    }
  }

  /// Saring halaman baru yang isinya identik dengan halaman yang sudah
  /// ada di [_imagePaths] (mis. hasil "Tambah Halaman" kebetulan
  /// menangkap ulang halaman yang sama).
  Future<List<String>> _dedupeAgainstExisting(List<String> newPaths) async {
    final existingHashes = <String>{};
    for (final p in _imagePaths) {
      try {
        existingHashes.add(md5.convert(await File(p).readAsBytes()).toString());
      } catch (_) {}
    }
    final result = <String>[];
    for (final p in newPaths) {
      try {
        final hash = md5.convert(await File(p).readAsBytes()).toString();
        if (existingHashes.add(hash)) result.add(p);
      } catch (_) {
        result.add(p);
      }
    }
    return result;
  }

  void removeImage(int index) {
    if (index < 0 || index >= _imagePaths.length) return;
    _imagePaths = List.from(_imagePaths)..removeAt(index);

    // Invalidate caches for removed image
    _preparedForOcrCache.removeWhere((k, v) {
      try {
        final originalIndex =
            _imagePaths.indexOf(File(k).path.split('/').last);
        return originalIndex == -1 || originalIndex > index;
      } catch (_) {
        return true;
      }
    });
    _preparedForPdfCache.clear();

    notifyListeners();
  }

  Future<bool> saveDocument() async {
    final title = titleController.text.trim();
    if (title.isEmpty) {
      _errorMessage = 'Masukkan judul dokumen';
      notifyListeners();
      return false;
    }

    if (_imagePaths.isEmpty) {
      _errorMessage = 'Tidak ada gambar untuk disimpan';
      notifyListeners();
      return false;
    }

    _setStatus(ScanStatus.processing);
    _processingStatus = 'Menyimpan ke galeri…';

    try {
      await _requestGalleryPermission();

      final id = _storageService.generateId();
      final saved = await _storageService.saveImages(id, _imagePaths);

      _processingStatus = 'Menulis ke galeri…';
      notifyListeners();

      for (var i = 0; i < saved.imagePaths.length; i++) {
        await SaverGallery.saveFile(
          filePath: saved.imagePaths[i],
          fileName: 'DocScan_${id}_$i',
          androidRelativePath: 'Pictures/DocScan',
          skipIfExists: false,
        );
      }

      _processingStatus = 'Menyimpan data…';
      notifyListeners();

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

      _setStatus(ScanStatus.done);
      _clearPreparedCache();
      return true;
    } catch (e) {
      _errorMessage =
          'Gagal menyimpan dokumen. Pastikan penyimpanan tidak penuh, lalu coba lagi.';
      _setStatus(ScanStatus.error);
      return false;
    }
  }

  Future<void> exportPdf() async {
    if (_imagePaths.isEmpty) return;

    // Check if we have cached OCR-prepared images we can reuse
    final preparedPaths = <String>[];
    for (final originalPath in _imagePaths) {
      // Try to find cached PDF-prepared version first (highest quality for PDF)
      if (_preparedForPdfCache.containsKey(originalPath)) {
        preparedPaths.add(_preparedForPdfCache[originalPath]!);
      }
      // Otherwise prepare fresh
      else {
        final prepared = await _enhanceService.prepareForPdf(originalPath);
        preparedPaths.add(prepared);
        _preparedForPdfCache[originalPath] = prepared;
      }
    }

    await _pdfService.generatePdf(
      title: titleController.text,
      imagePaths: preparedPaths,
    );
  }

  Future<void> shareImages() async {
    if (_imagePaths.isEmpty) return;
    await Share.shareXFiles(_imagePaths.map((p) => XFile(p)).toList());
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ── Sumber penamaan dokumen: otomatis / manual / scan barcode ──────────

  /// Isi ulang nama dokumen dengan judul otomatis berbasis waktu saat ini.
  /// Dipakai saat user memilih opsi "Otomatis" di layar scan.
  void useAutoTitle() {
    titleController.text = _defaultTitle();
  }

  /// Isi nama dokumen dari hasil scan barcode/QR. [rawValue] sudah berupa
  /// hasil decode mentah dari mobile_scanner — dibersihkan dulu dari
  /// baris baru/whitespace berlebih sebelum dipakai sebagai judul, karena
  /// beberapa barcode (mis. QR multi-baris) bisa mengandung newline yang
  /// akan merusak tampilan field judul satu baris.
  void useBarcodeTitle(String rawValue) {
    final cleaned = rawValue.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return;
    titleController.text = cleaned;
  }

  // ─── Private Helpers ──────────────────────────────────────────────────────

  void _setStatus(ScanStatus s) {
    _status = s;
    notifyListeners();
  }

  /// Run OCR with caching to avoid reprocessing images
  Future<void> _runOcr() async {
    if (_imagePaths.isEmpty) return;
    _isOcrRunning = true;
    notifyListeners();

    try {
      // Prepare images for OCR, using cache if available
      final preparedPaths = <String>[];
      for (final originalPath in _imagePaths) {
        if (_preparedForOcrCache.containsKey(originalPath)) {
          // Use cached prepared version
          preparedPaths.add(_preparedForOcrCache[originalPath]!);
        } else {
          // Prepare fresh and cache
          final prepared = await _enhanceService.prepareForOcr(originalPath);
          preparedPaths.add(prepared);
          _preparedForOcrCache[originalPath] = prepared;
        }
      }

      _extractedText =
          await _ocrService.extractTextFromImages(preparedPaths);
    } catch (_) {
      _extractedText = null;
    } finally {
      _isOcrRunning = false;
      notifyListeners();
    }
  }

  /// Clear prepared image caches to free memory
  void _clearPreparedCache() {
    _preparedForOcrCache.clear();
    _preparedForPdfCache.clear();
  }

  Future<void> _requestGalleryPermission() async {
    if (!Platform.isAndroid) return;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkVersion = androidInfo.version.sdkInt;

    if (sdkVersion >= 33) {
      // Android 13+ → minta READ_MEDIA_IMAGES (granular)
      final photos = await Permission.photos.request();
      if (photos.isGranted) return;

      // Fallback Android 13: coba READ_MEDIA_IMAGES lewat storage jika photos ditolak
      final storage = await Permission.storage.request();
      if (!storage.isGranted) {
        throw Exception(
          'Izin media ditolak. Buka Pengaturan › Izin › Media lalu aktifkan.',
        );
      }
    } else if (sdkVersion >= 29) {
      // Android 10–12 → MediaStore tidak perlu permission untuk write,
      // tapi READ_EXTERNAL_STORAGE tetap diperlukan untuk read-back file
      final status = await Permission.storage.request();
      if (!status.isGranted && !status.isLimited) {
        throw Exception(
          'Izin storage ditolak. Buka Pengaturan › Izin › Storage lalu aktifkan.',
        );
      }
    } else {
      // Android 7–9 (API 24–28) → WRITE_EXTERNAL_STORAGE wajib
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception(
          'Izin storage ditolak. Buka Pengaturan › Izin › Storage lalu aktifkan.',
        );
      }
    }
  }

  static String _defaultTitle() {
    final now = DateTime.now();
    // FIX: sebelumnya day/month/hour tidak di-padLeft (cuma minute yang
    // di-pad), jadi hasilnya tidak konsisten, mis. "Scan 3-7-2026 9:05"
    // bukan "Scan 03-07-2026 09:05". Judul default ini juga yang jadi
    // basis nama file PDF (lihat PdfService.generatePdf), jadi
    // ketidak-konsistenan ini ikut kebawa ke nama file.
    final dd = now.day.toString().padLeft(2, '0');
    final mo = now.month.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return 'Scan $dd-$mo-${now.year} $hh:$mm';
  }

  @override
  void dispose() {
    titleController.dispose();
    _clearPreparedCache();
    super.dispose();
  }
}
