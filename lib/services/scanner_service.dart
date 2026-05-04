import 'dart:io';
import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class ScannerService {
  static final ScannerService _instance = ScannerService._internal();
  factory ScannerService() => _instance;
  ScannerService._internal();

  final ImagePicker _imagePicker = ImagePicker();

  /// Grant camera permission — return true if granted
  static Future<bool> ensureCameraPermission() async {
    var status = await Permission.camera.status;

    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;

    status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Scan document — requires BuildContext for document_scanner_flutter
  Future<List<String>?> scanDocument(context) async {
    final granted = await ensureCameraPermission();

    if (!granted) {
      final status = await Permission.camera.status;
      if (status.isPermanentlyDenied) {
        throw Exception('PERMISSION_PERMANENTLY_DENIED');
      }
      throw Exception('PERMISSION_DENIED');
    }

    try {
      final File? scannedFile = await DocumentScannerFlutter.launch(context);
      if (scannedFile == null) return null;
      return [scannedFile.path];
    } on Exception catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('permission') || msg.contains('camera')) {
        throw Exception('PERMISSION_DENIED');
      }
      rethrow;
    }
  }

  /// Import from gallery
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
      throw Exception('Gallery import failed: $e');
    }
  }

  /// Take single photo
  Future<String?> takePhoto() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      return photo?.path;
    } catch (e) {
      throw Exception('Camera capture failed: $e');
    }
  }

  /// Delete temp files
  Future<void> cleanupFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}
