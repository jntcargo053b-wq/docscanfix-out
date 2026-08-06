import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Menyimpan salinan gambar di titik-titik kunci pipeline scan:
///
/// ```
/// 01_raw_scanner   → output mentah cunning_document_scanner (belum disentuh app)
/// 02_prepared_ocr  → setelah ImageEnhanceService.prepareForOcr (resize+grayscale)
/// 03_prepared_pdf  → setelah ImageEnhanceService.prepareForPdf (resize+compress)
/// 04_saved_gallery → file akhir yang di-copy ke galeri/document storage
/// ```
///
/// Tujuannya membuktikan (bukan menduga) di tahap mana overexpose/putih
/// pertama kali muncul — kalau "01_raw_scanner" sudah putih, sumbernya
/// scanner native/ML Kit, bukan kode enhancement kita.
///
/// Hanya aktif di [kDebugMode] secara default supaya tidak menambah I/O di
/// build release. Set [forceEnabled] = true kalau butuh capture di build
/// profile/release untuk investigasi laporan bug user tertentu.
class DebugCaptureService {
  static final DebugCaptureService _instance =
      DebugCaptureService._internal();
  factory DebugCaptureService() => _instance;
  DebugCaptureService._internal();

  bool forceEnabled = false;

  bool get isEnabled => kDebugMode || forceEnabled;

  /// Copy [imagePath] ke folder debug, ditandai dengan [sessionId] (biasanya
  /// document id atau timestamp mulai scan) dan [stage] (nama tahap).
  /// Gagal capture tidak boleh menghentikan alur utama — selalu dibungkus
  /// try/catch dan tidak melempar exception ke caller.
  Future<void> capture({
    required String sessionId,
    required String stage,
    required String imagePath,
  }) async {
    if (!isEnabled) return;
    try {
      final file = File(imagePath);
      if (!await file.exists()) return;

      final dir = await getApplicationDocumentsDirectory();
      final debugDir = Directory('${dir.path}/DocScan/Debug/$sessionId');
      await debugDir.create(recursive: true);

      final ext = imagePath.contains('.') ? imagePath.split('.').last : 'jpg';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final outPath = '${debugDir.path}/${stage}_$ts.$ext';

      await file.copy(outPath);
      debugPrint('[DebugCapture] $stage → $outPath');
    } catch (e) {
      debugPrint('[DebugCapture] gagal capture stage "$stage": $e');
    }
  }

  /// Capture untuk beberapa halaman sekaligus, indeks halaman ditambahkan
  /// otomatis ke nama stage (mis. "01_raw_scanner_p1", "..._p2").
  Future<void> captureAll({
    required String sessionId,
    required String stage,
    required List<String> imagePaths,
  }) async {
    if (!isEnabled) return;
    for (var i = 0; i < imagePaths.length; i++) {
      await capture(
        sessionId: sessionId,
        stage: '${stage}_p${i + 1}',
        imagePath: imagePaths[i],
      );
    }
  }

  /// Path folder debug untuk satu sesi — berguna kalau mau menampilkan
  /// hasil capture di layar debug internal atau membukanya via file manager.
  Future<Directory> sessionDir(String sessionId) async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/DocScan/Debug/$sessionId');
  }
}
