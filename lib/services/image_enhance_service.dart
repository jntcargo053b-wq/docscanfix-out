import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

// ── Top-level functions untuk compute() (harus di luar class) ──────────────

Future<String> _autoEnhanceIsolate(String imagePath) async {
  final svc = ImageEnhanceService();
  return svc._processAutoEnhance(imagePath);
}

Future<String> _manualEnhanceIsolate(_ManualParams p) async {
  final svc = ImageEnhanceService();
  return svc._processManualEnhance(p);
}

Future<String> _compressIsolate(_CompressParams p) async {
  final svc = ImageEnhanceService();
  return svc._processCompress(p);
}

Future<String> _thumbnailIsolate(String imagePath) async {
  final svc = ImageEnhanceService();
  return svc._processThumbnail(imagePath);
}

Future<String> _prepareForOcrIsolate(String imagePath) async {
  final svc = ImageEnhanceService();
  return svc._processPrepareForOcr(imagePath);
}

Future<String> _prepareForPdfIsolate(String imagePath) async {
  final svc = ImageEnhanceService();
  return svc._processPrepareForPdf(imagePath);
}

// ── Parameter classes ───────────────────────────────────────────────────────

class _ManualParams {
  final String imagePath;
  final double brightness, contrast, saturation;
  final bool sharpen, grayscale;
  _ManualParams(this.imagePath, this.brightness, this.contrast,
      this.saturation, this.sharpen, this.grayscale);
}

class _CompressParams {
  final String imagePath;
  final int maxDimension;
  final int quality;
  _CompressParams(this.imagePath, this.maxDimension, this.quality);
}

// ── Main service ──────────────────────────────────────────────────────────

class ImageEnhanceService {
  static final ImageEnhanceService _instance = ImageEnhanceService._internal();
  factory ImageEnhanceService() => _instance;
  ImageEnhanceService._internal();

  // ── PUBLIC API (pakai compute = background isolate) ──

  Future<String> autoEnhance(String imagePath) =>
      compute(_autoEnhanceIsolate, imagePath);

  Future<String> manualEnhance(
    String imagePath, {
    double brightness = 1.0,
    double contrast = 1.0,
    double saturation = 1.0,
    bool sharpen = false,
    bool grayscale = false,
  }) =>
      compute(
        _manualEnhanceIsolate,
        _ManualParams(imagePath, brightness, contrast,
            saturation, sharpen, grayscale),
      );

  /// Compress foto — max 2048px, quality 82%
  Future<String> compress(String imagePath,
          {int maxDimension = 2048, int quality = 82}) =>
      compute(_compressIsolate,
          _CompressParams(imagePath, maxDimension, quality));

  /// Buat thumbnail 200px untuk home screen cache
  Future<String> generateThumbnail(String imagePath) =>
      compute(_thumbnailIsolate, imagePath);

  /// Resize + grayscale sebelum OCR.
  ///
  /// ML Kit bekerja optimal pada gambar ≤1600px dan grayscale menghemat
  /// ~⅓ memori tanpa menurunkan akurasi teks. Dijalankan di isolate.
  Future<String> prepareForOcr(String imagePath) =>
      compute(_prepareForOcrIsolate, imagePath);

  /// Resize + kompres sebelum masuk PDF pipeline.
  ///
  /// Gambar kamera mentah sering 12–48 MP; 1920px sudah cukup tajam untuk
  /// dokumen A4 dicetak 200 dpi. Quality 85 memberi keseimbangan ukuran/kualitas.
  Future<String> prepareForPdf(String imagePath) =>
      compute(_prepareForPdfIsolate, imagePath);

  // ── Rotate & Flip (ringan, tidak perlu isolate) ──

  Future<String> rotate90(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return imagePath;
    image = img.copyRotate(image, angle: 90);
    return await _saveTemp(image);
  }

  Future<String> rotate90CCW(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return imagePath;
    image = img.copyRotate(image, angle: -90);
    return await _saveTemp(image);
  }

  Future<String> flipHorizontal(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return imagePath;
    image = img.flipHorizontal(image);
    return await _saveTemp(image);
  }

