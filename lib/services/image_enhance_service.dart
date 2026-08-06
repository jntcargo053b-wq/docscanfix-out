import 'dart:io';
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

// PERF FIX: rotate/flip/crop sebelumnya jalan langsung di main isolate
// (komentar lama bilang "ringan, tidak perlu isolate"), padahal tetap
// decode+encode JPEG resolusi kamera asli (bisa puluhan MP) — cukup berat
// untuk nge-jank UI thread saat dipanggil interaktif dari image editor.
// Disamakan pola dengan operasi lain: top-level function + compute().

Future<String> _rotate90Isolate(String imagePath) async {
  final svc = ImageEnhanceService();
  return svc._processRotate(imagePath, 90);
}

Future<String> _rotate90CCWIsolate(String imagePath) async {
  final svc = ImageEnhanceService();
  return svc._processRotate(imagePath, -90);
}

Future<String> _flipHorizontalIsolate(String imagePath) async {
  final svc = ImageEnhanceService();
  return svc._processFlipHorizontal(imagePath);
}

Future<String> _cropIsolate(_CropParams p) async {
  final svc = ImageEnhanceService();
  return svc._processCrop(p);
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

class _CropParams {
  final String imagePath;
  final double left, top, right, bottom;
  _CropParams(this.imagePath, this.left, this.top, this.right, this.bottom);
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

  // ── Rotate & Flip (pakai compute = background isolate) ──
  // PERF FIX: decode+encode JPEG resolusi kamera asli tidak "ringan" —
  // dijalankan di isolate terpisah sama seperti operasi enhance lain,
  // supaya UI thread tidak freeze saat user tap rotate/flip/crop.

  Future<String> rotate90(String imagePath) =>
      compute(_rotate90Isolate, imagePath);

  Future<String> rotate90CCW(String imagePath) =>
      compute(_rotate90CCWIsolate, imagePath);

  Future<String> flipHorizontal(String imagePath) =>
      compute(_flipHorizontalIsolate, imagePath);

  Future<String> crop(
    String imagePath, {
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) =>
      compute(_cropIsolate, _CropParams(imagePath, left, top, right, bottom));

  // ── INTERNAL (dipanggil dari isolate) ──

  Future<String> _processRotate(String imagePath, int angle) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return imagePath;
    image = img.copyRotate(image, angle: angle);
    return await _saveTemp(image);
  }

  Future<String> _processFlipHorizontal(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return imagePath;
    image = img.flipHorizontal(image);
    return await _saveTemp(image);
  }

  Future<String> _processCrop(_CropParams p) async {
    final bytes = await File(p.imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return p.imagePath;
    final x = (p.left * image.width).round().clamp(0, image.width - 1);
    final y = (p.top * image.height).round().clamp(0, image.height - 1);
    final w =
        ((p.right - p.left) * image.width).round().clamp(1, image.width - x);
    final h =
        ((p.bottom - p.top) * image.height).round().clamp(1, image.height - y);
    image = img.copyCrop(image, x: x, y: y, width: w, height: h);
    return await _saveTemp(image);
  }

  /// Auto-enhance berbasis histogram (percentile black/white point stretch).
  ///
  /// Implementasi lama pakai offset TETAP (+15 brightness, +25 contrast)
  /// untuk SEMUA foto tanpa peduli kondisi pencahayaan aslinya. Ini
  /// berbahaya untuk dokumen yang sudah cerah (kertas putih, kena flash,
  /// cahaya kuat) — offset tetap mendorong pixel yang sudah dekat 255
  /// makin nge-clip ke putih murni, teks tipis jadi hilang.
  ///
  /// Sekarang titik hitam & titik putih dihitung dari histogram luminance
  /// foto itu sendiri (persentil 1%/99%, BUKAN nilai min/max mentah — supaya
  /// tidak terpengaruh outlier seperti satu titik pantulan cahaya kecil),
  /// baru pixel-nya di-stretch secara linear ke rentang 0-255. Kalau
  /// dynamic range foto sudah lebar (>150 level, artinya sudah kontras),
  /// stretch di-skip supaya tidak over-process foto yang sudah bagus.
  Future<String> _processAutoEnhance(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return imagePath;

    final stretch = _computeHistogramStretch(image);
    if (stretch != null) {
      image = _applyStretch(image, stretch.$1, stretch.$2);
    }

    // Sharpen diterapkan SETELAH stretch (bukan sebelum) supaya tidak ikut
    // menajamkan noise dari pixel yang baru saja di-clip.
    image = img.convolution(image, filter: [0, -1, 0, -1, 5, -1, 0, -1, 0]);

    return await _saveTemp(image);
  }

  /// Hitung titik hitam (persentil 1%) & titik putih (persentil 99%) dari
  /// histogram luminance. Histogram dihitung dari versi downscale 300px
  /// (bukan resolusi penuh) supaya cepat — cukup representatif untuk
  /// menentukan dynamic range foto.
  ///
  /// Return null kalau dynamic range sudah lebar (>150 level) — dianggap
  /// sudah cukup kontras, tidak perlu di-stretch lagi.
  (int, int)? _computeHistogramStretch(img.Image image) {
    final sample =
        image.width > 300 ? img.copyResize(image, width: 300) : image;

    final hist = List<int>.filled(256, 0);
    for (final px in sample) {
      final l = img.getLuminance(px).round().clamp(0, 255);
      hist[l]++;
    }

    final total = sample.width * sample.height;
    final edgeCount = (total * 0.01).round().clamp(1, total);

    int low = 0;
    int cum = 0;
    for (int i = 0; i < 256; i++) {
      cum += hist[i];
      if (cum >= edgeCount) {
        low = i;
        break;
      }
    }

    int high = 255;
    cum = 0;
    for (int i = 255; i >= 0; i--) {
      cum += hist[i];
      if (cum >= edgeCount) {
        high = i;
        break;
      }
    }

    if (high <= low || (high - low) > 150) return null;
    return (low, high);
  }

  /// Stretch linear seluruh channel RGB dari rentang [low, high] ke [0, 255].
  img.Image _applyStretch(img.Image image, int low, int high) {
    final range = (high - low).clamp(1, 255);
    for (final px in image) {
      px.r = (((px.r - low) / range) * 255).clamp(0, 255);
      px.g = (((px.g - low) / range) * 255).clamp(0, 255);
      px.b = (((px.b - low) / range) * 255).clamp(0, 255);
    }
    return image;
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
      image = img.convolution(image, filter: [0,-1,0,-1,5,-1,0,-1,0]);
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
