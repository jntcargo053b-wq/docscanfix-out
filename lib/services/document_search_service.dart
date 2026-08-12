import 'package:flutter/foundation.dart';
import '../models/scanned_document.dart';

/// Menjalankan pencarian/filter dokumen.
///
/// SELALU dijalankan lewat [compute] di background isolate, apa pun ukuran
/// koleksinya, supaya UI thread tidak pernah ikut nge-block sedikit pun
/// saat men-scan extractedText — konsisten dan dapat diprediksi, tidak
/// bergantung pada tebakan ambang jumlah dokumen yang bisa meleset untuk
/// koleksi dengan extractedText sangat panjang tapi jumlah dokumen sedikit
/// (di bawah ambang tapi tetap berat untuk di-scan sinkron).
///
/// [isolateThreshold] tetap dipertahankan (bukan dihapus) hanya karena
/// dipakai di tempat lain (home_screen.dart) untuk memutuskan kapan
/// menampilkan indikator loading — bukan lagi untuk memutuskan jalur
/// sinkron/isolate di sini.
class DocumentSearchService {
  static const int isolateThreshold = 150;

  static Future<List<ScannedDocument>> filter(
    List<ScannedDocument> documents,
    String query,
  ) async {
    if (query.trim().isEmpty) return documents;

    final args = _FilterArgs(documents, query);
    return compute(_filterSync, args);
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
