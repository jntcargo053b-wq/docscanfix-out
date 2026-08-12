import 'dart:io';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/file_hash.dart';

class ScannerService {
  static final ScannerService _instance = ScannerService._internal();
  factory ScannerService() => _instance;
  ScannerService._internal();

  final ImagePicker _imagePicker = ImagePicker();

  /// Pastikan izin kamera — return true jika diberikan.
  static Future<bool> ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;
    status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Scan dokumen menggunakan cunning_document_scanner.
  /// BuildContext tetap diterima untuk kompatibilitas caller, tapi tidak dipakai.
  Future<List<String>?> scanDocument(BuildContext context) async {
    final granted = await ensureCameraPermission();
    if (!granted) {
      final status = await Permission.camera.status;
      throw ScannerException(
        status.isPermanentlyDenied
            ? ScannerError.permissionPermanentlyDenied
            : ScannerError.permissionDenied,
      );
    }

    try {
      // FIX (P1 — Scanner masih FULL mode): sebelumnya androidScannerMode
      // tidak pernah di-set, jadi plugin selalu jalan di mode default ML
      // Kit-nya sendiri (FULL) — mode ini menerapkan filter/binarization
      // OTOMATIS ala "dokumen hitam-putih tegas" di level native SEBELUM
      // gambar sampai ke Dart. Masalahnya, ImageEnhanceService di app ini
      // SUDAH punya pipeline enhance sendiri (percentile histogram
      // stretch adaptif — lihat _processAutoEnhance) yang didesain jalan
      // di atas foto ASLI apa adanya. Dua lapis auto-filter yang saling
      // tidak tahu satu sama lain (FULL mode di native + auto-enhance di
      // Dart) inilah akar salah satu bug overexposure yang pernah
      // didiagnosis sebelumnya: filter FULL sudah mendorong highlight ke
      // putih & posterize kontras duluan, lalu histogram stretch di atas
      // itu mendorongnya lebih jauh lagi — hasilnya tulisan tipis/pudar
      // bisa hilang total ke putih, bukan makin terbaca.
      // androidScannerMode baru tersedia sejak plugin versi 2.2.0 (lihat
      // bump versi di pubspec.yaml, sebelumnya terkunci ^1.4.0 yang belum
      // punya parameter ini sama sekali — makanya sebelum ini tidak ada
      // cara mengubahnya, defaultnya FULL apa pun yang dilakukan).
      // Fix: AndroidScannerMode.base — cuma deteksi tepi & crop dokumen
      // (tugas platform yang memang lebih baik dari ML Kit dibanding
      // reimplementasi manual), TANPA filter otomatis tambahan. Koreksi
      // pencahayaan/kontras sepenuhnya diserahkan ke ImageEnhanceService
      // yang sudah adaptif per-foto, bukan dobel dengan preset native.
      final List<String>? paths = await CunningDocumentScanner.getPictures(
        noOfPages: 10,
        isGalleryImportAllowed: false,
        androidScannerMode: AndroidScannerMode.base,
      );
      if (paths == null || paths.isEmpty) return null;
      // FIX: cunning_document_scanner kadang mengembalikan halaman yang
      // sama dua kali (path berbeda tapi isi file identik) saat capture
      // beberapa halaman dalam satu sesi — sebelumnya tidak difilter,
      // sehingga dokumen/PDF/share bisa berisi foto duplikat. Saring
      // berdasarkan hash konten file, bukan cuma path, karena duplikat
      // bisa muncul dengan nama file yang berbeda.
      return await _dedupeByContent(paths);
    } on ScannerException {
      rethrow;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('permission') || msg.contains('camera')) {
        throw ScannerException(ScannerError.permissionDenied);
      }
      throw ScannerException(ScannerError.scanFailed, cause: e);
    }
  }

  /// Buang halaman dengan isi file identik, pertahankan urutan kemunculan
  /// pertama. Dipakai untuk menangkis bug plugin scanner yang kadang
  /// mengembalikan halaman kembar.
  Future<List<String>> _dedupeByContent(List<String> paths) async {
    final seenHashes = <String>{};
    final result = <String>[];
    for (final path in paths) {
      // FIX (P1 — MD5 readAsBytes() baca seluruh file ke RAM): hash lewat
      // streaming (lihat hashFileStreaming()), bukan readAsBytes() penuh.
      final hash = await hashFileStreaming(path);
      if (hash == null) {
        // Jika file tidak terbaca, biarkan lolos apa adanya — biar
        // ditangani di tahap berikutnya (mis. saveImages sudah skip
        // file yang tidak ada), daripada diam-diam menghilangkan halaman.
        result.add(path);
      } else if (seenHashes.add(hash)) {
        result.add(path);
      }
    }
    return result;
  }

  /// Import dari galeri.
  Future<List<String>?> importFromGallery() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        imageQuality: 90,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (images.isEmpty) return null;
      return images.map((img) => img.path).toList();
    } catch (e) {
      throw ScannerException(ScannerError.galleryFailed, cause: e);
    }
  }

  /// Ambil foto tunggal dari kamera.
  Future<String?> takePhoto() async {
    final granted = await ensureCameraPermission();
    if (!granted) {
      final status = await Permission.camera.status;
      throw ScannerException(
        status.isPermanentlyDenied
            ? ScannerError.permissionPermanentlyDenied
            : ScannerError.permissionDenied,
      );
    }

    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      return photo?.path;
    } catch (e) {
      throw ScannerException(ScannerError.cameraFailed, cause: e);
    }
  }

  /// Hapus file sementara.
  Future<void> cleanupFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// Purge file basi di getTemporaryDirectory() yang lebih tua dari
  /// [maxAge] (default 24 jam).
  ///
  /// cleanupFiles() di atas menghapus temp file eksplisit lewat daftar path
  /// yang MASIH diketahui controller (jalur normal — user batal scan,
  /// simpan, dsb). Tapi cunning_document_scanner, image_picker, dan
  /// ImageEnhanceService (_saveTemp/_saveTempNamed: enhanced_*, ocr_prep_*,
  /// pdf_prep_*, dan thumbnail sementara sebelum jadi permanen) semua
  /// menulis ke getTemporaryDirectory() yang sama — kalau app di-kill paksa
  /// (force-stop, OOM killer, crash) di TENGAH sesi scan/enhance, daftar
  /// path itu hilang bersama proses, dan file-file itu nyangkut permanen
  /// di temp dir; OS Android boleh membersihkan cache dir kapan saja tapi
  /// tidak dijamin/tidak bisa diandalkan sebagai satu-satunya mekanisme
  /// cleanup, apalagi untuk storage yang mepet.
  /// Dipanggil sekali tiap startup app (lihat main.dart) sebagai
  /// pelengkap, bukan pengganti, cleanupFiles() — jaring pengaman untuk
  /// file yatim dari sesi yang tidak pernah sempat cleanup normal.
  /// Berjalan best-effort di background: kegagalan baca/hapus per-file
  /// tidak menghentikan proses, dan tidak pernah melempar ke caller
  /// (dipanggil fire-and-forget dari main(), sebelum runApp).
  static Future<void> purgeStaleTempFiles({
    Duration maxAge = const Duration(hours: 24),
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      if (!await dir.exists()) return;

      final cutoff = DateTime.now().subtract(maxAge);
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          }
        } catch (_) {
          // Satu file gagal di-stat/hapus (race dengan proses lain yang
          // masih menulis, permission, dsb.) — lewati, jangan hentikan
          // pembersihan file lain.
        }
      }
    } catch (_) {
      // getTemporaryDirectory()/listing gagal total — best-effort, jangan
      // sampai mengganggu startup app.
    }
  }
}

