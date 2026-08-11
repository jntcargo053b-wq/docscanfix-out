import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import '../models/scanned_document.dart';
import 'image_enhance_service.dart';

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
  static const Duration _writeDelay = Duration(milliseconds: 500);

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
      final List<dynamic> jsonList = json.decode(jsonStr);
      _cachedDocuments =
          jsonList.map((j) => ScannedDocument.fromJson(j)).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _cacheValid = true;
      return List.unmodifiable(_cachedDocuments!);
    } catch (e) {
      _cachedDocuments = [];
      _cacheValid = true;
      return [];
    }
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
    await tmpFile.writeAsString(jsonStr, flush: true);
    await tmpFile.rename(file.path);
  }

  /// Save document list to disk with debouncing to batch writes
  Future<void> _deferredSaveDocuments() async {
    // Cancel previous timer
    _writeTimer?.cancel();

    // Schedule write after delay to batch rapid updates
    _writeTimer = Timer(_writeDelay, () async {
      if (_cachedDocuments == null) return;
      try {
        final jsonStr = json.encode(
          _cachedDocuments!.map((d) => d.toJson()).toList(),
        );
        await _writeMetaAtomic(jsonStr);
      } catch (e) {
        // Silently fail deferred writes; caller should handle critical saves
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
  }

  /// Add or update batch of documents
  /// More efficient than calling addDocument/updateDocument multiple times
  Future<void> upsertDocuments(List<ScannedDocument> documents) async {
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
  }

  /// Delete a document and its files
  Future<void> deleteDocument(String documentId) async {
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
  }

  /// Delete multiple documents (batch operation)
  Future<void> deleteDocuments(List<String> documentIds) async {
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
    String? thumbnailPath;

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
    for (int i = 0; i < tempPaths.length; i++) {
      final rawPath = tempPaths[i].trim();
      if (rawPath.isEmpty) {
        throw Exception('Halaman ${i + 1} tidak valid (path kosong).');
      }

      final tempFile = File(rawPath);
      if (!await tempFile.exists()) {
        throw Exception('Halaman ${i + 1} tidak ditemukan di penyimpanan sementara.');
      }

      final newPath = '${docDir.path}/page_${i + 1}.jpg';
      try {
        await tempFile.copy(newPath);
      } catch (e) {
        // Storage penuh / permission I/O — gagalkan seluruh penyimpanan,
        // jangan lewati halaman ini.
        throw Exception('Gagal menyalin halaman ${i + 1}: $e');
      }
      savedPaths.add(newPath);

      // Penomoran sekarang selalu 1:1 dengan tempPaths (i + 1), tidak ada
      // lagi celah karena tidak ada lagi halaman yang di-skip diam-diam.
      thumbnailPath ??= newPath;
    }

    // FIX (perf #1): sebelumnya thumbnailPath cuma menunjuk ke halaman
    // pertama versi FULL-RES (page_1.jpg, bisa 12–48 MP hasil kamera —
    // lihat komentar di ImageEnhanceService). DocumentCard men-decode file
    // ini penuh setiap render row cuma untuk ditampilkan di kotak 60x60,
    // yang berat di CPU/memori tiap scroll daftar dokumen.
    // ImageEnhanceService.generateThumbnail() (resize 200x200, quality 75)
    // sudah ada dari sesi sebelumnya tapi tidak pernah dipanggil — sekarang
    // benar-benar dipakai di sini, supaya thumbnailPath menunjuk ke file
    // KECIL yang memang didesain untuk thumbnail, bukan halaman asli.
    // Kalau generate gagal (mis. file corrupt), fallback ke halaman pertama
    // seperti perilaku lama — jangan sampai gagal generate thumbnail
    // menggagalkan penyimpanan dokumen.
    if (thumbnailPath != null) {
      try {
        thumbnailPath = await ImageEnhanceService().generateThumbnail(thumbnailPath);
      } catch (_) {
        // biarkan thumbnailPath tetap menunjuk ke halaman pertama full-res
      }
    }

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
    if (_writeTimer?.isActive ?? false) {
      _writeTimer!.cancel();
      await _saveLocked();
    }
    _cacheValid = false;
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
