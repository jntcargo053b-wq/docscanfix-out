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

// ── Main service ─────────────────────────────────────────────────────────────

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

  Future<String> _processAutoEnhance(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return imagePath;
    image = _autoLevels(image);
    image = _applyContrast(image, 1.25);
    image = _sharpenImage(image);
    image = _applyBrightness(image, 15);
    return await _saveTemp(image);
  }

  Future<String> _processManualEnhance(_ManualParams p) async {
    final bytes = await File(p.imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return p.imagePath;
    if (p.grayscale) image = img.grayscale(image);
    if (p.brightness != 1.0) {
      image = _applyBrightness(image, ((p.brightness - 1.0) * 128).round());
    }
    if (p.contrast != 1.0) image = _applyContrast(image, p.contrast);
    if (!p.grayscale && p.saturation != 1.0) {
      image = _applySaturation(image, p.saturation);
    }
    if (p.sharpen) image = _sharpenImage(image);
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

    final dir = await getTemporaryDirectory();
    final name = 'compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outPath = '${dir.path}/$name';
    await File(outPath).writeAsBytes(
      Uint8List.fromList(img.encodeJpg(image, quality: p.quality)),
    );
    return outPath;
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

  // ── IMAGE PROCESSING HELPERS ──

  img.Image _autoLevels(img.Image src) {
    int minV = 255, maxV = 0;
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        final lum = (p.r * 0.299 + p.g * 0.587 + p.b * 0.114).round();
        if (lum < minV) minV = lum;
        if (lum > maxV) maxV = lum;
      }
    }
    final range = (maxV - minV).clamp(1, 255);
    final dst = img.Image(width: src.width, height: src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        dst.setPixelRgb(x, y,
          (((p.r.toInt() - minV) * 255) ~/ range).clamp(0, 255),
          (((p.g.toInt() - minV) * 255) ~/ range).clamp(0, 255),
          (((p.b.toInt() - minV) * 255) ~/ range).clamp(0, 255),
        );
      }
    }
    return dst;
  }

  img.Image _applyBrightness(img.Image src, int delta) {
    final dst = img.Image(width: src.width, height: src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        dst.setPixelRgb(x, y,
          (p.r.toInt() + delta).clamp(0, 255),
          (p.g.toInt() + delta).clamp(0, 255),
          (p.b.toInt() + delta).clamp(0, 255),
        );
      }
    }
    return dst;
  }

  img.Image _applyContrast(img.Image src, double factor) {
    final dst = img.Image(width: src.width, height: src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        dst.setPixelRgb(x, y,
          ((p.r.toInt() - 128) * factor + 128).clamp(0, 255).toInt(),
          ((p.g.toInt() - 128) * factor + 128).clamp(0, 255).toInt(),
          ((p.b.toInt() - 128) * factor + 128).clamp(0, 255).toInt(),
        );
      }
    }
    return dst;
  }

  img.Image _applySaturation(img.Image src, double factor) {
    final dst = img.Image(width: src.width, height: src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        final gray = r * 0.299 + g * 0.587 + b * 0.114;
        dst.setPixelRgb(x, y,
          (gray + (r - gray) * factor).clamp(0, 255).toInt(),
          (gray + (g - gray) * factor).clamp(0, 255).toInt(),
          (gray + (b - gray) * factor).clamp(0, 255).toInt(),
        );
      }
    }
    return dst;
  }

  img.Image _sharpenImage(img.Image src) {
    final dst = img.Image(width: src.width, height: src.height);
    for (int y = 1; y < src.height - 1; y++) {
      for (int x = 1; x < src.width - 1; x++) {
        final c  = src.getPixel(x, y);
        final t  = src.getPixel(x, y - 1);
        final bm = src.getPixel(x, y + 1);
        final l  = src.getPixel(x - 1, y);
        final r  = src.getPixel(x + 1, y);
        dst.setPixelRgb(x, y,
          (c.r*5 - t.r - bm.r - l.r - r.r).clamp(0,255).toInt(),
          (c.g*5 - t.g - bm.g - l.g - r.g).clamp(0,255).toInt(),
          (c.b*5 - t.b - bm.b - l.b - r.b).clamp(0,255).toInt(),
        );
      }
    }
    for (int x = 0; x < src.width; x++) {
      dst.setPixel(x, 0, src.getPixel(x, 0));
      dst.setPixel(x, src.height - 1, src.getPixel(x, src.height - 1));
    }
    for (int y = 0; y < src.height; y++) {
      dst.setPixel(0, y, src.getPixel(0, y));
      dst.setPixel(src.width - 1, y, src.getPixel(src.width - 1, y));
    }
    return dst;
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