// ─── Error types ─────────────────────────────────────────────────────────────

enum ScannerError {
  permissionDenied,
  permissionPermanentlyDenied,
  scanFailed,
  cameraFailed,
  galleryFailed,
}

class ScannerException implements Exception {
  final ScannerError error;
  final Object? cause;
  const ScannerException(this.error, {this.cause});

  String toUserMessage() => switch (error) {
    ScannerError.permissionDenied =>
      'Izin kamera diperlukan untuk scan dokumen. '
      'Ketuk Izinkan saat dialog muncul.',
    ScannerError.permissionPermanentlyDenied =>
      'Izin kamera diblokir. Buka Pengaturan → Aplikasi → DocScan → '
      'Izin → aktifkan Kamera, lalu coba lagi.',
    ScannerError.scanFailed =>
      'Scan gagal. Pastikan kamera tidak digunakan aplikasi lain, '
      'lalu coba lagi.',
    ScannerError.cameraFailed =>
      'Kamera tidak dapat dibuka. Coba tutup aplikasi lain yang '
      'menggunakan kamera.',
    ScannerError.galleryFailed =>
      'Gagal membuka galeri. Pastikan izin penyimpanan sudah diberikan.',
  };

  @override
  String toString() => 'ScannerException(${error.name}: $cause)';
}
