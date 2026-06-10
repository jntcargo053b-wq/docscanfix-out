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

  TextRecognizer? _recognizer;

  TextRecognizer get _textRecognizer {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _recognizer!;
  }

  /// Extract text from a single image, dengan timeout [_perPageTimeout].
  Future<String> extractTextFromImage(String imagePath) async {
    try {
      final inputImage = InputImage.fromFile(File(imagePath));
      final RecognizedText recognizedText = await _textRecognizer
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
  /// flag di-set true sehingga iterasi berikutnya di loop langsung skip — loop
  /// tidak terus berjalan di background setelah fungsi ini return.
  Future<String> extractTextFromImages(List<String> imagePaths) async {
    final buffer = StringBuffer();
    bool cancelled = false;

    final timer = Timer(_totalTimeout, () { cancelled = true; });

    try {
      for (int i = 0; i < imagePaths.length; i++) {
        if (cancelled) break;                    // berhenti sebelum halaman baru dimulai

        final text = await extractTextFromImage(imagePaths[i]);

        if (cancelled) break;                    // berhenti setelah await selesai

        if (text.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write('\n\n--- Halaman ${i + 1} ---\n\n');
          buffer.write(text);
        }
      }
    } catch (_) {
      // partial result tetap dikembalikan
    } finally {
      timer.cancel();
    }

    return buffer.toString();
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
    _recognizer?.close();
    _recognizer = null;
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
