import 'dart:io';
import 'package:share_plus/share_plus.dart';
import '../models/scanned_document.dart';
import 'document_storage_service.dart';
import 'pdf_service.dart';

/// Batas aman untuk sekali share. Ini bukan batas keras dari Android sendiri
/// (FileProvider cuma mengirim content:// URI lewat intent, bukan isi file),
/// tapi banyak app tujuan (WhatsApp, Gmail, Telegram, dst) punya batas jumlah
/// lampiran & ukuran total sendiri, dan generate PDF untuk ratusan dokumen
/// bisa memakan waktu lama tanpa disadari user. Batas ini dipakai untuk
/// memberi peringatan sebelum proses berat dimulai, bukan untuk memblokir.
class ShareLimits {
  static const int maxItemCount = 100;
  static const int maxTotalBytes = 200 * 1024 * 1024; // 200 MB
}

/// Dilempar saat user membatalkan proses share yang sedang berjalan.
class BulkShareCancelled implements Exception {
  @override
  String toString() => 'Proses dibagikan dibatalkan';
}

class BulkShareEstimate {
  final int itemCount;
  final int totalBytes;
  final bool exceedsLimit;

  const BulkShareEstimate({
    required this.itemCount,
    required this.totalBytes,
    required this.exceedsLimit,
  });

  String get formattedSize {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1048576) return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    return '${(totalBytes / 1048576).toStringAsFixed(1)} MB';
  }
}

/// Progres proses bulk share: dokumen ke berapa dari berapa, dan label
/// dokumen yang sedang diproses (ditampilkan di dialog progres).
class BulkShareProgress {
  final int current;
  final int total;
  final String label;
  const BulkShareProgress(this.current, this.total, this.label);
}

typedef ShareProgressCallback = void Function(BulkShareProgress progress);
typedef DocumentUpdatedCallback = void Function(ScannedDocument updated);

class BulkShareService {
  final PdfService _pdfService;
  final DocumentStorageService _storageService;
  bool _cancelRequested = false;

  BulkShareService({
    PdfService? pdfService,
    DocumentStorageService? storageService,
  })  : _pdfService = pdfService ?? PdfService(),
        _storageService = storageService ?? DocumentStorageService();

  /// Minta pembatalan; dicek di antara setiap file/dokumen yang diproses
  /// (bukan mid-file), supaya tidak meninggalkan PDF setengah jadi.
  void cancel() => _cancelRequested = true;

  void _checkCancelled() {
    if (_cancelRequested) throw BulkShareCancelled();
  }

  /// Estimasi cepat jumlah & ukuran file gambar dari dokumen terpilih,
  /// dipakai untuk peringatan sebelum share dimulai.
  Future<BulkShareEstimate> estimateImages(List<ScannedDocument> docs) async {
    int count = 0;
    int bytes = 0;
    for (final doc in docs) {
      for (final p in doc.imagePaths) {
        final file = File(p);
        if (await file.exists()) {
          count++;
          bytes += await file.length();
        }
      }
    }
    return BulkShareEstimate(
      itemCount: count,
      totalBytes: bytes,
      exceedsLimit: count > ShareLimits.maxItemCount ||
          bytes > ShareLimits.maxTotalBytes,
    );
  }

  /// Estimasi untuk mode PDF. Dokumen yang sudah punya pdfPath dihitung dari
  /// file aslinya; yang belum di-generate diestimasi dari total ukuran
  /// gambar sumbernya (perkiraan kasar, PDF biasanya sedikit lebih ringkas).
  Future<BulkShareEstimate> estimatePdfs(List<ScannedDocument> docs) async {
    int bytes = 0;
    for (final doc in docs) {
      final pdfPath = doc.pdfPath;
      if (pdfPath != null && await File(pdfPath).exists()) {
        bytes += await File(pdfPath).length();
        continue;
      }
      for (final p in doc.imagePaths) {
        final file = File(p);
        if (await file.exists()) bytes += await file.length();
      }
    }
    return BulkShareEstimate(
      itemCount: docs.length,
      totalBytes: bytes,
      exceedsLimit: docs.length > ShareLimits.maxItemCount ||
          bytes > ShareLimits.maxTotalBytes,
    );
  }

