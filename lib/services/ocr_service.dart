import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  static final OcrService _instance = OcrService._internal();
  factory OcrService() => _instance;
  OcrService._internal();

  // Supports Latin, Chinese, Devanagari, Japanese, Korean
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  /// Extract text from a single image
  Future<String> extractTextFromImage(String imagePath) async {
    try {
      final inputImage = InputImage.fromFile(File(imagePath));
      final RecognizedText recognizedText =
          await _textRecognizer.processImage(inputImage);
      return recognizedText.text;
    } catch (e) {
      throw Exception('OCR failed: $e');
    }
  }

  /// Extract text from multiple images (multi-page document)
  Future<String> extractTextFromImages(List<String> imagePaths) async {
    final StringBuffer buffer = StringBuffer();

    for (int i = 0; i < imagePaths.length; i++) {
      final text = await extractTextFromImage(imagePaths[i]);
      if (text.isNotEmpty) {
        if (i > 0) buffer.write('\n\n--- Halaman ${i + 1} ---\n\n');
        buffer.write(text);
      }
    }

    return buffer.toString();
  }

  /// Extract structured text with block and line positions
  Future<OcrResult> extractStructuredText(String imagePath) async {
    try {
      final inputImage = InputImage.fromFile(File(imagePath));
      final RecognizedText recognizedText =
          await _textRecognizer.processImage(inputImage);

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

      return OcrResult(
        fullText: recognizedText.text,
        blocks: blocks,
      );
    } catch (e) {
      throw Exception('OCR failed: $e');
    }
  }

  /// Dispose recognizer when done
  void dispose() {
    _textRecognizer.close();
  }
}

class OcrResult {
  final String fullText;
  final List<OcrBlock> blocks;

  OcrResult({required this.fullText, required this.blocks});

  bool get isEmpty => fullText.trim().isEmpty;
  int get wordCount => fullText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
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
