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
    // FIX: nama file sebelumnya cuma "<judul>_hal<N>.jpg". Judul dokumen
    // default ("Scan DD-MM-YYYY HH:MM") cuma presisi menit, jadi kalau user
    // scan 2+ dokumen dalam menit yang sama (sangat mungkin saat scan
    // berturut-turut), judulnya identik → nama file antar dokumen BENTROK
    // lagi persis seperti bug lama (page_1.jpg vs page_1.jpg), meski kali
    // ini isi path aslinya beda per dokumen. Di beberapa platform share
    // (terutama iOS) file-file yang dibagikan sekaligus disalin ke folder
    // temp berdasarkan `name` sebelum share sheet dibuka — kalau namanya
    // sama, salinan belakangan MENIMPA salinan sebelumnya di temp, jadi
    // semua lampiran yang namanya bentrok berakhir jadi gambar yang sama.
    // Fix: tambahkan nomor urut GLOBAL (lintas dokumen) di depan nama file,
    // supaya nama selalu unik apa pun judul dokumennya.
    int globalIndex = 0;
    for (final doc in validDocs) {
      for (int i = 0; i < doc.imagePaths.length; i++) {
        final p = doc.imagePaths[i];
        _checkCancelled();
        globalIndex++;
        if (await File(p).exists()) {
          files.add(XFile(
            p,
            mimeType: 'image/jpeg',
            name: '${globalIndex}_${_safeFileName(doc.title)}_hal${i + 1}.jpg',
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

    // FIX (integrasi penamaan): sebelumnya XFile PDF dibuat tanpa `name:`,
    // jadi nama file yang sampai ke aplikasi tujuan cuma ikut basename file
    // fisiknya di disk (dari PdfService.generatePdf: "<judul>_<millis>.pdf").
    // Itu sebetulnya sudah unik, tapi menampilkan timestamp mentah yang
    // tidak ramah-pengguna ke penerima file. Sekarang dibangun nama bersih
    // dari judul dokumen + nomor urut GLOBAL (pola sama seperti
    // shareAsImages di atas) supaya nama tetap unik meski ada 2+ dokumen
    // terpilih dengan judul identik (mis. user rename manual jadi sama).
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
        // FIX (P1 — updateDocument() critical masih deferred): pdfPath ini
        // adalah hasil PdfService.generatePdf() yang baru saja selesai
        // (kerja mahal: decode+resize+encode tiap halaman). immediate:
        // true supaya tidak hilang kalau app di-kill sebelum debounce
        // 500ms sempat jalan — lihat komentar lengkap di
        // DocumentStorageService.updateDocument().
        await _storageService.updateDocument(updated, immediate: true);
        onDocumentUpdated?.call(updated);
      }

      files.add(XFile(
        pdfPath,
        mimeType: 'application/pdf',
        name: '${i + 1}_${_safeFileName(doc.title)}.pdf',
      ));
      onProgress?.call(BulkShareProgress(i + 1, total, doc.title));
    }

    await _storageService.invalidateCache();

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
