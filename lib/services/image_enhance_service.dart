import 'dart:developer' as developer;
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

Future<String> _prepareForOcrIsolate(_OcrPrepareParams params) async {
  final svc = ImageEnhanceService();
  return svc._processPrepareForOcr(
    params.imagePath,
    tempDirectoryPath: params.tempDirectoryPath,
  );
}

Future<String> _prepareForOcrEnhancedIsolate(_OcrPrepareParams params) async {
  final svc = ImageEnhanceService();
  return svc._processPrepareForOcrEnhanced(
    params.imagePath,
    tempDirectoryPath: params.tempDirectoryPath,
  );
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

// BUG (share: "file yang dikirim bukan foto" saat multi-share): akar
// masalahnya di DocumentStorageService.saveImages() — halaman disalin ke
// penyimpanan permanen lewat tempFile.copy(newPath) MENTAH-MENTAH, byte
// apa adanya, dan newPath SELALU dikasih ekstensi ".jpg" TANPA PERNAH
// mengecek apakah isi filenya benar-benar JPEG. Untuk halaman hasil scan
// kamera (cunning_document_scanner) ini kebetulan selalu benar (memang
// JPEG asli). Tapi untuk halaman yang ditambahkan lewat "Tambah dari
// Galeri" (ScannerService.importFromGallery(), pakai image_picker),
// device Android/iOS modern sering menyimpan galeri dalam format lain
// (PNG hasil screenshot, WEBP, HEIC/HEIF dari kamera iPhone/Android
// terbaru) — file-file ini ikut disalin apa adanya tapi diberi nama
// "page_N.jpg" dan ditandai mimeType 'image/jpeg' di semua titik share
// (BulkShareService, ScanController.shareImages,
// DocumentDetailScreen._shareAsImages). Aplikasi tujuan (WhatsApp,
// Telegram, dst) yang memvalidasi MAGIC BYTES aktual (bukan cuma percaya
// ekstensi/mimeType yang diklaim) melihat ketidakcocokan ini dan sering
// menampilkannya sebagai lampiran dokumen/file generik alih-alih foto,
// atau gagal menampilkan preview — persis gejala "file yang dikirimkan
// bukan foto" yang paling sering muncul saat share BANYAK halaman
// sekaligus (makin banyak halaman, makin besar peluang salah satunya
// berasal dari galeri).
// Fix: [ensureJpeg] mengecek 3 byte pertama file (magic number JPEG:
// 0xFF 0xD8 0xFF) TANPA baca seluruh file — kalau sudah JPEG asli
// (mayoritas kasus: hasil scan kamera), return path apa adanya, nol
// overhead tambahan. Kalau BUKAN JPEG, baru decode (auto-deteksi format
// asli lewat img.decodeImage, yang otomatis mengenali PNG/WEBP/GIF/BMP
// dari byte-nya, bukan dari ekstensi) + re-encode jadi JPEG asli di
// background isolate (compute()) — hasilnya file YANG BENAR-BENAR JPEG,
// sehingga ekstensi ".jpg" & mimeType 'image/jpeg' yang dipasang di
// seluruh titik share menjadi klaim yang BENAR, bukan cuma nama.
// Dipanggil dari DocumentStorageService.saveImages() (sebelum halaman
// masuk penyimpanan permanen — sekali normalisasi di sini, semua share
// berikutnya dari dokumen ini otomatis aman) dan dari
// ScanController.shareImages() (share langsung dari sesi scan aktif,
// SEBELUM saveImages() sempat berjalan — jalur ini butuh jaring
// pengaman sendiri karena _imagePaths di titik itu masih path temp
// mentah, bisa saja hasil galeri yang belum ternormalisasi).
Future<String> _ensureJpegIsolate(String imagePath) async {
  final svc = ImageEnhanceService();
  return svc._processEnsureJpeg(imagePath);
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

// Pass plugin-derived paths from the root isolate. Calling path_provider
// inside compute() requires background messenger initialization and causes
// BackgroundIsolateBinaryMessenger.instance errors on Android.
class _OcrPrepareParams {
  final String imagePath;
  final String tempDirectoryPath;
  const _OcrPrepareParams(this.imagePath, this.tempDirectoryPath);
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
  /// Batas 2048px mempertahankan lebih banyak detail karakter kecil.
  /// Grayscale tetap dipakai untuk menghemat memori. Dijalankan di isolate.
  Future<String> prepareForOcr(String imagePath) async {
    final tempDirectoryPath = (await getTemporaryDirectory()).path;
    return compute(
      _prepareForOcrIsolate,
      _OcrPrepareParams(imagePath, tempDirectoryPath),
    );
  }

  /// Fallback OCR preprocessing for difficult photos. Kept separate from
  /// the primary path so good photos never pay for aggressive enhancement.
  Future<String> prepareForOcrEnhanced(String imagePath) async {
    final tempDirectoryPath = (await getTemporaryDirectory()).path;
    return compute(
      _prepareForOcrEnhancedIsolate,
      _OcrPrepareParams(imagePath, tempDirectoryPath),
    );
  }

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

  /// Pastikan [imagePath] BENAR-BENAR file JPEG (dicek dari magic bytes,
  /// bukan dari ekstensi nama file) — lihat catatan lengkap di
  /// [_ensureJpegIsolate] soal bug "file yang dikirim bukan foto" saat
  /// share. Kalau sudah JPEG asli, return path yang sama tanpa kerja
  /// tambahan (fast path — berlaku untuk mayoritas kasus: halaman hasil
  /// scan kamera). Kalau bukan (mis. PNG/WEBP/HEIC dari galeri), decode +
  /// re-encode ke JPEG asli di background isolate, return path file BARU.
  Future<String> ensureJpeg(String imagePath) async {
    if (await _looksLikeJpeg(imagePath)) return imagePath;
    return compute(_ensureJpegIsolate, imagePath);
  }

  /// Varian [ensureJpeg] yang menimpa file di PATH YANG SAMA alih-alih
  /// mengembalikan path baru. Dipakai untuk migrasi satu-kali dokumen
  /// lama (lihat DocumentStorageService.migrateNormalizeImageFormats())
  /// di mana path halaman sudah tercatat permanen di
  /// documents_meta.json — mengubah path berarti harus ikut menulis
  /// ulang metadata tiap dokumen, jauh lebih rumit & berisiko daripada
  /// cukup memperbaiki ISI file di path yang sudah ada. Sama seperti
  /// ensureJpeg(), no-op (tidak baca/tulis apa pun) kalau file yang
  /// dicek sudah JPEG asli.
  Future<void> ensureJpegInPlace(String imagePath) async {
    if (await _looksLikeJpeg(imagePath)) return;
    final normalizedPath = await compute(_ensureJpegIsolate, imagePath);
    final source = File(normalizedPath);
    final target = File(imagePath);
    // Temp replacement harus berada di direktori yang sama dengan target
    // agar rename tetap berada pada filesystem yang sama. Dengan begitu
    // migrasi tidak pernah menulis byte JPEG setengah jadi langsung ke file
    // permanen. Rename menjadi satu operasi replacement pada Android/Linux.
    final targetDir = target.parent;
    final tempPath =
        '${targetDir.path}/.${target.uri.pathSegments.last}.${DateTime.now().microsecondsSinceEpoch}.tmp';
    final replacement = File(tempPath);
    try {
      await source.copy(tempPath);
      await replacement.rename(imagePath);
    } finally {
      // normalizedPath adalah file perantara dari isolate.
      try {
        await source.delete();
      } catch (_) {}
      // Jika proses gagal sebelum rename, jangan tinggalkan temp replacement.
      try {
        if (await replacement.exists()) await replacement.delete();
      } catch (_) {}
    }
  }

  /// Cek magic number JPEG (0xFF 0xD8 0xFF) dari 3 byte pertama saja —
  /// tidak baca seluruh file, jauh lebih murah daripada decode penuh.
  /// Kegagalan baca (file hilang, dst) dianggap "bukan JPEG" supaya
  /// caller jatuh ke jalur decode+encode yang punya penanganan error
  /// sendiri (lempar exception yang jelas), bukan diam-diam lolos.
  Future<bool> _looksLikeJpeg(String imagePath) async {
    RandomAccessFile? raf;
    try {
      raf = await File(imagePath).open();
      final header = await raf.read(3);
      return header.length == 3 &&
          header[0] == 0xFF &&
          header[1] == 0xD8 &&
          header[2] == 0xFF;
    } catch (_) {
      return false;
    } finally {
      await raf?.close();
    }
  }

  // ── INTERNAL (dipanggil dari isolate) ──
  //
  // FIX (P1 — Image Editor berpotensi menghapus file asli): tujuh fungsi di
  // bawah (_processRotate, _processFlipHorizontal, _processCrop,
  // _processAutoEnhance, _processManualEnhance, _processCompress,
  // _processThumbnail) sebelumnya `return imagePath;` (mengembalikan PATH
  // INPUT apa adanya) kalau img.decodeImage() gagal (null) — dimaksudkan
  // sebagai "gagal, kembalikan yang lama saja". Tapi caller (semua lewat
  // compute() di atas) tidak bisa membedakan return value ini dari file
  // BARU yang benar-benar berhasil dibuat — keduanya sama-sama String.
  // ImageEditorScreen (lihat _rotate/_flip/_applyCrop/_applyPreset/
  // _applyManualEnhance) langsung `_generatedPaths.add(result)` atas
  // SEMUA return value tanpa kecuali, dengan asumsi tiap hasil adalah file
  // temp baru yang aman dihapus di dispose() kalau tidak jadi dipakai
  // sebagai _resultPath. Kalau decode gagal PADA OPERASI PERTAMA (saat
  // _currentPath == _originalPath == widget.imagePath — file scan asli
  // dari Scan Flow, BUKAN salinan), return value yang "gagal" itu sama
  // dengan _originalPath — dan _originalPath pun ikut masuk ke
  // _generatedPaths. Skenario selanjutnya: (a) user tekan "Batal"/close
  // tanpa _resultPath pernah di-set → dispose() menghapus SEMUA isi
  // _generatedPaths, termasuk _originalPath — foto sumber asli hilang
  // permanen meski user bermaksud MEMBATALKAN edit. (b) user lanjut edit
  // lagi sampai berhasil (menghasilkan file BARU sebagai _resultPath) →
  // dispose() menghapus semua _generatedPaths KECUALI _resultPath —
  // _originalPath (yang nyasar masuk _generatedPaths di langkah pertama)
  // tetap ikut terhapus, padahal bukan file perantara yang tidak dipakai.
  // Fix: decode gagal adalah KEGAGALAN OPERASI, bukan "berhasil tapi tidak
  // berubah" — lempar exception (sama seperti _processPrepareForOcr &
  // _processPrepareForPdf yang sudah benar melakukan ini), supaya caller
  // (blok try/catch di ImageEditorScreen) menampilkan pesan error dan
  // TIDAK PERNAH mencatat path input sebagai hasil generate baru.

  Future<String> _processRotate(String imagePath, int angle) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) throw Exception('Gagal decode gambar: $imagePath');
    image = img.bakeOrientation(image);
    image = img.copyRotate(image, angle: angle);
    return await _saveTemp(image);
  }

  Future<String> _processFlipHorizontal(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) throw Exception('Gagal decode gambar: $imagePath');
    image = img.bakeOrientation(image);
    image = img.flipHorizontal(image);
    return await _saveTemp(image);
  }

  Future<String> _processCrop(_CropParams p) async {
    final bytes = await File(p.imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Gagal decode gambar: ${p.imagePath}');
    }
    image = img.bakeOrientation(image);
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
    if (image == null) throw Exception('Gagal decode gambar: $imagePath');
    image = img.bakeOrientation(image);

    // PROFILING: _correctIllumination() adalah loop per-pixel (O(width×
    // height), dengan clamp+divide per channel) — kandidat kuat jadi
    // bagian paling berat dari pipeline auto-enhance, tapi belum pernah
    // diukur nyata di device (cuma dugaan dari membaca kode). Dibungkus
    // Timeline.timeSync di sini (bukan cuma di sekitar seluruh
    // _processAutoEnhance) supaya kontribusi tahap INI secara spesifik
    // kelihatan terpisah dari tone-mapping & sharpen di DevTools Timeline
    // (fungsi ini jalan di background isolate lewat compute() — event
    // Timeline dari isolate non-main tetap tercatat & terlihat per-isolate
    // di Observatory/DevTools, jadi tetap berguna diukur di sini, bukan
    // cuma di isolate utama). Android Profiler (CPU Profiler → method
    // trace) di device fisik kelas menengah-bawah adalah pelengkap yang
    // lebih representatif untuk keputusan lanjutan (mis. apakah perlu
    // downscale peta iluminasi lebih agresif) dibanding angka di emulator.
    developer.Timeline.startSync('ImageEnhance.correctIllumination');
    // 1) Ratakan pencahayaan tidak merata dulu, supaya langkah berikutnya
    // menghitung statistik dari kondisi yang sudah rata — bukan campuran
    // area terang & gelap dalam satu foto.
    try {
      image = _correctIllumination(image);
    } finally {
      developer.Timeline.finishSync();
    }

    // 2) Titik hitam/putih (persentil 1%/99%) + gamma adaptif dihitung dari
    // HASIL koreksi iluminasi, digabung jadi satu LUT, diterapkan 1 pass.
    developer.Timeline.startSync('ImageEnhance.toneMapping');
    try {
      final stretch = _computeHistogramStretch(image);
      final lut = _buildToneLut(image, stretch);
      image = _applyLut(image, lut);
    } finally {
      developer.Timeline.finishSync();
    }

    // 3) Sharpen adaptif, diterapkan TERAKHIR supaya tidak menajamkan noise
    // dari pixel yang baru saja di-stretch/di-clip.
    developer.Timeline.startSync('ImageEnhance.adaptiveSharpen');
    try {
      image = _applyAdaptiveSharpen(image);
    } finally {
      developer.Timeline.finishSync();
    }

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
    if (image == null) {
      throw Exception('Gagal decode gambar: ${p.imagePath}');
    }
    image = img.bakeOrientation(image);

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
    if (image == null) {
      throw Exception('Gagal decode gambar: ${p.imagePath}');
    }
    image = img.bakeOrientation(image);

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

  /// Decode format asli apa pun yang dikenali package:image (PNG, WEBP,
  /// GIF, BMP, dst — dideteksi dari byte, bukan ekstensi) lalu re-encode
  /// jadi JPEG asli. Dipanggil dari isolate lewat [ensureJpeg]/
  /// [_ensureJpegIsolate] — lihat catatan lengkap di sana. Quality 92
  /// (sama seperti _saveTemp) supaya konversi format ini sendiri tidak
  /// jadi sumber degradasi kualitas yang terlihat.
  Future<String> _processEnsureJpeg(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Gagal decode gambar (format tidak dikenali): $imagePath');
    }
    return _saveTempNamed(image, 'normalized', quality: 92);
  }

  /// FIX (P2 — Thumbnail square crop): sebelumnya copyResizeCropSquare()
  /// crop TENGAH ke 200x200 — untuk dokumen (umumnya potret, rasio jauh
  /// dari 1:1), ini membuang bagian atas (biasanya kop/judul surat) dan
  /// bawah (biasanya tanda tangan/stempel) foto, cuma menyisakan strip
  /// tengah yang seringkali kosong/kurang representatif untuk mengenali
  /// dokumen mana yang mana di grid.
  /// Fix: fit-within (downscale mempertahankan aspect ratio penuh, sisi
  /// terpanjang = 200px) lalu taruh di tengah kanvas 200x200 putih —
  /// letterbox, bukan crop. Ukuran file output tetap persegi 200x200
  /// (kontrak dengan DocumentCard/ImageGrid tidak berubah), tapi seluruh
  /// halaman tetap kelihatan, tidak ada konten yang hilang.
  Future<String> _processThumbnail(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) throw Exception('Gagal decode gambar: $imagePath');
    image = img.bakeOrientation(image);

    const canvasSize = 200;
    final fitted = image.width >= image.height
        ? img.copyResize(image, width: canvasSize)
        : img.copyResize(image, height: canvasSize);

    final canvas = img.Image(
      width: canvasSize,
      height: canvasSize,
      numChannels: 3,
    )..clear(img.ColorRgb8(255, 255, 255));

    final offsetX = ((canvasSize - fitted.width) / 2).round();
    final offsetY = ((canvasSize - fitted.height) / 2).round();
    img.compositeImage(canvas, fitted, dstX: offsetX, dstY: offsetY);
    image = canvas;

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

  /// Fallback OCR preprocessing untuk foto sulit.
  ///
  /// Jalur utama sengaja tidak diubah. Fallback ini menambahkan contrast,
  /// sharpening ringan, lalu binarisasi Otsu setelah resize/grayscale.
  /// Karena hanya dipakai ketika OCR utama kosong, preprocessing agresif
  /// tidak dapat merusak hasil OCR yang sudah berhasil.
  Future<String> _processPrepareForOcrEnhanced(
    String imagePath, {
    required String tempDirectoryPath,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Gagal decode gambar: $imagePath');
    image = img.bakeOrientation(image);

    const maxOcrDimension = 2048;
    if (image.width > maxOcrDimension || image.height > maxOcrDimension) {
      image = img.copyResize(
        image,
        width: image.width > image.height ? maxOcrDimension : -1,
        height: image.height >= image.width ? maxOcrDimension : -1,
        interpolation: img.Interpolation.linear,
      );
    }

    image = img.grayscale(image);

    // Deskew is intentionally restricted to the enhanced fallback path.
    // The original image and primary OCR path remain untouched. Estimate the
    // angle on a small preview, then rotate only when the projection score
    // indicates a clear improvement; this avoids expensive full-resolution
    // angle searches and reduces the risk of rotating an already-straight page.
    final deskewAngle = _estimateDeskewAngle(image);
    if (deskewAngle.abs() >= 0.5) {
      image = img.copyRotate(image, angle: deskewAngle);
    }

    image = img.contrast(image, contrast: 70);
    image = img.convolution(
      image,
      filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
    );
    image = _binarizeOtsu(image);

    return _saveTempNamed(
      image,
      'ocr_enhanced',
      quality: 95,
      directoryPath: tempDirectoryPath,
    );
  }

  /// Estimate small text-line skew by maximizing horizontal projection
  /// concentration. Work on a downscaled preview so this fallback remains
  /// bounded on high-resolution phone photos. Returns 0 when no confident
  /// improvement is found; rotation is limited to +/- 7 degrees.
  double _estimateDeskewAngle(img.Image source) {
    const maxPreviewDimension = 800;
    final preview = source.width > maxPreviewDimension ||
            source.height > maxPreviewDimension
        ? img.copyResize(
            source,
            width: source.width >= source.height ? maxPreviewDimension : -1,
            height: source.height > source.width ? maxPreviewDimension : -1,
            interpolation: img.Interpolation.average,
          )
        : source;

    final baseline = _horizontalProjectionScore(preview, 0);
    var bestScore = baseline;
    var bestAngle = 0.0;
    for (var step = -14; step <= 14; step++) {
      final angle = step * 0.5;
      if (angle == 0) continue;
      final score = _horizontalProjectionScore(preview, angle);
      if (score > bestScore) {
        bestScore = score;
        bestAngle = angle;
      }
    }

    // Require a meaningful score improvement; otherwise avoid changing pixels.
    if (baseline <= 0 || (bestScore - baseline) / baseline < 0.025) {
      return 0;
    }
    return bestAngle;
  }

  double _horizontalProjectionScore(img.Image source, double angle) {
    final rotated = angle == 0 ? source : img.copyRotate(source, angle: angle);
    final rowCounts = List<int>.filled(rotated.height, 0);
    // Sample every second pixel to keep the angle search inexpensive.
    for (var y = 0; y < rotated.height; y += 2) {
      for (var x = 0; x < rotated.width; x += 2) {
        if (img.getLuminance(rotated.getPixel(x, y)) < 180) {
          rowCounts[y]++;
        }
      }
    }
    var score = 0.0;
    for (var y = 1; y < rowCounts.length; y += 2) {
      final difference = rowCounts[y] - rowCounts[y - 1];
      score += difference * difference;
    }
    return score;
  }

  img.Image _binarizeOtsu(img.Image image) {
    final histogram = List<int>.filled(256, 0);
    for (final px in image) {
      histogram[img.getLuminance(px).round().clamp(0, 255)]++;
    }

    final total = image.width * image.height;
    if (total == 0) return image;

    var sumAll = 0.0;
    for (var i = 0; i < histogram.length; i++) {
      sumAll += i * histogram[i];
    }

    var weightBackground = 0;
    var sumBackground = 0.0;
    var bestVariance = -1.0;
    var threshold = 128;
    for (var i = 0; i < histogram.length; i++) {
      weightBackground += histogram[i];
      if (weightBackground == 0) continue;
      final weightForeground = total - weightBackground;
      if (weightForeground == 0) break;
      sumBackground += i * histogram[i];
      final meanBackground = sumBackground / weightBackground;
      final meanForeground = (sumAll - sumBackground) / weightForeground;
      final diff = meanBackground - meanForeground;
      final variance =
          weightBackground.toDouble() * weightForeground * diff * diff;
      if (variance > bestVariance) {
        bestVariance = variance;
        threshold = i;
      }
    }

    for (final px in image) {
      final value = img.getLuminance(px) >= threshold ? 255 : 0;
      px.r = value;
      px.g = value;
      px.b = value;
    }
    return image;
  }

  /// Resize ke max 2048px + konversi grayscale untuk OCR.
  /// Grayscale hemat ~⅓ memori dan tidak menurunkan akurasi ML Kit.
  Future<String> _processPrepareForOcr(
    String imagePath, {
    required String tempDirectoryPath,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Gagal decode gambar: $imagePath');
    image = img.bakeOrientation(image);

    // Resize bila lebih lebar/tinggi dari 2048px. Batas ini sengaja
    // lebih tinggi dari pipeline lama (1600px) agar karakter kecil tidak
    // kehilangan detail sebelum masuk ke ML Kit.
    const maxOcrDimension = 2048;
    if (image.width > maxOcrDimension || image.height > maxOcrDimension) {
      image = img.copyResize(
        image,
        width: image.width > image.height ? maxOcrDimension : -1,
        height: image.height >= image.width ? maxOcrDimension : -1,
        interpolation: img.Interpolation.linear,
      );
    }

    // Grayscale — ML Kit teks tidak butuh warna
    image = img.grayscale(image);

    return _saveTempNamed(
      image,
      'ocr_prep',
      quality: 95,
      directoryPath: tempDirectoryPath,
    );
  }

  /// Resize ke max 1920px + kompres ke quality 85 sebelum masuk PDF pipeline.
  Future<String> _processPrepareForPdf(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Gagal decode gambar: $imagePath');
    image = img.bakeOrientation(image);

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
  Future<String> _saveTempNamed(
    img.Image image,
    String prefix, {
    int quality = 92,
    String? directoryPath,
  }) async {
    final dirPath = directoryPath ?? (await getTemporaryDirectory()).path;
    final name = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outPath = '${dirPath}/$name';
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
