import 'dart:io';
import 'dart:math' as math;
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

  /// Auto-enhance ADAPTIF — semua parameter dihitung dari kondisi foto itu
  /// sendiri, bukan konstanta tetap. Pipeline 3 tahap, tiap tahap
  /// menganalisis hasil tahap sebelumnya supaya konsisten baik foto terang,
  /// gelap, maupun berbayang (pencahayaan tidak merata):
  ///
  ///   1. Koreksi iluminasi (flat-field) — meratakan bayangan/gradient
  ///      cahaya secara SPASIAL, sebelum statistik global dihitung.
  ///   2. Tone mapping (black/white stretch + gamma) — 1 LUT gabungan yang
  ///      dihitung dari histogram & median foto pasca-koreksi iluminasi.
  ///   3. Sharpen — kekuatannya diskalakan turun untuk foto noisy/low-light
  ///      supaya tidak ikut menajamkan grain.
  ///
  /// Implementasi lama pakai offset TETAP (+15 brightness, +25 contrast)
  /// untuk SEMUA foto, dan hanya melihat histogram global — jadi dokumen
  /// yang setengah kena bayangan (histogram keseluruhan masih lebar/normal)
  /// tidak pernah "diratakan" bayangannya oleh stretch global manapun.
  Future<String> _processAutoEnhance(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return imagePath;

    // 1) Ratakan pencahayaan tidak merata dulu, supaya langkah berikutnya
    // menghitung statistik dari kondisi yang sudah rata — bukan campuran
    // area terang & gelap dalam satu foto.
    image = _correctIllumination(image);

    // 2) Titik hitam/putih (persentil 1%/99%) + gamma adaptif dihitung dari
    // HASIL koreksi iluminasi, digabung jadi satu LUT, diterapkan 1 pass.
    final stretch = _computeHistogramStretch(image);
    final lut = _buildToneLut(image, stretch);
    image = _applyLut(image, lut);

    // 3) Sharpen adaptif, diterapkan TERAKHIR supaya tidak menajamkan noise
    // dari pixel yang baru saja di-stretch/di-clip.
    image = _applyAdaptiveSharpen(image);

    return await _saveTemp(image);
  }

  /// Koreksi pencahayaan tidak merata (bayangan, gradient cahaya dari
  /// jendela/lampu) dengan flat-field correction: estimasi peta iluminasi
  /// lokal dari versi blur resolusi rendah, lalu tiap pixel dibagi dengan
  /// iluminasi lokalnya (dinormalisasi ke rata-rata iluminasi foto).
  ///
  /// Beda dengan histogram stretch (yang cuma lihat statistik GLOBAL):
  /// dokumen yang setengah kena bayangan tetap bisa punya histogram lebar
  /// secara keseluruhan, jadi stretch global tidak bisa "meratakan" bayangan
  /// itu. Flat-field correction menormalkan pencahayaan secara SPASIAL
  /// terlebih dahulu, baru tone mapping global dijalankan di atas hasil yang
  /// sudah rata.
  img.Image _correctIllumination(img.Image image) {
    // Peta iluminasi dihitung dari downscale kecil + blur radius besar,
    // supaya hanya menangkap gradasi cahaya/bayangan berskala besar — bukan
    // detail teks/garis dokumen (yang harus tetap tajam).
    final mapWidth = image.width > 150 ? 150 : image.width;
    var illumMap = img.copyResize(image,
        width: mapWidth, interpolation: img.Interpolation.average);
    illumMap = img.grayscale(illumMap);
    final blurRadius = (illumMap.width / 6).round().clamp(8, 40);
    illumMap = img.gaussianBlur(illumMap, radius: blurRadius);

    final mapMean = _meanLuminance(illumMap);
    if (mapMean <= 0) return image;

    // Upscale peta iluminasi ke resolusi penuh sebagai divisor per-pixel.
    final fullMap = img.copyResize(illumMap,
        width: image.width,
        height: image.height,
        interpolation: img.Interpolation.linear);

    // Gain di-clamp supaya area yang SANGAT gelap (mis. bayangan tangan)
    // tidak diperkuat berlebihan sampai jadi noise, dan area yang sudah
    // terang tidak digelapkan drastis.
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final px = image.getPixel(x, y);
        final localLum = img.getLuminance(fullMap.getPixel(x, y)).clamp(10, 255);
        final gain = (mapMean / localLum).clamp(0.7, 2.2);
        px.r = (px.r * gain).clamp(0, 255);
        px.g = (px.g * gain).clamp(0, 255);
        px.b = (px.b * gain).clamp(0, 255);
      }
    }
    return image;
  }

  double _meanLuminance(img.Image image) {
    double sum = 0;
    int count = 0;
    for (final px in image) {
      sum += img.getLuminance(px);
      count++;
    }
    return count == 0 ? 0 : sum / count;
  }

  /// Bangun LUT 256-nilai gabungan (black/white stretch + gamma adaptif)
  /// dari histogram foto, supaya stretch dan koreksi gamma diterapkan
  /// dalam SATU pass pixel, bukan dua pass terpisah.
  ///
  /// Gamma-nya sendiri target-nya median luminance ~190 (dekat putih
  /// kertas) — ini melengkapi stretch: stretch cuma meluruskan titik
  /// EKSTREM (hitam/putih), sementara gamma meluruskan DISTRIBUSI TENGAH,
  /// jadi foto yang seluruhnya redup (bukan cuma berbayang) tetap
  /// dinaikkan kecerahannya walau titik hitam/putihnya sudah 0–255.
  List<int> _buildToneLut(img.Image image, (int, int)? stretch) {
    final low = stretch?.$1 ?? 0;
    final high = stretch?.$2 ?? 255;
    final range = (high - low).clamp(1, 255);

    final medianAfterStretch = _estimateMedianAfterStretch(image, low, range);

    double gamma = 1.0;
    if (medianAfterStretch > 0) {
      const target = 190.0;
      final m = (medianAfterStretch / 255).clamp(0.02, 0.98);
      gamma = math.log(target / 255) / math.log(m);
      gamma = gamma.clamp(0.6, 1.8);
    }
    final applyGamma = (gamma - 1.0).abs() >= 0.05;

    return List<int>.generate(256, (i) {
      double v = ((i - low) / range) * 255;
      v = v.clamp(0, 255);
      if (applyGamma) {
        v = math.pow(v / 255, gamma) * 255;
      }
      return v.round().clamp(0, 255);
    });
  }

  /// Perkiraan median luminance SETELAH stretch, dihitung dari sample kecil
  /// (bukan full-res) supaya tidak perlu pass tambahan di gambar penuh.
  double _estimateMedianAfterStretch(img.Image image, int low, int range) {
    final sample =
        image.width > 300 ? img.copyResize(image, width: 300) : image;
    final values = <int>[];
    for (final px in sample) {
      final l = img.getLuminance(px);
      values.add((((l - low) / range) * 255).clamp(0, 255).round());
    }
    if (values.isEmpty) return 0;
    values.sort();
    return values[values.length ~/ 2].toDouble();
  }

  img.Image _applyLut(img.Image image, List<int> lut) {
    for (final px in image) {
      px.r = lut[px.r.round().clamp(0, 255)];
      px.g = lut[px.g.round().clamp(0, 255)];
      px.b = lut[px.b.round().clamp(0, 255)];
    }
    return image;
  }

  /// Sharpen adaptif — kekuatan unsharp mask diskalakan berdasarkan level
  /// noise foto (estimasi dari varians laplacian sample kecil). Foto
  /// low-light yang barusan dinaikkan gain-nya di tahap koreksi iluminasi
  /// biasanya lebih noisy; sharpen penuh di foto begini akan menajamkan
  /// grain, bukan teks. Foto bersih/terang tetap dapat sharpen penuh.
  img.Image _applyAdaptiveSharpen(img.Image image) {
    final noise = _estimateNoise(image);
    final amount = 1.0 - (noise / 25).clamp(0.0, 0.7);
    if (amount < 0.05) return image; // noise sangat tinggi -> skip total

    final sharpened = img.convolution(image.clone(),
        filter: [0, -1, 0, -1, 5, -1, 0, -1, 0]);

    if (amount > 0.95) return sharpened; // foto bersih -> sharpen penuh

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final orig = image.getPixel(x, y);
        final sharp = sharpened.getPixel(x, y);
        orig.r = (orig.r + (sharp.r - orig.r) * amount).clamp(0, 255);
        orig.g = (orig.g + (sharp.g - orig.g) * amount).clamp(0, 255);
        orig.b = (orig.b + (sharp.b - orig.b) * amount).clamp(0, 255);
      }
    }
    return image;
  }

  /// Estimasi noise dari deviasi laplacian pada sample grayscale kecil.
  /// Foto tajam & bersih -> varians laplacian didominasi tepi teks (tinggi
  /// tapi terstruktur). Foto grainy -> varians tinggi tersebar merata.
  /// Sebagai proxy sederhana dipakai standar deviasi laplacian mentah;
  /// cukup untuk membedakan "cukup bersih untuk sharpen penuh" vs
  /// "noisy, kurangi sharpen" tanpa perlu model noise yang rumit.
  double _estimateNoise(img.Image image) {
    final sample =
        image.width > 300 ? img.copyResize(image, width: 300) : image;
    final gray = img.grayscale(sample.clone());
    final lap = img.convolution(gray, filter: [0, 1, 0, 1, -4, 1, 0, 1, 0]);

    double sum = 0, sumSq = 0;
    int count = 0;
    for (final px in lap) {
      final l = img.getLuminance(px);
      sum += l;
      sumSq += l * l;
      count++;
    }
    if (count == 0) return 0;
    final mean = sum / count;
    final variance = (sumSq / count) - (mean * mean);
    return math.sqrt(variance.abs());
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
