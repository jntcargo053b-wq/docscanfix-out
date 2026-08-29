import 'package:flutter/foundation.dart';
import '../models/scanned_document.dart';

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
    String query,
  ) async {
    if (query.trim().isEmpty) return documents;

    final normalized = query.trim().toLowerCase();
    // Avoid isolate spawn/serialization overhead for genuinely small searches,
    // while still protecting the UI when a small collection contains very
    // large OCR payloads.
    final estimatedText = documents.fold<int>(
      0,
      (sum, d) => sum + d.title.length + (d.extractedText?.length ?? 0),
    );
    if (documents.length < _smallCollectionThreshold &&
        estimatedText < _largeTextThreshold) {
      return _filterSync(_FilterArgs(documents, normalized));
    }

    return compute(_filterSync, _FilterArgs(documents, normalized));
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
