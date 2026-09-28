import 'package:flutter_test/flutter_test.dart';
import 'package:docscan/models/scanned_document.dart';
import 'package:docscan/services/document_search_service.dart';

ScannedDocument makeDocument(int index, {String? text}) => ScannedDocument(
      id: 'doc-$index',
      title: 'Document $index',
      imagePaths: const [],
      extractedText: text,
      createdAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: index)),
    );

void main() {
  group('DocumentSearchService.filter', () {
    test('returns the original collection for an empty query', () async {
      final documents = [makeDocument(1), makeDocument(2)];

      expect(await DocumentSearchService.filter(documents, ''), same(documents));
      expect(
        await DocumentSearchService.filter(documents, '   '),
        same(documents),
      );
    });

    test('matches title and OCR text without case sensitivity', () async {
      final documents = [
        makeDocument(1, text: 'Paid by ACME'),
        makeDocument(2, text: 'Pending approval'),
        makeDocument(3),
      ];

      final byTitle =
          await DocumentSearchService.filter(documents, 'DOCUMENT 2');
      final byOcr = await DocumentSearchService.filter(documents, 'acme');

      expect(byTitle.map((document) => document.id), ['doc-2']);
      expect(byOcr.map((document) => document.id), ['doc-1']);
    });

    test('filters large collections through the isolate path', () async {
      final documents = List.generate(
        200,
        (index) => makeDocument(
          index,
          text: index == 177 ? 'Reference ZX-177' : 'General document',
        ),
      );

      final result = await DocumentSearchService.filter(documents, 'zx-177');

      expect(result, hasLength(1));
      expect(result.single.id, 'doc-177');
    });

    test('trims whitespace from the query', () async {
      final documents = [
        makeDocument(1, text: 'Unique reference ABC-123'),
      ];

      final result =
          await DocumentSearchService.filter(documents, '  ABC-123  ');

      expect(result, hasLength(1));
      expect(result.single.id, 'doc-1');
    });
  });
}
