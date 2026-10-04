import 'package:flutter_test/flutter_test.dart';
import 'package:docscan/models/scanned_document.dart';

void main() {
  group('ScannedDocument serialization', () {
    test('round-trips document fields', () {
      final createdAt = DateTime.utc(2026, 9, 28, 10, 30);
      final original = ScannedDocument(
        id: 'doc-001',
        title: 'Invoice September',
        imagePaths: const ['/docs/page-1.jpg', '/docs/page-2.jpg'],
        pageTexts: const ['Page one OCR', 'Page two OCR'],
        extractedText: 'Invoice number 123',
        createdAt: createdAt,
        pdfPath: '/docs/invoice.pdf',
        thumbnailPath: '/docs/thumb.jpg',
      );

      final restored = ScannedDocument.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.pageTexts, original.pageTexts);
      expect(restored.imagePaths, original.imagePaths);
      expect(restored.extractedText, original.extractedText);
      expect(restored.createdAt, createdAt);
      expect(restored.pdfPath, original.pdfPath);
      expect(restored.thumbnailPath, original.thumbnailPath);
      expect(restored.pageCount, 2);
    });

    test('supports older metadata with optional fields missing', () {
      final restored = ScannedDocument.fromJson({
        'id': 'legacy-001',
        'title': 'Legacy document',
        'imagePaths': ['/docs/legacy.jpg'],
        'createdAt': '2026-01-02T03:04:05.000Z',
      });

      expect(restored.id, 'legacy-001');
      expect(restored.title, 'Legacy document');
      expect(restored.imagePaths, ['/docs/legacy.jpg']);
      expect(restored.pageTexts, isEmpty);
      expect(restored.extractedText, isNull);
      expect(restored.pdfPath, isNull);
      expect(restored.thumbnailPath, isNull);
    });
  });

  group('ScannedDocument search and copying', () {
    test('matches title and OCR text case-insensitively', () {
      final document = ScannedDocument(
        id: 'doc-002',
        title: 'Delivery Note',
        imagePaths: const [],
        extractedText: 'SHIPMENT TO MALANG',
        createdAt: DateTime.utc(2026),
      );

      expect(document.matchesQuery('delivery'), isTrue);
      expect(document.matchesQuery('shipment to malang'), isTrue);
      expect(document.matchesQuery('NOT PRESENT'), isFalse);
    });

    test('search includes per-page OCR and returns a focused snippet', () {
      final document = ScannedDocument(
        id: 'doc-006',
        title: 'Receipt',
        imagePaths: const ['/docs/a.jpg'],
        pageTexts: const ['Customer order number ABC-12345 and delivery address'],
        createdAt: DateTime.utc(2026),
      );

      expect(document.matchesQuery('abc-12345'), isTrue);
      final snippet = document.searchSnippet('ABC-12345');
      expect(snippet, isNotNull);
      expect(snippet, contains('ABC-12345'));
    });

    test('copyWith preserves fields not explicitly changed', () {
      final original = ScannedDocument(
        id: 'doc-003',
        title: 'Original',
        imagePaths: const ['/docs/a.jpg'],
        extractedText: 'Recognized text',
        createdAt: DateTime.utc(2026),
      );

      final updated = original.copyWith(title: 'Updated');

      expect(updated.title, 'Updated');
      expect(updated.id, original.id);
      expect(updated.imagePaths, original.imagePaths);
      expect(updated.extractedText, original.extractedText);
      expect(updated.createdAt, original.createdAt);
    });

    test('rename preserves pages and invalidates cached PDF', () {
      final original = ScannedDocument(
        id: 'doc-005',
        title: 'Old title',
        imagePaths: const ['/docs/a.jpg', '/docs/b.jpg'],
        pageTexts: const ['Page A', 'Page B'],
        createdAt: DateTime.utc(2026),
        pdfPath: '/docs/old-title.pdf',
        thumbnailPath: '/docs/thumb.jpg',
      );

      final renamed = original.copyWith(
        title: 'New title',
        clearPdfPath: true,
      );

      expect(renamed.title, 'New title');
      expect(renamed.imagePaths, original.imagePaths);
      expect(renamed.pageTexts, original.pageTexts);
      expect(renamed.thumbnailPath, original.thumbnailPath);
      expect(renamed.pdfPath, isNull);
    });

    test('can clear cached PDF and thumbnail paths', () {
      final original = ScannedDocument(
        id: 'doc-004',
        title: 'Cached',
        imagePaths: const ['/docs/a.jpg'],
        createdAt: DateTime.utc(2026),
        pdfPath: '/docs/a.pdf',
        thumbnailPath: '/docs/a-thumb.jpg',
      );

      final updated = original.copyWith(
        clearPdfPath: true,
        clearThumbnailPath: true,
      );

      expect(updated.pdfPath, isNull);
      expect(updated.thumbnailPath, isNull);
    });
  });
}
