import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';

class SaveService {
  // Cache SDK version — DeviceInfoPlugin baca dari sistem sekali saja
  static int? _cachedSdk;

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

      final fileName = "scan_${DateTime.now().millisecondsSinceEpoch}_$i.jpg";

      final result = await SaverGallery.saveFile(
        filePath: file.path,
        fileName: fileName,
        androidRelativePath: "Pictures/DocScan",
        skipIfExists: false,
      );

      if (!result.isSuccess) {
        throw Exception("Gagal simpan foto ${i + 1}: ${result.errorMessage}");
      }
    }
  }

  Future<void> _requestPermission() async {
    if (!Platform.isAndroid) return;

    final sdk = await _getSdkVersion();

    if (sdk >= 33) {
      final status = await Permission.photos.request();
      if (!status.isGranted) {
        throw Exception(
          "Izin galeri ditolak. Buka Pengaturan > Aplikasi > DocScan > Izin > Media.",
        );
      }
    } else if (sdk < 29) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception(
          "Izin storage ditolak. Buka Pengaturan > Aplikasi > DocScan > Izin > Storage.",
        );
      }
    }
    // Android 10–12: MediaStore tidak butuh permission untuk write
  }

  /// Gunakan DeviceInfoPlugin — tidak butuh shell process.
  Future<int> _getSdkVersion() async {
    if (_cachedSdk != null) return _cachedSdk!;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      _cachedSdk = info.version.sdkInt;
      return _cachedSdk!;
    } catch (_) {
      return 29; // safe fallback: Android 10
    }
  }
}
