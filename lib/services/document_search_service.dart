import 'package:flutter/foundation.dart';
import '../models/scanned_document.dart';

enum DocumentSortOrder { newest, oldest, title }

/// Menjalankan pencarian/filter dokumen.
///
/// Memilih jalur pencarian berdasarkan ukuran koleksi DAN perkiraan total
/// teks OCR. Koleksi kecil dengan payload kecil diproses langsung untuk
/// menghindari overhead spawn/serialisasi isolate; koleksi besar atau yang
/// membawa OCR berat tetap dipindahkan ke background isolate.
///
/// [isolateThreshold] tetap dipertahankan karena dipakai di tempat lain
/// (home_screen.dart) untuk indikator loading.
class DocumentSearchService {
  static const int isolateThreshold = 150;
  static const int _smallCollectionThreshold = 80;
  static const int _largeTextThreshold = 120000;

  static Future<List<ScannedDocument>> filter(
    List<ScannedDocument> documents,
    String query, {
    DateTime? startDate,
    DateTime? endDate,
    DocumentSortOrder? sortOrder,
  }) async {
    final hasQuery = query.trim().isNotEmpty;
    if (!hasQuery && startDate == null && endDate == null && sortOrder == null) {
      return documents;
    }

    final normalized = query.trim().toLowerCase();
    // Avoid isolate spawn/serialization overhead for genuinely small searches,
    // while still protecting the UI when a small collection contains very
    // large OCR payloads.
    final estimatedText = documents.fold<int>(
      0,
      (sum, d) => sum + d.title.length + (d.extractedText?.length ?? 0),
    );
    final matches = !hasQuery
        ? documents
        : documents.length < _smallCollectionThreshold &&
                estimatedText < _largeTextThreshold
            ? _filterSync(_FilterArgs(documents, normalized))
            : await compute(_filterSync, _FilterArgs(documents, normalized));

    final start = startDate == null
        ? null
        : DateTime(startDate.year, startDate.month, startDate.day);
    final endExclusive = endDate == null
        ? null
        : DateTime(endDate.year, endDate.month, endDate.day + 1);
    final result = matches.where((document) {
      final createdDate = DateTime(
        document.createdAt.year,
        document.createdAt.month,
        document.createdAt.day,
      );
      if (start != null && createdDate.isBefore(start)) return false;
      if (endExclusive != null && !createdDate.isBefore(endExclusive)) {
        return false;
      }
      return true;
    }).toList();

    switch (sortOrder) {
      case DocumentSortOrder.newest:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case DocumentSortOrder.oldest:
        result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case DocumentSortOrder.title:
        result.sort((a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case null:
        break;
    }
    return result;
  }
}

class _FilterArgs {
  final List<ScannedDocument> documents;
  final String query;
  const _FilterArgs(this.documents, this.query);
}

/// Top-level function (dibutuhkan oleh [compute]) yang melakukan filter
/// sesungguhnya. Dipakai baik untuk jalur sinkron maupun jalur isolate.
List<ScannedDocument> _filterSync(_FilterArgs args) {
  final query = args.query.trim().toLowerCase();
  if (query.isEmpty) return args.documents;
  return args.documents.where((d) => d.matchesQuery(query)).toList();
}
