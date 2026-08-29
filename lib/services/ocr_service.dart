import 'dart:async';
import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  static final OcrService _instance = OcrService._internal();
  factory OcrService() => _instance;
  OcrService._internal();

  // Timeout per halaman — cegah hang pada gambar beresolusi sangat tinggi
  static const Duration _perPageTimeout = Duration(seconds: 15);
  // Timeout keseluruhan dokumen multi-halaman
  static const Duration _totalTimeout = Duration(seconds: 60);

  // PERF FIX (OCR multi-halaman terasa lambat): extractTextFromImages()
  // sebelumnya proses halaman STRICT SEQUENTIAL — satu TextRecognizer
  // dipakai bergantian, halaman ke-N nunggu halaman ke-(N-1) selesai total
  // sebelum mulai. Untuk dokumen 20-50 halaman, total waktu = jumlah waktu
  // SEMUA halaman, padahal saveDocument() bisa saja nunggu ini kalau user
  // tekan "Simpan" sebelum OCR background selesai (lihat _runOcr() di
  // ScanController).
  // Fix: pool 2 instance TextRecognizer TERPISAH, proses 2 halaman
  // BERSAMAAN per giliran (Future.wait) — tiap instance tetap dipanggil
  // SATU per satu ke dirinya sendiri (tidak ada 2 processImage() bersamaan
  // di instance recognizer yang SAMA, yang tidak terjamin aman lewat
  // platform channel ML Kit), tapi 2 instance berbeda memang didesain
  // untuk dipakai independen/paralel. Ini murni soal THROUGHPUT (jumlah
  // halaman per detik), BUKAN soal resolusi/kualitas gambar — akurasi per
  // halaman tidak berubah sama sekali (ImageEnhanceService.prepareForOcr()
  // yang menentukan itu, downsize 1600px + grayscale, tidak disentuh).
  // Ukuran pool sengaja kecil (2, bukan lebih) — ML Kit text recognition
  // sudah cukup berat per panggilan (CPU/NPU-bound di native), pool besar
  // berisiko malah memperlambat (kontensi resource) alih-alih mempercepat,
  // apalagi di HP kelas menengah-bawah yang jadi target app ini.
  static const int _poolSize = 2;
  final List<TextRecognizer?> _recognizers = List<TextRecognizer?>.filled(_poolSize, null);

  // ML Kit recognizers are native resources. Serialize whole multi-page OCR
  // sessions so two callers cannot concurrently consume the same singleton
  // pool and create uncontrolled native CPU/memory contention. Within one
  // session we still use the two independent recognizers in parallel.
  Future<void> _ocrQueue = Future<void>.value();

  Future<T> _withOcrQueue<T>(Future<T> Function() action) async {
    final previous = _ocrQueue;
    final release = Completer<void>();
    _ocrQueue = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  TextRecognizer _recognizerAt(int slot) {
    return _recognizers[slot] ??= TextRecognizer(script: TextRecognitionScript.latin);
  }

  TextRecognizer get _textRecognizer => _recognizerAt(0);

  /// Extract text from a single image, dengan timeout [_perPageTimeout].
  /// [slot] menentukan instance TextRecognizer mana dari pool yang dipakai
  /// (default 0) — dipakai oleh [extractTextFromImages] untuk memproses
  /// beberapa halaman paralel tanpa berbagi instance yang sama.
  Future<String> extractTextFromImage(String imagePath, {int slot = 0}) async {
    try {
      final inputImage = InputImage.fromFile(File(imagePath));
      final RecognizedText recognizedText = await _recognizerAt(slot)
          .processImage(inputImage)
          .timeout(
            _perPageTimeout,
            onTimeout: () => throw TimeoutException(
              'OCR timeout setelah ${_perPageTimeout.inSeconds}s pada: $imagePath',
            ),
          );
      return recognizedText.text;
    } on TimeoutException {
      // Kembalikan string kosong — jangan blok halaman lain karena satu halaman lambat
      return '';
    } catch (e) {
      throw Exception('OCR gagal: $e');
    }
  }

  /// Extract text dari banyak halaman, dengan total timeout [_totalTimeout].
  ///
  /// Menggunakan flag [cancelled] sebagai cancellation token. Setelah timeout,
  /// flag di-set true sehingga batch berikutnya di loop langsung skip — loop
  /// tidak terus berjalan di background setelah fungsi ini return.
  ///
  /// PERF FIX (pool 2 recognizer — lihat catatan lengkap di [_poolSize]):
  /// diproses [_poolSize] halaman per giliran secara PARALEL (Future.wait),
  /// masing-masing di instance TextRecognizer terpisah dari pool. Urutan
  /// hasil di [buffer] tetap sesuai urutan halaman asli (Future.wait
  /// mengembalikan hasil dalam urutan input, terlepas dari urutan
  /// selesainya) — nomor "Halaman N" di output tidak berubah perilakunya
  /// sama sekali dibanding sebelumnya, cuma throughput-nya yang naik.
  ///
  /// BUG FIX sekalian (satu halaman error dulu menggagalkan SISA dokumen):
  /// sebelumnya exception non-timeout dari satu halaman (mis. error native
  /// ML Kit) lolos ke catch() di luar loop dan MENGHENTIKAN seluruh proses
  /// — halaman-halaman setelahnya tidak pernah di-OCR meski filenya baik-
  /// baik saja. Sekarang tiap panggilan individual dibungkus try/catch
  /// sendiri — satu halaman gagal cuma jadi teks kosong untuk halaman itu,
  /// halaman lain tetap diproses.
  Future<String> extractTextFromImages(List<String> imagePaths) async {
    return _withOcrQueue<String>(() => _extractTextFromImagesImpl(imagePaths));
  }

  Future<String> _extractTextFromImagesImpl(List<String> imagePaths) async {
    final results = List<String>.filled(imagePaths.length, '');
    bool cancelled = false;

    final timer = Timer(_totalTimeout, () { cancelled = true; });

    try {
      for (int start = 0; start < imagePaths.length; start += _poolSize) {
        if (cancelled) break; // berhenti sebelum batch baru dimulai

        final end = (start + _poolSize < imagePaths.length)
            ? start + _poolSize
            : imagePaths.length;

        final batchResults = await Future.wait([
          for (int i = start; i < end; i++)
            _safeExtract(imagePaths[i], slot: i - start),
        ]);

        if (cancelled) break; // berhenti setelah batch selesai

        for (int i = start; i < end; i++) {
          results[i] = batchResults[i - start];
        }
      }
    } catch (_) {
      // partial result tetap dikembalikan
    } finally {
      timer.cancel();
    }

    // Susun buffer dari [results] (urutan halaman asli, terlepas dari
    // urutan selesainya tiap batch) — halaman yang belum sempat diproses
    // (mis. karena cancelled sebelum batch-nya mulai) tetap '' bawaan.
    final buffer = StringBuffer();
    for (int i = 0; i < results.length; i++) {
      if (results[i].isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write('\n\n--- Halaman ${i + 1} ---\n\n');
      buffer.write(results[i]);
    }
    return buffer.toString();
  }

  /// Bungkus [extractTextFromImage] supaya error non-timeout dari SATU
  /// halaman tidak ikut melempar ke [Future.wait] pemanggil (yang akan
  /// membatalkan seluruh batch, termasuk halaman lain yang baik-baik
  /// saja) — lihat catatan lengkap di [extractTextFromImages].
  Future<String> _safeExtract(String imagePath, {required int slot}) async {
    try {
      return await extractTextFromImage(imagePath, slot: slot);
    } catch (_) {
      return '';
    }
  }

  /// Extract structured text with block and line positions.
  Future<OcrResult> extractStructuredText(String imagePath) async {
    try {
      final inputImage = InputImage.fromFile(File(imagePath));
      final RecognizedText recognizedText = await _textRecognizer
          .processImage(inputImage)
          .timeout(_perPageTimeout);

      final blocks = recognizedText.blocks.map((block) {
        return OcrBlock(
          text: block.text,
          lines: block.lines.map((line) => line.text).toList(),
          boundingBox: BlockBoundingBox(
            left: block.boundingBox.left,
            top: block.boundingBox.top,
            right: block.boundingBox.right,
            bottom: block.boundingBox.bottom,
          ),
        );
      }).toList();

      return OcrResult(fullText: recognizedText.text, blocks: blocks);
    } on TimeoutException {
      return OcrResult(fullText: '', blocks: []);
    } catch (e) {
      throw Exception('OCR gagal: $e');
    }
  }

  void dispose() {
    for (int i = 0; i < _recognizers.length; i++) {
      _recognizers[i]?.close();
      _recognizers[i] = null;
    }
  }
}

class OcrResult {
  final String fullText;
  final List<OcrBlock> blocks;

  OcrResult({required this.fullText, required this.blocks});

  bool get isEmpty => fullText.trim().isEmpty;
  int get wordCount =>
      fullText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  int get lineCount => fullText.split('\n').where((l) => l.isNotEmpty).length;
}

class OcrBlock {
  final String text;
  final List<String> lines;
  final BlockBoundingBox boundingBox;

  OcrBlock({
    required this.text,
    required this.lines,
    required this.boundingBox,
  });
}

class BlockBoundingBox {
  final double left, top, right, bottom;
  BlockBoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
}