  /// Bagikan semua halaman dari dokumen terpilih sebagai gambar.
  /// Melapor progres per halaman lewat [onProgress].
  Future<void> shareAsImages(
    List<ScannedDocument> docs, {
    ShareProgressCallback? onProgress,
  }) async {
    _cancelRequested = false;
    final validDocs = docs.where((d) => d.imagePaths.isNotEmpty).toList();
    final totalPages =
        validDocs.fold<int>(0, (sum, d) => sum + d.imagePaths.length);

    final files = <XFile>[];
    int done = 0;
    for (final doc in validDocs) {
      // FIX: sebelumnya XFile dibuat tanpa `name:`, jadi nama file yang
      // dikirim ke share sheet ikut nama asli di disk (page_1.jpg,
      // page_2.jpg, dst — penomoran mulai dari 1 lagi di tiap dokumen).
      // Kalau lebih dari satu dokumen dipilih, nama file antar dokumen
      // BENTROK (page_1.jpg dari dokumen A = page_1.jpg dari dokumen B),
      // dan aplikasi tujuan (email/WA/dll) bisa menimpa atau membingungkan
      // salah satunya. Sekarang tiap file diberi nama unik berbasis judul
      // dokumen + nomor halaman.
      for (int i = 0; i < doc.imagePaths.length; i++) {
        final p = doc.imagePaths[i];
        _checkCancelled();
        if (await File(p).exists()) {
          files.add(XFile(
            p,
            mimeType: 'image/jpeg',
            name: '${_safeFileName(doc.title)}_hal${i + 1}.jpg',
          ));
        }
        done++;
        onProgress?.call(BulkShareProgress(done, totalPages, doc.title));
      }
    }

    if (files.isEmpty) {
      throw Exception('Tidak ada gambar yang tersedia dari dokumen terpilih');
    }

    await Share.shareXFiles(
      files,
      subject: '${docs.length} dokumen',
      text: '${docs.length} dokumen (${files.length} halaman total)',
    );
  }

  /// Bersihkan judul dokumen supaya aman dipakai sebagai nama file
  /// (buang karakter yang tidak valid di sebagian besar filesystem/app
  /// tujuan share, dan cegah nama file kosong).
  static String _safeFileName(String title) {
    final cleaned = title.trim().replaceAll(RegExp(r'[^\w\s-]'), '_');
    return cleaned.isEmpty ? 'Dokumen' : cleaned;
  }

  /// Bagikan dokumen terpilih sebagai PDF. Dokumen yang belum punya PDF akan
  /// digenerate satu per satu (proses paling berat), melapor progres per
  /// dokumen lewat [onProgress]. [onDocumentUpdated] dipanggil setiap kali
  /// PDF baru dibuat, supaya pemanggil bisa sinkronkan cache in-memory-nya
  /// tanpa perlu reload semua dokumen dari disk.
  Future<void> shareAsPdf(
    List<ScannedDocument> docs, {
    ShareProgressCallback? onProgress,
    DocumentUpdatedCallback? onDocumentUpdated,
  }) async {
    _cancelRequested = false;
    final files = <XFile>[];
    final total = docs.length;

    for (int i = 0; i < docs.length; i++) {
      _checkCancelled();
      final doc = docs[i];
      onProgress?.call(BulkShareProgress(i, total, doc.title));

      var pdfPath = doc.pdfPath ?? '';
      if (pdfPath.isEmpty || !await File(pdfPath).exists()) {
        pdfPath = await _pdfService.generatePdf(
          title: doc.title,
          imagePaths: doc.imagePaths,
          extractedText: doc.extractedText,
        );
        final updated = doc.copyWith(pdfPath: pdfPath);
        await _storageService.updateDocument(updated);
        onDocumentUpdated?.call(updated);
      }

      files.add(XFile(pdfPath, mimeType: 'application/pdf'));
      onProgress?.call(BulkShareProgress(i + 1, total, doc.title));
    }

    _storageService.invalidateCache();

    if (files.isEmpty) {
      throw Exception('Tidak ada PDF yang bisa dibagikan');
    }

    await Share.shareXFiles(
      files,
      subject: '${docs.length} dokumen',
      text: '${docs.length} dokumen sebagai PDF',
    );
  }
}
