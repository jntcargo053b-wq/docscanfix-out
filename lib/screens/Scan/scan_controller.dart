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
import '../../models/scanned_document.dart';

enum ScanStatus { idle, scanning, ready, processing, done, error }

class ScanController extends ChangeNotifier {
  // ─── Dependencies ────────────────────────────────────────────────────────────
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

  // ─── State ───────────────────────────────────────────────────────────────────
  ScanStatus _status = ScanStatus.idle;
  List<String> _imagePaths = [];
  String? _extractedText;
  bool _isOcrRunning = false;
  String _processingStatus = '';
  String? _errorMessage;

  late final TextEditingController titleController = TextEditingController(
    text: _defaultTitle(),
  );

  // ─── Getters ─────────────────────────────────────────────────────────────────
  ScanStatus get status => _status;
  List<String> get imagePaths => List.unmodifiable(_imagePaths);
  String? get extractedText => _extractedText;
  bool get isOcrRunning => _isOcrRunning;
  bool get isScanning => _status == ScanStatus.scanning;
  bool get isProcessing => _status == ScanStatus.processing;
  bool get hasImages => _imagePaths.isNotEmpty;
  String get processingStatus => _processingStatus;
  String? get errorMessage => _errorMessage;

  // ─── Public Actions ───────────────────────────────────────────────────────────

  Future<void> startScan(BuildContext context) async {
    _setStatus(ScanStatus.scanning);
    _errorMessage = null;

    try {
      final images = await _scannerService.scanDocument(context);

      if (images == null || images.isEmpty) {
        _setStatus(ScanStatus.idle);
        return;
      }

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
    notifyListeners();
  }

  Future<bool> saveDocument() async {
    final title = titleController.text.trim();
    if (title.isEmpty) {
      _errorMessage = 'Masukkan judul dokumen';
      notifyListeners();
      return false;
    }

    // FIX: jangan lanjut jika tidak ada gambar sama sekali
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
      return true;
    } catch (e) {
      _errorMessage = 'Gagal menyimpan dokumen. Pastikan penyimpanan tidak penuh, lalu coba lagi.';
      _setStatus(ScanStatus.error);
      return false;
    }
  }

  Future<void> exportPdf() async {
    if (_imagePaths.isEmpty) return;
    // Resize sebelum masuk PDF — gambar kamera mentah bisa 12–48 MP
    final preparedPaths = await Future.wait(
      _imagePaths.map((p) => _enhanceService.prepareForPdf(p)),
    );
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

  // ─── Private Helpers ──────────────────────────────────────────────────────────

  void _setStatus(ScanStatus s) {
    _status = s;
    notifyListeners();
  }

  Future<void> _runOcr() async {
    if (_imagePaths.isEmpty) return;
    _isOcrRunning = true;
    notifyListeners();

    try {
      // Resize + grayscale sebelum OCR — hemat RAM ML Kit, tidak turunkan akurasi
      final preparedPaths = await Future.wait(
        _imagePaths.map((p) => _enhanceService.prepareForOcr(p)),
      );
      _extractedText = await _ocrService.extractTextFromImages(preparedPaths);
    } catch (_) {
      _extractedText = null;
    } finally {
      _isOcrRunning = false;
      notifyListeners();
    }
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
      // (beberapa ROM custom Android 13 tidak map Permission.photos dengan benar)
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
    super.dispose();
  }
}
