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


    test('filters by inclusive calendar date range without requiring a query', () async {
      final documents = [
        ScannedDocument(
          id: 'before',
          title: 'Before',
          imagePaths: const [],
          createdAt: DateTime(2026, 1, 31, 23, 59),
        ),
        ScannedDocument(
          id: 'start',
          title: 'Start',
          imagePaths: const [],
          createdAt: DateTime(2026, 2, 1, 0, 1),
        ),
        ScannedDocument(
          id: 'end',
          title: 'End',
          imagePaths: const [],
          createdAt: DateTime(2026, 2, 3, 23, 59),
        ),
        ScannedDocument(
          id: 'after',
          title: 'After',
          imagePaths: const [],
          createdAt: DateTime(2026, 2, 4),
        ),
      ];

      final result = await DocumentSearchService.filter(
        documents,
        '',
        startDate: DateTime(2026, 2, 1),
        endDate: DateTime(2026, 2, 3),
      );

      expect(result.map((document) => document.id), ['start', 'end']);
    });

    test('sorts matching documents by newest, oldest, or title', () async {
      final documents = [
        makeDocument(2).copyWith(title: 'Beta'),
        makeDocument(1).copyWith(title: 'alpha'),
        makeDocument(3).copyWith(title: 'Charlie'),
      ];

      final newest = await DocumentSearchService.filter(
        documents, '', sortOrder: DocumentSortOrder.newest,
      );
      final oldest = await DocumentSearchService.filter(
        documents, '', sortOrder: DocumentSortOrder.oldest,
      );
      final title = await DocumentSearchService.filter(
        documents, '', sortOrder: DocumentSortOrder.title,
      );

      expect(newest.map((document) => document.id), ['doc-3', 'doc-2', 'doc-1']);
      expect(oldest.map((document) => document.id), ['doc-1', 'doc-2', 'doc-3']);
      expect(title.map((document) => document.title), ['alpha', 'Beta', 'Charlie']);
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
