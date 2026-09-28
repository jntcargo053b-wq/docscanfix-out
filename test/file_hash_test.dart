import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:docscan/utils/file_hash.dart';

void main() {
  group('hashFileStreaming', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory =
          await Directory.systemTemp.createTemp('docscan_hash_test_');
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('returns the same digest for identical file contents', () async {
      final first = File('${tempDirectory.path}/first.bin');
      final second = File('${tempDirectory.path}/second.bin');
      const content = 'DocScan regression test content';

      await first.writeAsString(content);
      await second.writeAsString(content);

      final firstHash = await hashFileStreaming(first.path);
      final secondHash = await hashFileStreaming(second.path);

      expect(firstHash, isNotNull);
      expect(firstHash, secondHash);
    });

    test('returns different digests for different contents', () async {
      final first = File('${tempDirectory.path}/first.bin');
      final second = File('${tempDirectory.path}/second.bin');

      await first.writeAsString('page one');
      await second.writeAsString('page two');

      final firstHash = await hashFileStreaming(first.path);
      final secondHash = await hashFileStreaming(second.path);

      expect(firstHash, isNotNull);
      expect(secondHash, isNotNull);
      expect(firstHash, isNot(equals(secondHash)));
    });

    test('returns null for a missing file instead of throwing', () async {
      final missingPath = '${tempDirectory.path}/missing.bin';

      expect(await hashFileStreaming(missingPath), isNull);
    });
  });
}
