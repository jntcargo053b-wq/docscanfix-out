import 'dart:async';
import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';


class OcrPageResult {
  final String text;
  final bool success;
  final String? errorMessage;

  const OcrPageResult({
    required this.text,
    required this.success,
    this.errorMessage,
  });
}

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
  // yang menentukan itu, downsize 2048px + grayscale, tidak disentuh).
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

  /// Extract text from a single image, preserving the legacy String API.
  /// Use [extractPageResult] when the caller needs success/error information.
  Future<String> extractTextFromImage(String imagePath, {int slot = 0}) async {
    final result = await extractPageResult(imagePath, slot: slot);
    return result.text;
  }

  /// Extract one page with an explicit result status.
  Future<OcrPageResult> extractPageResult(
    String imagePath, {
    int slot = 0,
  }) async {
    _validateSlot(slot);
    if (_isDisposed) {
      return const OcrPageResult(
        text: '',
        success: false,
        errorMessage: 'OCR service sudah dihentikan.',
      );
    }
    return _withOcrQueue<OcrPageResult>(
      () => _extractPageResult(imagePath, slot: slot),
    );
  }

  /// Extract text from many pages using a small worker pool.
  ///
  /// Each worker owns one recognizer slot and takes the next page as soon as
  /// its previous page finishes. This avoids waiting for the slowest page in
  /// a static batch before starting another page.
  ///
  /// [isCancelled] is optional so screen/controller code can stop starting
  /// new work when its lifecycle ends.
  Future<String> extractTextFromImages(
    List<String> imagePaths, {
    void Function(int index, OcrPageResult result)? onPageCompleted,
    bool Function()? isCancelled,
  }) async {
    return _withOcrQueue<String>(() => _extractTextFromImagesImpl(
      imagePaths,
      onPageCompleted: onPageCompleted,
      isCancelled: isCancelled,
    ));
  }

  Future<String> _extractTextFromImagesImpl(
    List<String> imagePaths, {
    void Function(int index, OcrPageResult result)? onPageCompleted,
    bool Function()? isCancelled,
  }) async {
    if (imagePaths.isEmpty) return '';

    final results = List<String>.filled(imagePaths.length, '');
    final statuses = List<OcrPageResult?>.filled(imagePaths.length, null);
    var nextIndex = 0;
    final workerCount = imagePaths.length < _poolSize
        ? imagePaths.length
        : _poolSize;
    final requestedBudgetMs = _perPageTimeout.inMilliseconds *
        ((imagePaths.length + _poolSize - 1) ~/ _poolSize);
    final totalBudgetMs = requestedBudgetMs < _totalTimeout.inMilliseconds
        ? requestedBudgetMs
        : _totalTimeout.inMilliseconds;
    final totalBudget = Duration(milliseconds: totalBudgetMs);
    final deadline = DateTime.now().add(totalBudget);

    Future<void> worker(int slot) async {
      while (true) {
        if (_isDisposed || isCancelled?.call() == true) return;

        final index = nextIndex++;
        if (index >= imagePaths.length) return;

        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          _reportPage(
            index,
            OcrPageResult(
              text: '',
              success: false,
              errorMessage: 'Dilewati karena batas waktu total.',
            ),
            results,
            statuses,
            onPageCompleted,
          );
          continue;
        }

        final pageResult = await _extractPageResult(
          imagePaths[index],
          slot: slot,
          timeout: remaining < _perPageTimeout ? remaining : _perPageTimeout,
        );
        _reportPage(
          index,
          pageResult,
          results,
          statuses,
          onPageCompleted,
        );
      }
    }

    await Future.wait([
      for (var slot = 0; slot < workerCount; slot++) worker(slot),
    ]);

    final wasCancelled = _isDisposed || isCancelled?.call() == true;
    for (var i = 0; i < imagePaths.length; i++) {
      if (statuses[i] != null) continue;
      _reportPage(
        i,
        OcrPageResult(
          text: '',
          success: false,
          errorMessage: wasCancelled
              ? 'Dibatalkan sebelum diproses.'
              : 'Dilewati karena batas waktu total.',
        ),
        results,
        statuses,
        onPageCompleted,
      );
    }

    final buffer = StringBuffer();
    for (var i = 0; i < results.length; i++) {
      final text = results[i].trim();
      if (text.isEmpty) continue;
      buffer
        ..write('--- Halaman ${i + 1} ---')
        ..write('\n')
        ..write(text)
        ..write('\n\n');
    }
    return buffer.toString().trim();
  }

  void _reportPage(
    int index,
    OcrPageResult result,
    List<String> results,
    List<OcrPageResult?> statuses,
    void Function(int index, OcrPageResult result)? onPageCompleted,
  ) {
    results[index] = result.text;
    statuses[index] = result;
    try {
      onPageCompleted?.call(index, result);
    } catch (_) {
      // A UI callback must never abort the OCR worker pool.
    }
  }

  Future<OcrPageResult> _extractPageResult(
    String imagePath, {
    required int slot,
    Duration timeout = _perPageTimeout,
  }) async {
    _validateSlot(slot);
    if (_isDisposed) {
      return const OcrPageResult(
        text: '',
        success: false,
        errorMessage: 'OCR service sudah dihentikan.',
      );
    }
    try {
      final inputImage = InputImage.fromFile(File(imagePath));
      final recognizedText = await _recognizerAt(slot)
          .processImage(inputImage)
          .timeout(timeout);
      return OcrPageResult(text: recognizedText.text, success: true);
    } on TimeoutException {
      await _resetRecognizer(slot);
      return OcrPageResult(
        text: '',
        success: false,
        errorMessage: 'OCR timeout setelah ${timeout.inSeconds}s',
      );
    } catch (e) {
      return OcrPageResult(
        text: '',
        success: false,
        errorMessage: 'OCR gagal: $e',
      );
    }
  }

  void _validateSlot(int slot) {
    if (slot < 0 || slot >= _poolSize) {
      throw RangeError.range(slot, 0, _poolSize - 1, 'slot');
    }
  }

  Future<void> _resetRecognizer(int slot) async {
    final recognizer = _recognizers[slot];
    _recognizers[slot] = null;
    if (recognizer != null) {
      try {
        await recognizer.close();
      } catch (_) {}
    }
  }

  /// Extract structured text with block and line positions.
  Future<OcrResult> extractStructuredText(String imagePath) async {
    if (_isDisposed) {
      return OcrResult(fullText: '', blocks: []);
    }

    return _withOcrQueue<OcrResult>(() async {
      try {
        final inputImage = InputImage.fromFile(File(imagePath));
        final recognizedText = await _recognizerAt(0)
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
        await _resetRecognizer(0);
        return OcrResult(fullText: '', blocks: []);
      } catch (e) {
        throw Exception('OCR gagal: $e');
      }
    });
  }

  bool _isDisposed = false;

  /// Queue disposal behind any active OCR request so native recognizers are
  /// not closed while their platform call is still being awaited.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    unawaited(_withOcrQueue<void>(() async {
      for (var i = 0; i < _recognizers.length; i++) {
        final recognizer = _recognizers[i];
        _recognizers[i] = null;
        if (recognizer != null) {
          try {
            await recognizer.close();
          } catch (_) {}
        }
      }
    }));
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
