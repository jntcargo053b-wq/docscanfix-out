import 'dart:io';
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
import '../../services/debug_capture_service.dart';
import '../../models/scanned_document.dart';

enum ScanStatus { idle, scanning, ready, processing, done, error }

class ScanController extends ChangeNotifier {
  // ─── Dependencies ────────────────────────────────────────────────────────
  final ScannerService _scannerService;
  final OcrService _ocrService;
  final PdfService _pdfService;
  final DocumentStorageService _storageService;
  final ImageEnhanceService _enhanceService;
  final DebugCaptureService _debugCapture;

  ScanController({
    ScannerService? scannerService,
    OcrService? ocrService,
    PdfService? pdfService,
    DocumentStorageService? storageService,
    ImageEnhanceService? enhanceService,
    DebugCaptureService? debugCapture,
  })  : _scannerService = scannerService ?? ScannerService(),
        _ocrService = ocrService ?? OcrService(),
        _pdfService = pdfService ?? PdfService(),
        _storageService = storageService ?? DocumentStorageService(),
        _enhanceService = enhanceService ?? ImageEnhanceService(),
        _debugCapture = debugCapture ?? DebugCaptureService();

  // ── Debug capture session ──
  // Satu sessionId per proses scan, dipakai untuk mengelompokkan
  // capture di DebugCaptureService (lihat folder DocScan/Debug/<id>).
  String? _debugSessionId;

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
        _setStatus(ScanStatus.idle);
        return;
      }

      // Session baru per scan — dipakai untuk mengelompokkan semua debug
      // capture tahap ini (raw → prepared OCR → prepared PDF → saved).
      _debugSessionId = DateTime.now().millisecondsSinceEpoch.toString();

      // DEBUG: simpan output MENTAH dari cunning_document_scanner, sebelum
      // app menyentuhnya sama sekali. Kalau foto sudah putih di sini,
      // sumbernya scanner native/ML Kit — bukan kode kita.
      await _debugCapture.captureAll(
        sessionId: _debugSessionId!,
        stage: '01_raw_scanner',
        imagePaths: images,
      );

      _imagePaths = images;
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

      // DEBUG: file akhir yang benar-benar tersimpan (hasil copy dari
      // _imagePaths, byte-identik — lihat DocumentStorageService.saveImages).
      // Kalau ini beda dari "01_raw_scanner", berarti user mengedit di
      // image editor sebelum simpan; kalau sama, overexpose 100% dari scanner.
      if (_debugSessionId != null) {
        await _debugCapture.captureAll(
          sessionId: _debugSessionId!,
          stage: '04_saved_gallery',
          imagePaths: saved.imagePaths,
        );
      }

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

    // DEBUG: hasil resize+compress sebelum masuk PDF. prepareForPdf tidak
    // mengubah warna (cuma resize + kompres JPEG) — kalau tahap ini putih
    // padahal "01_raw_scanner" normal, curigai gamma shift dari re-encode
    // JPEG quality rendah, bukan enhancement warna.
    if (_debugSessionId != null) {
      await _debugCapture.captureAll(
        sessionId: _debugSessionId!,
        stage: '03_prepared_pdf',
        imagePaths: preparedPaths,
      );
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

      // DEBUG: hasil resize+grayscale sebelum masuk OCR. Ini TIDAK dipakai
      // sebagai gambar tersimpan/preview — cuma input ML Kit — tapi berguna
      // untuk mengecek apakah grayscale conversion ikut andil di kasus lain.
      if (_debugSessionId != null) {
        await _debugCapture.captureAll(
          sessionId: _debugSessionId!,
          stage: '02_prepared_ocr',
          imagePaths: preparedPaths,
        );
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
    final mm = now.minute.toString().padLeft(2, '0');
    return 'Scan ${now.day}-${now.month}-${now.year} ${now.hour}:$mm';
  }

  @override
  void dispose() {
    titleController.dispose();
    _clearPreparedCache();
    super.dispose();
  }
}
