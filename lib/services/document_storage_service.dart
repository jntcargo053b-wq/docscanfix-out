import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/scanned_document.dart';
import 'image_enhance_service.dart';

/// Top-level (dibutuhkan oleh [compute]): parse JSON string metadata jadi
/// List<ScannedDocument> di background isolate. Dipakai oleh loadDocuments()
/// untuk koleksi besar — lihat catatan di sana.
List<ScannedDocument> _parseDocumentsJson(String jsonStr) {
  final List<dynamic> jsonList = json.decode(jsonStr);
  return jsonList.map((j) => ScannedDocument.fromJson(j)).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

class DocumentStorageService {
  static final DocumentStorageService _instance =
      DocumentStorageService._internal();
  factory DocumentStorageService() => _instance;
  DocumentStorageService._internal();

  static const String _metaFile = 'documents_meta.json';

  // ── In-memory cache to avoid repeated JSON reads ──
  List<ScannedDocument>? _cachedDocuments;
  bool _cacheValid = false;

  // ── Debounce timer for batch writes ──
  Timer? _writeTimer;
  bool _writePending = false;
  static const Duration _writeDelay = Duration(milliseconds: 500);

  // Serialize every cache mutation + metadata write. Without this lock, two
  // async callers can both load the same list, modify it, and then overwrite
  // each other's metadata. A tiny FIFO lock keeps the existing API intact
  // while making add/update/delete/upsert safe under concurrent calls.
  Future<void> _mutationLock = Future<void>.value();

  Future<T> _withMutationLock<T>(Future<T> Function() action) async {
    final previous = _mutationLock;
    final release = Completer<void>();
    _mutationLock = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  Future<Directory> get _docsDir async {
    final dir = await getApplicationDocumentsDirectory();
    final docsDir = Directory('${dir.path}/DocScan/Documents');
    await docsDir.create(recursive: true);
    return docsDir;
  }

  Future<File> get _metaFilePath async {
    final dir = await _docsDir;
    return File('${dir.path}/$_metaFile');
  }

  // PERF (lazy-load metadata untuk koleksi besar): di bawah ukuran file ini,
  // parse sinkron di main isolate (~sub-ms – beberapa ms) tidak terasa. Di
  // atasnya, json.decode() + map(fromJson) atas ribuan entri (tiap entri
  // bisa membawa extractedText hasil OCR yang panjang) bisa memblokir main
  // thread cukup lama untuk terasa nge-jank saat app dibuka/list di-refresh.
  // documents_meta.json TIDAK di-chunk secara fisik (satu file JSON array
  // utuh) — package:convert bawaan Flutter tidak punya streaming JSON
  // parser incremental yang dipakai proyek ini, jadi "streaming" di sini
  // berarti memindahkan decode+parse penuh ke background isolate lewat
  // compute() (bukan mem-parsial baca file), supaya UI thread tetap
  // responsif selama parse berlangsung — bukan mengurangi total kerja
  // parse-nya.
  static const int _largeMetaFileBytes = 256 * 1024; // 256 KB

  /// Load all documents from cache or disk
  /// Cache is validated to avoid stale data across multiple calls
  Future<List<ScannedDocument>> loadDocuments() async {
    if (_cacheValid && _cachedDocuments != null) {
      return List.unmodifiable(_cachedDocuments!);
    }

    try {
      final file = await _metaFilePath;
      if (!await file.exists()) {
        _cachedDocuments = [];
        _cacheValid = true;
        return [];
      }

      final jsonStr = await file.readAsString();
      final fileIsLarge = jsonStr.length > _largeMetaFileBytes;
      _cachedDocuments = fileIsLarge
          ? await compute(_parseDocumentsJson, jsonStr)
          : _parseDocumentsJson(jsonStr);
      _cacheValid = true;
      return List.unmodifiable(_cachedDocuments!);
    } catch (e) {
      // Never silently convert metadata corruption/I/O failure into an empty
      // database. If the primary metadata is damaged, try the last known-good
      // backup produced by _writeMetaAtomic(). If recovery also fails, surface
      // the error so callers do not accidentally overwrite valid documents
      // with an empty list.
      try {
        final file = await _metaFilePath;
        final backup = File('${file.path}.bak');
        if (await backup.exists()) {
          final jsonStr = await backup.readAsString();
          final fileIsLarge = jsonStr.length > _largeMetaFileBytes;
          _cachedDocuments = fileIsLarge
              ? await compute(_parseDocumentsJson, jsonStr)
              : _parseDocumentsJson(jsonStr);
          _cacheValid = true;
          // Best-effort repair of the primary metadata file.
          try {
            await backup.copy(file.path);
          } catch (_) {}
          return List.unmodifiable(_cachedDocuments!);
        }
      } catch (_) {}
      _cacheValid = false;
      rethrow;
    }
  }

  /// Ambil satu "halaman" dari daftar dokumen yang sudah di-load (lewat
  /// [loadDocuments], yang meng-cache hasilnya) — untuk pagination di UI
  /// (lihat home_screen.dart), supaya widget list awal hanya perlu
  /// membangun & mendekode thumbnail untuk [limit] dokumen pertama, bukan
  /// seluruh koleksi sekaligus.
  ///
  /// Catatan: ini bukan pagination di level I/O (documents_meta.json tetap
  /// dibaca & di-parse utuh sekali oleh loadDocuments() di atas — format
  /// JSON array tunggal tidak mendukung baca sebagian tanpa parser
  /// streaming khusus yang tidak dipakai proyek ini). Manfaatnya di sisi
  /// UI: windowing jumlah item yang dirender/di-build, bukan mengurangi
  /// I/O/parse metadata.
  Future<List<ScannedDocument>> loadDocumentsPage({
    required int offset,
    required int limit,
  }) async {
    final all = await loadDocuments();
    if (offset >= all.length) return const [];
    final end = (offset + limit).clamp(0, all.length);
    return all.sublist(offset, end);
  }

  /// Tulis [jsonStr] ke [_metaFile] secara ATOMIC: tulis dulu ke file
  /// sementara di direktori yang SAMA (supaya rename di bawah adalah
  /// operasi rename dalam satu filesystem, bukan copy lintas volume),
  /// baru [File.rename] menggantikan file asli.
  ///
  /// FIX (P0 — Metadata JSON tidak atomic): sebelumnya _deferredSaveDocuments()
  /// & _saveLocked() langsung `file.writeAsString(jsonStr)` ke
  /// documents_meta.json yang sudah ada. writeAsString() BUKAN operasi
  /// atomic — di level OS ini truncate-lalu-tulis byte demi byte. Kalau
  /// proses ke-kill (force-stop, OOM killer, crash, device mati) TEPAT di
  /// tengah penulisan itu, file berakhir sebagai JSON terpotong/corrupt
  /// (mis. array yang belum ditutup). loadDocuments() men-catch SEMUA
  /// error parse dan diam-diam fallback ke `[]` (lihat catch block di
  /// bawah) — jadi bukan cuma update terakhir yang hilang, TAPI SELURUH
  /// daftar dokumen "hilang" dari sisi user, padahal folder gambarnya
  /// masih utuh di disk (cuma metadata yang menunjuk ke sana yang rusak).
  /// Fix: pola write-to-temp-then-rename. File sementara ditulis penuh
  /// dulu (kalau proses mati di sini, file ASLI documents_meta.json sama
  /// sekali tidak tersentuh — masih versi lama yang utuh). Baru setelah
  /// tulis selesai, [File.rename] menggantikan file lama — rename di
  /// filesystem yang sama dijamin atomic oleh OS (POSIX rename(2) /
  /// Windows MoveFileEx), tidak ada state "setengah tertulis" yang bisa
  /// terlihat oleh pembaca berikutnya.
  Future<void> _writeMetaAtomic(String jsonStr) async {
    final file = await _metaFilePath;
    final tmpFile = File('${file.path}.tmp');
    final backupFile = File('${file.path}.bak');

    // Write the new document completely before touching the live metadata.
    await tmpFile.writeAsString(jsonStr, flush: true);

    // Keep a last-known-good copy for recovery if a future write is interrupted
    // or the live file becomes unreadable. This copy is made only after the
    // new temp file is complete, so it can never replace the primary with a
    // partially-written payload.
    if (await file.exists()) {
      try {
        await file.copy(backupFile.path);
      } catch (_) {
        // Backup is best-effort; the atomic primary write remains mandatory.
      }
    }

    try {
      await tmpFile.rename(file.path);
    } catch (_) {
      // Some platforms/filesystems reject rename-over-existing. Remove the
      // target only after the temp file is fully written, then retry.
      if (await file.exists()) {
        await file.delete();
      }
      await tmpFile.rename(file.path);
    }
  }

  /// Save document list to disk with debouncing to batch writes
  Future<void> _deferredSaveDocuments() async {
    // Cancel previous timer and replace it with one representing the latest
    // cache state. Keep a separate pending flag because Timer.isActive becomes
    // false as soon as its callback starts, even if that callback is still
    // waiting for the mutation lock.
    _writeTimer?.cancel();
    _writePending = true;

    _writeTimer = Timer(_writeDelay, () async {
      try {
        await _withMutationLock<void>(() async {
          if (_cachedDocuments == null) return;
          final jsonStr = json.encode(
            _cachedDocuments!.map((d) => d.toJson()).toList(),
          );
          await _writeMetaAtomic(jsonStr);
        });
      } catch (_) {
        // Deferred writes are best-effort; critical callers use immediate save.
      } finally {
        _writePending = false;
      }
    });
  }

  /// Immediate save without debouncing (for critical operations)
  Future<void> _saveLocked() async {
    if (_cachedDocuments == null) return;
    _writeTimer?.cancel();
    try {
      final jsonStr = json.encode(
        _cachedDocuments!.map((d) => d.toJson()).toList(),
      );
      await _writeMetaAtomic(jsonStr);
    } catch (e) {
      throw Exception('Failed to save documents: $e');
    }
  }

  /// Add a new document (commit dokumen hasil scan).
  Future<void> addDocument(ScannedDocument document) async {
    await _withMutationLock<void>(() async {
      // Load from cache if valid, otherwise from disk
      final docs = await loadDocuments();

    // Modify in-memory cache
    _cachedDocuments = [document, ...docs];
    _cacheValid = true;

    // FIX: sebelumnya commit dokumen baru pakai _deferredSaveDocuments()
    // (debounce 500ms) — cocok untuk update ringan yang sering terjadi
    // berturut-turut, tapi BERBAHAYA untuk commit dokumen: gambar sudah
    // ter-copy ke folder permanen (lihat saveImages di ScanController)
    // sebelum addDocument() ini dipanggil, tapi kalau app di-kill atau
    // dibackground tepat setelah "Simpan" ditekan — sebelum timer 500ms
    // sempat jalan — metadata dokumen ini TIDAK PERNAH tertulis ke
    // documents_meta.json. Hasilnya: file gambar nyangkut di disk tapi
    // dokumennya tidak pernah muncul di daftar ("hilang" dari sisi user).
    // Commit dokumen adalah operasi kritis satu-kali (bukan burst update
    // berulang), jadi ditulis langsung/synchronous, bukan di-defer.
      await _saveLocked();
    });
  }

  /// Update an existing document.
  ///
  /// FIX (P1 — updateDocument() critical masih deferred): sebelumnya SELALU
  /// lewat _deferredSaveDocuments() (debounce 500ms) apa pun isi update-nya.
  /// Cocok untuk perubahan ringan yang sering beruntun, tapi berbahaya untuk
  /// update yang merepresentasikan hasil kerja MAHAL & tidak-gratis-diulang
  /// (mis. pdfPath baru setelah PdfService.generatePdf() selesai generate —
  /// lihat BulkShareService.shareAsPdf() & DocumentDetailScreen._exportAsPdf()).
  /// Kalau app di-kill di jendela 500ms itu, update hilang dari
  /// documents_meta.json — bukan data hilang permanen (dokumen intinya masih
  /// ada), tapi kerja mahal itu (generate PDF, dsb.) akan diulang lagi dari
  /// nol di percobaan berikutnya karena state pdfPath-nya tidak pernah
  /// tercatat.
  /// Fix: parameter [immediate] — saat true, tulis langsung/synchronous
  /// (sama seperti addDocument()) alih-alih di-debounce. Caller yang
  /// melakukan update kritis (hasil kerja mahal, atau titik akhir sebuah
  /// alur seperti export PDF) wajib pakai immediate: true; update ringan/
  /// beruntun (mis. upsertDocuments batch) tetap boleh pakai default
  /// (debounced) untuk menghindari I/O berlebihan.
  Future<void> updateDocument(
    ScannedDocument document, {
    bool immediate = false,
  }) async {
    return _withMutationLock<void>(() async {
      final docs = await loadDocuments();
    final idx = docs.indexWhere((d) => d.id == document.id);
    if (idx == -1) return;

    // Modify cache in-place
    _cachedDocuments![idx] = document;
    _cacheValid = true;

      if (immediate) {
        await _saveLocked();
      } else {
        await _deferredSaveDocuments();
      }
    });
  }

  /// Add or update batch of documents
  /// More efficient than calling addDocument/updateDocument multiple times
  Future<void> upsertDocuments(List<ScannedDocument> documents) async {
    await _withMutationLock<void>(() async {
      final docs = await loadDocuments();

    for (final doc in documents) {
      final idx = docs.indexWhere((d) => d.id == doc.id);
      if (idx != -1) {
        _cachedDocuments![idx] = doc;
      } else {
        _cachedDocuments!.insert(0, doc);
      }
    }

    _cacheValid = true;
      await _deferredSaveDocuments();
    });
  }

  /// Delete a document and its files
  Future<void> deleteDocument(String documentId) async {
    await _withMutationLock<void>(() async {
      final docs = await loadDocuments();

    // Cari dokumen; jika tidak ada, langsung return (idempotent delete)
    final docIndex = docs.indexWhere((d) => d.id == documentId);
    if (docIndex == -1) return;

    final doc = docs[docIndex];

    // Delete image files in background (non-blocking)
    _deleteFilesInBackground(doc.imagePaths);

    // Delete PDF if exists
    if (doc.pdfPath != null) {
      _deleteFileInBackground(doc.pdfPath!);
    }

    // FIX (perf #1): thumbnailPath sekarang file terpisah hasil
    // ImageEnhanceService.generateThumbnail() (lihat saveImages di bawah),
    // bukan lagi salah satu dari imagePaths — jadi harus dihapus eksplisit
    // di sini juga, kalau tidak akan jadi sampah menumpuk di folder
    // DocScan/Thumbnails setiap dokumen dihapus.
    if (doc.thumbnailPath != null &&
        !doc.imagePaths.contains(doc.thumbnailPath)) {
      _deleteFileInBackground(doc.thumbnailPath!);
    }

    // Update cache and save immediately
    _cachedDocuments!.removeAt(docIndex);
    _cacheValid = true;
      await _saveLocked();
    });
  }

  /// Delete multiple documents (batch operation)
  Future<void> deleteDocuments(List<String> documentIds) async {
    await _withMutationLock<void>(() async {
      final docs = await loadDocuments();

    final toDelete = <ScannedDocument>[];
    for (final id in documentIds) {
      final doc = docs.firstWhere((d) => d.id == id,
          orElse: () => ScannedDocument.empty());
      if (doc.id.isNotEmpty) {
        toDelete.add(doc);
      }
    }

    // Delete all files in background
    for (final doc in toDelete) {
      _deleteFilesInBackground(doc.imagePaths);
      if (doc.pdfPath != null) _deleteFileInBackground(doc.pdfPath!);
      // FIX (perf #1): sama seperti deleteDocument — thumbnail terpisah
      // harus ikut dibersihkan.
      if (doc.thumbnailPath != null &&
          !doc.imagePaths.contains(doc.thumbnailPath)) {
        _deleteFileInBackground(doc.thumbnailPath!);
      }
    }

    // Update cache
    for (final doc in toDelete) {
      _cachedDocuments!.removeWhere((d) => d.id == doc.id);
    }

    _cacheValid = true;
      await _saveLocked();
    });
  }

  /// Copy scanned images ke permanent storage (tanpa processing)
  Future<({List<String> imagePaths, String? thumbnailPath})> saveImages(
    String documentId,
    List<String> tempPaths,
  ) async {
    // FIX: tolak lebih awal jika tidak ada gambar
    if (tempPaths.isEmpty) {
      throw Exception('Tidak ada gambar untuk disimpan.');
    }

    final dir = await _docsDir;
    final docDir = Directory('${dir.path}/$documentId');
    await docDir.create(recursive: true);

    final List<String> savedPaths = [];

    // PERF (thumbnail sebelum permanent save, bukan sesudah): versi
    // sebelumnya generate thumbnail SETELAH seluruh loop copy halaman di
    // bawah selesai (menunggu semua halaman ter-copy dulu, baru mulai
    // generate thumbnail dari path PERMANEN halaman pertama) — jadi
    // caller (ScanController.saveDocument()) menunggu dua tahap yang
    // sebetulnya independen secara BERURUTAN: copy semua halaman, BARU
    // generate thumbnail. Halaman pertama (tempPaths.first) sudah ada &
    // siap dibaca sejak awal, tidak perlu menunggu halaman² lain selesai
    // di-copy dulu. Fix: mulai generate thumbnail dari file TEMP halaman
    // pertama serentak (Future, belum di-await) dengan loop copy di bawah,
    // supaya kerja isolate thumbnail (resize+encode) tumpang tindih dengan
    // I/O copy halaman lain alih-alih menunggu di belakangnya — total
    // waktu saveImages() mendekati max(waktu-copy, waktu-thumbnail),
    // bukan jumlah keduanya. Formatnya tetap JPEG kecil pre-resized
    // (200x200 q75, lihat ImageEnhanceService.generateThumbnail) — WebP
    // tidak dipakai karena versi package:image di proyek ini tidak
    // punya encoder WebP yang terverifikasi, dan JPEG kecil sudah "fast
    // loading" untuk kebutuhan thumbnail 200x200 ini.
    final thumbnailFuture = tempPaths.isNotEmpty
        ? ImageEnhanceService()
            .generateThumbnail(tempPaths.first.trim())
            .then<String?>((p) => p)
            .catchError((_) => null)
        : Future<String?>.value(null);

    // FIX (dokumen parsial): versi sebelumnya `continue` saat satu halaman
    // gagal (path kosong, file hilang, atau copy gagal) dan cuma throw kalau
    // SEMUA halaman gagal — artinya sebagian halaman yang gagal di-copy bisa
    // hilang tanpa pemberitahuan apapun ke user; dokumen tetap "berhasil"
    // tersimpan tapi dengan halaman lebih sedikit dari yang di-scan. Sekarang
    // all-or-nothing: begitu SATU halaman gagal, langsung throw. Caller
    // (ScanController.saveDocument()) sudah punya rollback penuh untuk kasus
    // saveImages() throw (discardUnsavedDocument() di catch block, menghapus
    // docDir termasuk halaman yang sempat ter-copy sebelum kegagalan ini) —
    // jadi hasilnya bersih: dokumen tidak pernah tercatat dengan halaman
    // bolong, dan user melihat error yang jelas alih-alih dokumen parsial
    // yang terlihat baik-baik saja.
    try {
      for (int i = 0; i < tempPaths.length; i++) {
        final rawPath = tempPaths[i].trim();
        if (rawPath.isEmpty) {
          throw Exception('Halaman ${i + 1} tidak valid (path kosong).');
        }

        final tempFile = File(rawPath);
        if (!await tempFile.exists()) {
          throw Exception('Halaman ${i + 1} tidak ditemukan di penyimpanan sementara.');
        }

        // BUG FIX (share: "file yang dikirim bukan foto"): sebelumnya
        // tempFile.copy(newPath) menyalin byte APA ADANYA lalu memberi
        // nama "page_N.jpg" tanpa pernah mengecek isi filenya benar JPEG
        // atau bukan — halaman dari "Tambah dari Galeri" yang aslinya
        // PNG/WEBP/HEIC ikut disalin mentah tapi diberi label ".jpg" +
        // mimeType 'image/jpeg' di semua titik share. Aplikasi tujuan
        // yang memvalidasi magic bytes aktual (bukan cuma percaya nama
        // file) sering menampilkan ini sebagai dokumen/file generik,
        // bukan foto. Lihat catatan lengkap di
        // ImageEnhanceService.ensureJpeg()/_processEnsureJpeg().
        // Fix: normalisasi ke JPEG asli SEBELUM disalin ke penyimpanan
        // permanen — sekali di sini, semua share berikutnya dari
        // dokumen ini (BulkShareService, DocumentDetailScreen) otomatis
        // aman tanpa perlu tahu format sumbernya. Untuk halaman yang
        // memang sudah JPEG asli (mayoritas — hasil scan kamera),
        // ensureJpeg() adalah fast path (cek 3 byte, tanpa decode),
        // jadi tidak ada biaya tambahan berarti untuk kasus normal.
        final normalizedPath = await ImageEnhanceService().ensureJpeg(rawPath);

        final newPath = '${docDir.path}/page_${i + 1}.jpg';
        try {
          await File(normalizedPath).copy(newPath);
        } catch (e) {
          // Storage penuh / permission I/O — gagalkan seluruh penyimpanan,
          // jangan lewati halaman ini.
          throw Exception('Gagal menyalin halaman ${i + 1}: $e');
        } finally {
          // File hasil normalisasi cuma perantara (beda dari rawPath asli
          // yang milik caller/scanner plugin) — bersihkan supaya tidak
          // jadi sampah temp, kecuali memang tidak ada file baru yang
          // dibuat (normalizedPath == rawPath, sudah JPEG dari awal).
          if (normalizedPath != rawPath) {
            _deleteFileInBackground(normalizedPath);
          }
        }
        savedPaths.add(newPath);
        // Penomoran sekarang selalu 1:1 dengan tempPaths (i + 1), tidak ada
        // lagi celah karena tidak ada lagi halaman yang di-skip diam-diam.
      }
    } catch (_) {
      // Loop copy gagal di tengah jalan — thumbnailFuture yang sudah
      // dimulai paralel di atas mungkin masih berjalan atau sudah selesai
      // menghasilkan file. Karena saveImages() akan throw (caller tidak
      // pernah menerima thumbnailPath ini untuk dibersihkan lewat
      // discardUnsavedDocument()), file itu harus dibersihkan di sini juga
      // supaya tidak jadi sampah tak tercatat.
      final orphanThumb = await thumbnailFuture;
      if (orphanThumb != null) {
        _deleteFileInBackground(orphanThumb);
      }
      rethrow;
    }

    // Tunggu hasil thumbnail yang sudah mulai diproses paralel di atas.
    // Kalau generate dari file temp gagal (mis. file corrupt) ATAU
    // tempPaths kosong tapi savedPaths ada isinya, fallback ke path
    // PERMANEN halaman pertama yang barusan selesai di-copy — sama
    // seperti perilaku lama, sekadar jaring pengaman terakhir.
    // Do not fall back to a full-resolution page as thumbnail. A missing
    // thumbnail is preferable to reintroducing large image decodes into the
    // document list. DocumentCard already has a safe resized-image fallback
    // for legacy documents.
    final thumbnailPath = await thumbnailFuture;

    return (imagePaths: savedPaths, thumbnailPath: thumbnailPath);
  }

  /// Buang folder permanen milik [documentId] yang SUDAH di-copy oleh
  /// [saveImages] tapi GAGAL di-commit ke daftar dokumen (addDocument()
  /// tidak pernah/tidak boleh dipanggil untuk id ini).
  ///
  /// FIX (P0 — Partial Gallery save → orphan document files): sebelumnya
  /// ScanController.saveDocument() memanggil saveImages() (copy byte ke
  /// folder permanen Documents/{id}/, lihat di atas) SEBELUM loop
  /// SaverGallery.saveFile(). Kalau loop itu gagal di tengah jalan (mis.
  /// storage penuh, permission dicabut saat runtime), controller langsung
  /// masuk catch dan return false — addDocument() tidak pernah tercapai,
  /// tapi folder Documents/{id}/ (dan thumbnail terpisah di
  /// DocScan/Thumbnails/ hasil generateThumbnail()) sudah telanjur ada di
  /// disk, tidak tercatat di documents_meta.json manapun, dan tidak akan
  /// pernah dibersihkan oleh alur cleanup manapun (beda dari file temp
  /// sesi yang ditangani ScannerService.cleanupFiles()) — jadi sampah
  /// permanen yang menumpuk tiap kali user coba simpan & gagal di tengah.
  /// Dipanggil oleh caller (ScanController.saveDocument()) di catch block
  /// SEBELUM addDocument() berhasil dipanggil, supaya kegagalan partial
  /// tidak meninggalkan jejak di disk sama sekali — state balik seperti
  /// document ini tidak pernah dicoba disimpan.
  Future<void> discardUnsavedDocument(
    String documentId, {
    String? thumbnailPath,
  }) async {
    try {
      final dir = await _docsDir;
      final docDir = Directory('${dir.path}/$documentId');
      if (await docDir.exists()) {
        await docDir.delete(recursive: true);
      }
    } catch (_) {
      // Terbaik-upaya — kalau gagal hapus, tidak ada yang bisa dilakukan
      // lebih lanjut di sini; tidak boleh melempar dan menutupi error asli
      // yang memicu rollback ini.
    }

    // Thumbnail generateThumbnail() disimpan TERPISAH di
    // DocScan/Thumbnails/, bukan di dalam Documents/{id}/ — jadi tidak ikut
    // terhapus oleh docDir.delete(recursive:true) di atas dan harus
    // dibersihkan eksplisit.
    if (thumbnailPath != null) {
      _deleteFileInBackground(thumbnailPath);
    }
  }

  /// Generate unique document ID
  String generateId() {
    return 'doc_${DateTime.now().millisecondsSinceEpoch}';
  }

  // BUG FIX (migrasi data lama — share: "file yang dikirim bukan foto"):
  // saveImages() SEKARANG sudah menormalisasi tiap halaman ke JPEG asli
  // sebelum disimpan (lihat catatan di sana), tapi itu cuma berlaku
  // untuk dokumen yang disimpan SETELAH fix itu ada. Dokumen yang sudah
  // lebih dulu tersimpan di HP user (dari "Tambah dari Galeri" sebelum
  // fix) masih punya file fisik "page_N.jpg" yang isinya sebenarnya
  // PNG/WEBP/HEIC — titik share sudah dilindungi jaring pengaman
  // ensureJpeg() (BulkShareService, ScanController, DocumentDetailScreen)
  // yang menormalisasi ON-THE-FLY tiap kali share terjadi, TAPI itu
  // berarti konversi decode+encode yang sama terulang tiap kali dokumen
  // yang sama di-share lagi — kerja yang sama dikerjakan berkali-kali
  // padahal hasilnya selalu sama.
  //
  // migrateNormalizeImageFormats() membenahi ini SEKALI SAJA secara
  // permanen: menimpa isi file yang bukan JPEG asli langsung di path
  // penyimpanan permanennya (lewat ImageEnhanceService.ensureJpegInPlace
  // — path TIDAK berubah, jadi documents_meta.json tidak perlu ditulis
  // ulang sama sekali). Setelah migrasi sekali jalan, jaring pengaman
  // ensureJpeg() di titik share jadi selalu fast-path (cek 3 byte, tanpa
  // decode) untuk SEMUA dokumen, lama maupun baru.
  //
  // Ditandai lewat file flag kosong di folder dokumen (bukan
  // SharedPreferences — proyek ini belum punya dependency itu, dan pola
  // "flag file di documents dir" sudah konsisten dengan cara app ini
  // menyimpan state lain) supaya HANYA jalan sekali seumur hidup app,
  // bukan di-scan ulang tiap startup untuk koleksi dokumen yang sudah
  // besar. Dipanggil fire-and-forget dari main() (sama pola dengan
  // ScannerService.purgeStaleTempFiles()) — best-effort, tidak pernah
  // melempar ke caller, dan kegagalan per-halaman tidak menghentikan
  // migrasi halaman/dokumen lain.
  static const String _migrationFlagFile = '.jpeg_migration_v1_done';

  Future<void> migrateNormalizeImageFormats() async {
    try {
      final dir = await _docsDir;
      final flag = File('${dir.path}/$_migrationFlagFile');
      if (await flag.exists()) return; // sudah pernah jalan, skip

      final docs = await loadDocuments();
      final enhanceService = ImageEnhanceService();
      for (final doc in docs) {
        for (final path in doc.imagePaths) {
          try {
            await enhanceService.ensureJpegInPlace(path);
          } catch (_) {
            // Satu halaman gagal dinormalisasi (mis. file sudah hilang,
            // format tidak dikenali sama sekali) — lewati, jangan
            // gagalkan migrasi dokumen/halaman lain. Halaman ini tetap
            // akan dicoba lagi lewat jaring pengaman ensureJpeg() di
            // titik share kalau suatu saat di-share.
          }
        }
      }

      // Tulis flag PALING TERAKHIR, setelah semua dokumen selesai
      // diproses — supaya kalau app di-kill di tengah migrasi, migrasi
      // otomatis diulang dari awal di startup berikutnya alih-alih
      // dianggap "selesai" padahal cuma sebagian jalan. ensureJpegInPlace
      // sendiri sudah aman diulang (no-op untuk halaman yang sudah benar
      // JPEG dari percobaan migrasi sebelumnya).
      await flag.create(recursive: true);
    } catch (_) {
      // getApplicationDocumentsDirectory()/listing gagal total — sama
      // seperti purgeStaleTempFiles(), best-effort, jangan sampai
      // mengganggu apa pun di app.
    }
  }

  /// Clear cache (useful when external changes might occur).
  ///
  /// BUG (updateDocument() + invalidateCache() bisa kehilangan pdfPath):
  /// updateDocument() menulis lewat _deferredSaveDocuments() (debounce
  /// 500ms), TIDAK langsung. Kalau invalidateCache() dipanggil sebelum
  /// timer itu sempat jalan — persis skenario BulkShareService.shareAsPdf()
  /// yang updateDocument() beberapa dokumen di dalam loop lalu langsung
  /// invalidateCache() begitu loop selesai — _writeTimer?.cancel() di sini
  /// MEMBATALKAN tulisan yang masih pending. Update pdfPath yang baru saja
  /// di-generate hilang begitu saja, tidak pernah tertulis ke
  /// documents_meta.json. Ditambah _cacheValid=false, loadDocuments()
  /// berikutnya baca ulang dari disk yang masih basi, jadi update di
  /// memory pun ikut hilang — dokumen kelihatan seperti belum pernah
  /// di-generate PDF-nya padahal filenya sudah ada di disk (jadi sampah
  /// tak tercatat, dan PDF akan digenerate ulang di percobaan berikutnya).
  /// Fix: kalau ada write yang masih pending, flush dulu (tulis langsung)
  /// sebelum invalidate — bukan dibuang begitu saja.
  Future<void> invalidateCache() async {
    await _withMutationLock<void>(() async {
      if (_writePending) {
        _writeTimer?.cancel();
        _writePending = false;
        await _saveLocked();
      }
      _cacheValid = false;
    });
  }

  // ── Helper methods for background file deletion ──

  void _deleteFileInBackground(String path) {
    File(path).delete().catchError((Object _) {
      return File(path); // required: catchError must return FileSystemEntity
    });
  }

  void _deleteFilesInBackground(List<String> paths) {
    for (final path in paths) {
      _deleteFileInBackground(path);
    }
  }

  @override
  String toString() => 'DocumentStorageService(cached: $_cacheValid)';
}
