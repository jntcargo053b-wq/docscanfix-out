import 'dart:io';
import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

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

  /// Scan dokumen — memerlukan BuildContext untuk document_scanner_flutter.
  /// Melempar [ScannerException] dengan kode yang bisa diinterpretasi UI.
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
      final File? scannedFile = await DocumentScannerFlutter.launch(context);
      if (scannedFile == null) return null;
      return [scannedFile.path];
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
  /// Permission dicek sebelum membuka kamera.
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

  /// Pesan ramah pengguna — tidak ada stack trace atau nama class.
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
