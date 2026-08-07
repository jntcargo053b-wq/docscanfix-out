import 'package:flutter/foundation.dart';
import '../models/scanned_document.dart';

/// Menjalankan pencarian/filter dokumen.
///
/// Untuk koleksi kecil, filter jalan langsung (spawn isolate baru untuk
/// setiap keystroke justru lebih mahal daripada scan sinkron singkat).
/// Untuk koleksi besar (jumlah dokumen di atas [isolateThreshold], atau
/// total karakter OCR yang besar), filter dijalankan lewat [compute] di
/// background isolate supaya UI thread tidak nge-block saat men-scan
/// extractedText yang panjang dari banyak dokumen sekaligus.
class DocumentSearchService {
  // Di bawah ambang ini, overhead spawn/message-passing ke isolate lebih
  // mahal daripada scan sinkron singkat (~sub-ms). Di atasnya, terutama saat
  // extractedText panjang (hasil OCR banyak dokumen), scan sinkron bisa makan
  // puluhan ms dan bikin keystroke terasa nge-jank — jadi dilempar ke isolate.
  static const int isolateThreshold = 150;

  static Future<List<ScannedDocument>> filter(
    List<ScannedDocument> documents,
    String query,
  ) async {
    if (query.trim().isEmpty) return documents;

    final args = _FilterArgs(documents, query);
    if (documents.length < isolateThreshold) {
      return _filterSync(args);
    }
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