  Future<String> crop(
    String imagePath, {
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return imagePath;
    final x = (left * image.width).round().clamp(0, image.width - 1);
    final y = (top * image.height).round().clamp(0, image.height - 1);
    final w = ((right - left) * image.width).round().clamp(1, image.width - x);
    final h = ((bottom - top) * image.height).round().clamp(1, image.height - y);
    image = img.copyCrop(image, x: x, y: y, width: w, height: h);
    return await _saveTemp(image);
  }

  // ── INTERNAL (dipanggil dari isolate) ──

  /// Auto-enhance using built-in filters instead of pixel loops.
  /// ~5-10x faster than manual per-pixel operations.
  Future<String> _processAutoEnhance(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return imagePath;

    // Use built-in filters instead of pixel loops
    image = img.adjustColor(image, brightness: 15);
    image = img.contrast(image, contrast: 25); // contrast scale: 1-100, 50 is neutral
    image = img.sharpen(image);

    return await _saveTemp(image);
  }

  Future<String> _processManualEnhance(_ManualParams p) async {
    final bytes = await File(p.imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return p.imagePath;

    if (p.grayscale) {
      image = img.grayscale(image);
    }

    // Apply transformations using built-in methods
    if (p.brightness != 1.0) {
      final brightnessAdjust = ((p.brightness - 1.0) * 128).round();
      image = img.adjustColor(image, brightness: brightnessAdjust);
    }

    if (p.contrast != 1.0) {
      // Convert contrast factor (0.5-2.0) to image package scale (1-100)
      final contrastScale = ((p.contrast - 1.0) * 50 + 50).toInt().clamp(1, 100);
      image = img.contrast(image, contrast: contrastScale);
    }

    if (!p.grayscale && p.saturation != 1.0) {
      // Convert saturation factor (0.5-2.0) to image package scale (0-200)
      final saturationScale =
          ((p.saturation - 1.0) * 100 + 100).toInt().clamp(0, 200);
      image = img.adjustColor(image, saturation: saturationScale);
    }

    if (p.sharpen) {
      image = img.sharpen(image);
    }

    return await _saveTemp(image);
  }

  Future<String> _processCompress(_CompressParams p) async {
    final bytes = await File(p.imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return p.imagePath;

    // Resize jika lebih besar dari maxDimension
    if (image.width > p.maxDimension || image.height > p.maxDimension) {
      if (image.width > image.height) {
        image = img.copyResize(image, width: p.maxDimension);
      } else {
        image = img.copyResize(image, height: p.maxDimension);
      }
    }

    return _saveTempNamed(image, 'compressed', quality: p.quality);
  }

  Future<String> _processThumbnail(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return imagePath;

    // Thumbnail 200x200 crop tengah
    image = img.copyResizeCropSquare(image, size: 200);

    final dir = await getApplicationDocumentsDirectory();
    final thumbDir = Directory('${dir.path}/DocScan/Thumbnails');
    await thumbDir.create(recursive: true);

    final name = 'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outPath = '${thumbDir.path}/$name';
    await File(outPath).writeAsBytes(
      Uint8List.fromList(img.encodeJpg(image, quality: 75)),
    );
    return outPath;
  }

  /// Resize ke max 1600px lebar + konversi grayscale untuk OCR.
  /// Grayscale hemat ~⅓ memori dan tidak menurunkan akurasi ML Kit.
  Future<String> _processPrepareForOcr(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Gagal decode gambar: $imagePath');

    // Resize bila lebih lebar/tinggi dari 1600px
    if (image.width > 1600 || image.height > 1600) {
      image = img.copyResize(
        image,
        width: image.width > image.height ? 1600 : -1,
        height: image.height >= image.width ? 1600 : -1,
        interpolation: img.Interpolation.linear,
      );
    }

    // Grayscale — ML Kit teks tidak butuh warna
    image = img.grayscale(image);

    return _saveTempNamed(image, 'ocr_prep', quality: 88);
  }

  /// Resize ke max 1920px + kompres ke quality 85 sebelum masuk PDF pipeline.
  Future<String> _processPrepareForPdf(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Gagal decode gambar: $imagePath');

    if (image.width > 1920 || image.height > 1920) {
      image = img.copyResize(
        image,
        width: image.width > image.height ? 1920 : -1,
        height: image.height >= image.width ? 1920 : -1,
        interpolation: img.Interpolation.linear,
      );
    }

    return _saveTempNamed(image, 'pdf_prep', quality: 85);
  }

  /// Simpan ke temp dengan prefix nama tertentu.
  Future<String> _saveTempNamed(img.Image image, String prefix,
      {int quality = 92}) async {
    final dir = await getTemporaryDirectory();
    final name = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outPath = '${dir.path}/$name';
    await File(outPath).writeAsBytes(
      Uint8List.fromList(img.encodeJpg(image, quality: quality)),
    );
    return outPath;
  }

  Future<String> _saveTemp(img.Image image) async {
    final dir = await getTemporaryDirectory();
    final name = 'enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outPath = '${dir.path}/$name';
    await File(outPath).writeAsBytes(
      Uint8List.fromList(img.encodeJpg(image, quality: 92)),
    );
    return outPath;
  }
}
