import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:docscan/services/image_enhance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  Directory? tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('docscan_ocr_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getTemporaryDirectory') {
        return tempDirectory!.path;
      }
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDirectory!.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (tempDirectory != null && await tempDirectory!.exists()) {
      await tempDirectory!.delete(recursive: true);
    }
  });

  test('enhanced OCR preprocessing handles representative image conditions without changing source', () async {
    final service = ImageEnhanceService();
    final variants = <String, img.Image Function()>{
      'normal': () => _documentLikeImage(),
      'dark': () => _darken(_documentLikeImage()),
      'shadow': () => _addUnevenShadow(_documentLikeImage()),
      'tilted': () => img.copyRotate(_documentLikeImage(), angle: 3),
      'no-text': () => img.Image(width: 320, height: 420, numChannels: 3)
        ..clear(img.ColorRgb8(245, 245, 245)),
    };

    for (final entry in variants.entries) {
      final sourcePath = '${tempDirectory!.path}/${entry.key}.jpg';
      final sourceBytes = img.encodeJpg(entry.value(), quality: 95);
      await File(sourcePath).writeAsBytes(sourceBytes);

      final before = await File(sourcePath).readAsBytes();
      final enhancedPath = await service.prepareForOcrEnhanced(sourcePath);
      final enhancedFile = File(enhancedPath);

      expect(await enhancedFile.exists(), isTrue, reason: entry.key);
      final enhancedImage = img.decodeImage(await enhancedFile.readAsBytes());
      expect(enhancedImage, isNotNull, reason: entry.key);
      expect(await File(sourcePath).readAsBytes(), before,
          reason: 'preprocessing must not overwrite source: ${entry.key}');

      if (enhancedPath != sourcePath && await enhancedFile.exists()) {
        await enhancedFile.delete();
      }
    }
  });

  test('primary OCR preparation emits a decodable image and preserves source', () async {
    final sourcePath = '${tempDirectory!.path}/primary.jpg';
    await File(sourcePath).writeAsBytes(img.encodeJpg(_documentLikeImage()));
    final before = await File(sourcePath).readAsBytes();

    final preparedPath =
        await ImageEnhanceService().prepareForOcr(sourcePath);

    expect(img.decodeImage(await File(preparedPath).readAsBytes()), isNotNull);
    expect(await File(sourcePath).readAsBytes(), before);
    if (preparedPath != sourcePath && await File(preparedPath).exists()) {
      await File(preparedPath).delete();
    }
  });
}

img.Image _documentLikeImage() {
  final image = img.Image(width: 360, height: 480, numChannels: 3)
    ..clear(img.ColorRgb8(250, 250, 250));

  // Synthetic text-like strokes: repeated rows with gaps similar to printed
  // characters, sufficient to exercise thresholding/deskew without fixtures.
  for (var row = 0; row < 8; row++) {
    final yStart = 55 + row * 42;
    for (var y = yStart; y < yStart + 15; y++) {
      for (var x = 28; x < 330; x++) {
        final glyphColumn = ((x - 28) % 17) < 3;
        final horizontalStroke = (y - yStart) < 2;
        if (glyphColumn || horizontalStroke) {
          final pixel = image.getPixel(x, y);
          pixel.r = 25;
          pixel.g = 25;
          pixel.b = 25;
        }
      }
    }
  }
  return image;
}

img.Image _darken(img.Image image) {
  for (final pixel in image) {
    pixel.r = (pixel.r * 0.42).round();
    pixel.g = (pixel.g * 0.42).round();
    pixel.b = (pixel.b * 0.42).round();
  }
  return image;
}

img.Image _addUnevenShadow(img.Image image) {
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final factor = 0.48 + 0.52 * x / image.width;
      final pixel = image.getPixel(x, y);
      pixel.r = (pixel.r * factor).round();
      pixel.g = (pixel.g * factor).round();
      pixel.b = (pixel.b * factor).round();
    }
  }
  return image;
}
