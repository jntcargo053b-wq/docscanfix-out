import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';

class SaveService {
  Future<void> saveImages(List<String> paths) async {
    if (paths.isEmpty) {
      throw Exception("Tidak ada gambar untuk disimpan");
    }

    await _requestPermission();

    for (int i = 0; i < paths.length; i++) {
      final file = File(paths[i]);
      if (!await file.exists()) {
        throw Exception("File tidak ditemukan: ${paths[i]}");
      }

      final fileName =
          "scan_${DateTime.now().millisecondsSinceEpoch}_$i.jpg";

      final result = await SaverGallery.saveFile(
        filePath: file.path,
        fileName: fileName,
        androidRelativePath: "Pictures/DocScan",
        skipIfExists: false,
      );

      if (!result.isSuccess) {
        throw Exception(
            "Gagal simpan foto ${i + 1}: ${result.errorMessage}");
      }
    }
  }

  Future<void> _requestPermission() async {
    if (!Platform.isAndroid) return;

    // Android 13+ (API 33) pakai Permission.photos
    // Android 10-12 tidak perlu permission untuk MediaStore
    // Android < 10 pakai Permission.storage
    final sdk = await _getSdkVersion();

    if (sdk >= 33) {
      final status = await Permission.photos.request();
      if (!status.isGranted) {
        throw Exception(
            "Izin galeri ditolak. Buka Pengaturan > Aplikasi > DocScan > Izin > Media.");
      }
    } else if (sdk < 29) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception(
            "Izin storage ditolak. Buka Pengaturan > Aplikasi > DocScan > Izin > Storage.");
      }
    }
    // Android 10-12: tidak perlu permission, MediaStore langsung bisa
  }

  Future<int> _getSdkVersion() async {
    try {
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse(result.stdout.toString().trim()) ?? 29;
    } catch (_) {
      return 29;
    }
  }
}
