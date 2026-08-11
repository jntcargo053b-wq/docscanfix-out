import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/scanner_service.dart';
import '../../services/ocr_service.dart';
import '../../services/pdf_service.dart';
import '../../services/document_storage_service.dart';
import '../../services/image_enhance_service.dart';
import '../../models/scanned_document.dart';

enum ScanStatus { idle, scanning, ready, processing, done, error }

class ScanController extends ChangeNotifier {
  // ─── Dependencies ────────────────────────────────────────────────────────
  final ScannerService _scannerService;
  final OcrService _ocrService;
  final PdfService _pdfService;
  final DocumentStorageService _storageService;
  final ImageEnhanceService _enhanceService;

  ScanController({
    ScannerService? scannerService,
    OcrService? ocrService,
    PdfService? pdfService,
    DocumentStorageService? storageService,
    ImageEnhanceService? enhanceService,
  })  : _scannerService = scannerService ?? ScannerService(),
        _ocrService = ocrService ?? OcrService(),
        _pdfService = pdfService ?? PdfService(),
        _storageService = storageService ?? DocumentStorageService(),
        _enhanceService = enhanceService ?? ImageEnhanceService();

  // ─── State ──────────────────────────────────────────────────────────
  // BUG (ScanController share lifecycle): shareImages() (dan method async
  // lain di controller ini) memanggil notifyListeners()/_setStatus() lagi
  // di blok finally SETELAH await — termasuk await Share.shareXFiles(),
  // yang bisa menggantung lama kalau share sheet OS masih terbuka
  // menunggu user memilih aplikasi tujuan. Kalau ScanScreen ditutup
  // (Navigator.pop) selagi await itu masih berjalan, _ScanScreenState.
  // dispose() memanggil controller.dispose() — dan begitu await akhirnya
  // selesai, finally block masih mencoba notifyListeners() pada
  // ChangeNotifier yang SUDAH di-dispose → melempar exception
  // ("A ChangeNotifier was used after being disposed"). Sama berlaku
  // untuk saveDocument()/_runOcr()/startScan() yang juga notifyListeners()
  // setelah await. Fix: flag _disposed, dicek di titik notifyListeners()
  // agar tidak dipanggil lagi setelah dispose().
  bool _disposed = false;
  ScanStatus _status = ScanStatus.idle;
  List<String> _imagePaths = [];
  String? _extractedText;
  bool _isOcrRunning = false;
  // Token generasi untuk _runOcr() — lihat komentar di _runOcr().
  int _ocrRunId = 0;
  // FIX (P0 — Save tidak menunggu OCR selesai): pegangan ke run OCR yang
  // sedang berjalan, supaya saveDocument() punya sesuatu yang bisa
  // di-await. Lihat komentar lengkap di _runOcr() dan saveDocument().
  Future<void>? _ocrFuture;
  String _processingStatus = '';
  String? _errorMessage;

  // ── Cache for prepared images to avoid reprocessing ──
  final Map<String, String> _preparedForOcrCache = {};
  final Map<String, String> _preparedForPdfCache = {};

  // ── LIFECYCLE CLEANUP: semua file sementara yang dibuat sepanjang sesi
  // scan ini (halaman mentah dari scanner, hasil edit dari Image Editor,
  // versi prepared untuk OCR/PDF) — bukan cuma yang sedang dipakai di
  // _imagePaths. File yang dibuang lewat removeImage()/replaceImage(),
  // atau yang jadi halaman terduplikasi hasil dedupe, tetap tercatat di
  // sini supaya ikut dibersihkan saat sesi berakhir (lihat dispose()).
  // Aman dibersihkan kapan pun sesi berakhir (baik batal maupun sudah
  // disimpan) karena saveDocument() men-COPY byte ke folder permanen
  // (DocumentStorageService.saveImages), bukan memindahkan/mereferensi
  // file temp ini.
  final Set<String> _sessionTempFiles = {};

  late final TextEditingController titleController = TextEditingController(
    text: _defaultTitle(),
  );

  // ─── Getters ─────────────────────────────────────────────────────────
  ScanStatus get status => _status;
  List<String> get imagePaths => List.unmodifiable(_imagePaths);
  String? get extractedText => _extractedText;
  bool get isOcrRunning => _isOcrRunning;
  bool get isScanning => _status == ScanStatus.scanning;
  bool get isProcessing => _status == ScanStatus.processing;
  bool get hasImages => _imagePaths.isNotEmpty;
  String get processingStatus => _processingStatus;
  String? get errorMessage => _errorMessage;

  // ─── Public Actions ───────────────────────────────────────────────────────

  Future<void> startScan(BuildContext context) async {
    // FIX (P1 — Tambah halaman bisa dipanggil bersamaan): sebelumnya
    // tidak ada guard re-entry di sini. UI (ScanScreen._buildBody())
    // memang menyembunyikan tombol "Tambah Halaman" begitu isScanning
    // true, tapi itu baru berlaku SETELAH rebuild berikutnya — kalau user
    // tap dua kali sangat cepat (double-tap) sebelum frame rebuild itu
    // sempat terjadi, _handleAddMore() di ScanScreen bisa terpanggil dua
    // kali sebelum status berubah, dan keduanya sama-sama memanggil
    // startScan(). Dua pemanggilan _scannerService.scanDocument(context)
    // yang berjalan BERSAMAAN membuka dua sesi CunningDocumentScanner
    // (activity native) di atas satu sama lain, yang bisa bentrok
    // (crash, state UI native yang tidak konsisten, atau salah satu
    // panggilan gagal dengan error tidak jelas ke user).
    // Fix: guard di level controller (bukan cuma UI) — cek status di
    // awal, bukan cuma andalkan timing rebuild widget. Ini pertahanan
    // yang lebih andal karena tidak bergantung pada seberapa cepat
    // Flutter merender ulang setelah notifyListeners().
    if (_status == ScanStatus.scanning || _status == ScanStatus.processing) {
      return;
    }
    _setStatus(ScanStatus.scanning);
    _errorMessage = null;

    // FIX duplicate detection (tombol "Tambah Halaman"): hash halaman yang
    // SUDAH ADA harus diambil SEBELUM sesi scan baru dipicu, bukan sesudah.
    // cunning_document_scanner menyimpan hasil capture ke file temp yang
    // penamaannya bisa dipakai ulang antar sesi (mis. path lama ikut
    // ditimpa saat sesi baru berjalan) — kalau existingHashes dihitung
    // SETELAH `scanDocument()` selesai, isi file di path lama itu bisa
    // saja sudah keburu berubah jadi konten scan yang BARU, sehingga
    // deteksi duplikat membandingkan halaman baru dengan dirinya sendiri
    // (bukan dengan halaman lama yang sebenarnya) — hasilnya jadi tidak
    // bisa diandalkan: duplikat asli lolos, atau halaman lama yang masih
    // valid salah dianggap identik. Snapshot dulu di sini, sebelum apa
    // pun di disk sempat berubah.
    final existingHashes = await _hashAll(_imagePaths);

    try {
      final images = await _scannerService.scanDocument(context);

      if (images == null || images.isEmpty) {
        _setStatus(_imagePaths.isEmpty ? ScanStatus.idle : ScanStatus.ready);
        return;
      }

      // Semua path mentah hasil sesi scan ini dicatat untuk cleanup lifecycle
      // nanti (lihat dispose()) — termasuk yang bakal disaring sebagai
      // duplikat di bawah, karena file fisiknya tetap ada di temp dir.
      _sessionTempFiles.addAll(images);

      // FIX: sebelumnya `_imagePaths = images` MENIMPA seluruh halaman yang
      // sudah ada — akibatnya tombol "Tambah Halaman" bukannya menambah,
      // malah membuang semua halaman sebelumnya. Sekarang halaman baru
      // digabung ke halaman lama, sambil tetap disaring dari duplikat
      // terhadap snapshot hash yang diambil sebelum scan dimulai.
      final newImages = await _dedupeAgainstHashes(images, existingHashes);
      _imagePaths = [..._imagePaths, ...newImages];
      _setStatus(ScanStatus.ready);
      _runOcr();
    } on ScannerException catch (e) {
      _errorMessage = e.toUserMessage();
      _setStatus(ScanStatus.error);
    } catch (e) {
      _errorMessage = 'Scan gagal. Coba lagi atau restart aplikasi.';
      _setStatus(ScanStatus.error);
    }
  }

  /// Hash konten sekumpulan file (dipakai untuk snapshot state "existing"
  /// sebelum operasi yang bisa mengubah isi file di path yang sama).
  Future<Set<String>> _hashAll(List<String> paths) async {
    final hashes = <String>{};
    for (final p in paths) {
      try {
        hashes.add(md5.convert(await File(p).readAsBytes()).toString());
      } catch (_) {}
    }
    return hashes;
  }

  /// Saring halaman baru yang isinya identik dengan [existingHashes] (state
  /// sebelum sesi scan ini dimulai) ATAU dengan sesama halaman baru dalam
  /// batch yang sama (mis. hasil "Tambah Halaman" kebetulan menangkap ulang
  /// halaman yang sama beberapa kali dalam satu sesi).
  Future<List<String>> _dedupeAgainstHashes(
    List<String> newPaths,
    Set<String> existingHashes,
  ) async {
    final seen = {...existingHashes};
    final result = <String>[];
    for (final p in newPaths) {
      try {
        final hash = md5.convert(await File(p).readAsBytes()).toString();
        if (seen.add(hash)) result.add(p);
      } catch (_) {
        result.add(p);
      }
    }
    return result;
  }

  /// Ganti halaman di [index] dengan hasil dari Image Editor ([newPath]).
  /// Dipanggil setelah user menekan "Simpan" di ImageEditorScreen untuk
  /// halaman terkait — menghubungkan Image Editor ke scan flow.
  void replaceImage(int index, String newPath) {
    if (index < 0 || index >= _imagePaths.length) return;
    if (newPath == _imagePaths[index]) return;

    final oldPath = _imagePaths[index];
    final updated = List<String>.from(_imagePaths);
    updated[index] = newPath;
    _imagePaths = updated;

    // Hasil edit adalah file temp baru → catat untuk cleanup lifecycle.
    _sessionTempFiles.add(newPath);

    // Konten halaman berubah: cache OCR/PDF untuk path lama sudah basi.
    _preparedForOcrCache.remove(oldPath);
    _preparedForPdfCache.remove(oldPath);

    notifyListeners();
    _runOcr();
  }

  void removeImage(int index) {
    if (index < 0 || index >= _imagePaths.length) return;
    final removedPath = _imagePaths[index];
    _imagePaths = List.from(_imagePaths)..removeAt(index);

    // BUG (invalidasi cache salah): logic lama ambil filename dari KEY
    // cache (originalPath, path LENGKAP) lewat File(k).path.split('/').last,
    // lalu cari filename itu di _imagePaths — padahal _imagePaths isinya
    // path LENGKAP juga, bukan filename. indexOf() jadi hampir SELALU
    // return -1 untuk SEMUA entri, sehingga originalIndex == -1 true untuk
    // semua → SELURUH cache OCR (bukan cuma punya halaman yang dihapus)
    // kehapus tiap kali satu halaman dihapus. Akibatnya _runOcr()
    // berikutnya harus prepare+OCR ULANG semua halaman yang sebenarnya
    // tidak berubah sama sekali — bukan cuma yang benar-benar perlu.
    // Cache di-key oleh path (bukan index), dan path halaman LAIN tidak
    // berubah saat satu halaman dihapus — jadi cukup buang entri milik
    // path yang benar-benar dihapus.
    _preparedForOcrCache.remove(removedPath);
    _preparedForPdfCache.remove(removedPath);

    notifyListeners();
    // FIX terkait: sebelumnya tidak ada _runOcr() di sini sama sekali,
    // jadi _extractedText tetap menampilkan teks lama yang bisa saja
    // berasal (sebagian) dari halaman yang baru dihapus. Refresh OCR
    // supaya hasilnya konsisten dengan halaman yang tersisa.
    _runOcr();
  }

  Future<bool> saveDocument() async {
    final title = titleController.text.trim();
    if (title.isEmpty) {
      _errorMessage = 'Masukkan judul dokumen';
      notifyListeners();
      return false;
    }

    if (_imagePaths.isEmpty) {
      _errorMessage = 'Tidak ada gambar untuk disimpan';
      notifyListeners();
      return false;
    }

    _setStatus(ScanStatus.processing);
    _processingStatus = 'Menyimpan ke galeri…';

    // FIX (P0 — Save tidak menunggu OCR selesai): tunggu run OCR yang
    // sedang jalan (kalau ada) sebelum lanjut, supaya ScannedDocument di
    // bawah dibangun dari _extractedText yang benar-benar sudah final
    // untuk _imagePaths saat ini — lihat komentar lengkap di _runOcr().
    // Error dari OCR sendiri tidak boleh menggagalkan save (sudah ditelan
    // di _runOcrBody(); _extractedText di sini bisa saja tetap null kalau
    // OCR-nya sendiri gagal, itu perilaku yang benar).
    if (_isOcrRunning && _ocrFuture != null) {
      _processingStatus = 'Menunggu OCR selesai…';
      notifyListeners();
      try {
        await _ocrFuture;
      } catch (_) {}
    }

    // documentId & thumbnailPath dideklarasikan di luar try supaya bisa
    // dipakai untuk rollback di catch block kalau ada kegagalan setelah
    // saveImages() berhasil.
    String? id;
    String? thumbnailForRollback;

    try {
      await _requestGalleryPermission();

      id = _storageService.generateId();
      final saved = await _storageService.saveImages(id, _imagePaths);
      thumbnailForRollback = saved.thumbnailPath;

      _processingStatus = 'Menulis ke galeri…';
      notifyListeners();

      // FIX (P1 — Save gallery bisa menghasilkan halaman parsial):
      // sebelumnya loop ini throw _SavePageException pada kegagalan
      // HALAMAN PERTAMA yang gagal, langsung lompat ke catch block di
      // bawah — yang me-rollback dokumen INTERNAL (discardUnsavedDocument,
      // menghapus Documents/{id}/ yang baru saja berhasil di-copy oleh
      // saveImages() di atas). Masalahnya: halaman 1..i-1 yang SUDAH
      // berhasil ditulis oleh SaverGallery.saveFile() di iterasi
      // sebelumnya TETAP ada di galeri publik (Pictures/DocScan) — paket
      // saver_gallery tidak punya API hapus, jadi tidak ada cara
      // membersihkannya balik dari sini. Hasilnya: user melihat pesan
      // "gagal disimpan" (dokumen memang tidak tercatat di app), padahal
      // sebagian halaman scan-nya sudah nyangkut permanen & tidak berlabel
      // di galeri foto pribadinya — persis kebalikan dari yang diharapkan
      // (bukannya tidak ada jejak sama sekali, malah ada jejak PARSIAL
      // yang tidak diketahui user).
      // Fix: salinan ke galeri publik itu SEBENARNYA cuma "bonus" untuk
      // kenyamanan user (sumber kebenaran tetap folder internal
      // Documents/{id}/, sudah tercopy penuh lewat saveImages() di atas
      // — itu sendiri sudah resilient per-halaman, lihat komentar di
      // DocumentStorageService.saveImages()). Jadi loop ini sekarang
      // best-effort juga: coba SEMUA halaman, jangan berhenti di
      // kegagalan pertama, kumpulkan yang gagal. Dokumen tetap
      // dikomit (addDocument) selama ada minimal satu halaman berhasil
      // di-copy secara internal (selalu true di titik ini, karena
      // saveImages() sudah melempar sebelum sampai sini kalau savedPaths
      // kosong) — kegagalan ekspor ke galeri publik jadi warning
      // non-fatal, bukan alasan membuang dokumen yang sebenarnya baik-baik
      // saja.
      // FIX (isSuccess tidak pernah dicek): SaverGallery.saveFile() (paket
      // saver_gallery) mengembalikan objek SaveResult dan pada kegagalan yang
      // WAJAR (izin ditolak saat runtime, storage penuh, path tidak valid)
      // itu DITANGKAP secara internal oleh paket dan dikembalikan sebagai
      // `isSuccess: false` — BUKAN dilempar sebagai exception. Loop
      // sebelumnya cuma mengandalkan try/catch tanpa pernah membaca
      // `.isSuccess`, jadi kegagalan gallery yang paling umum sekalipun lolos
      // tanpa terdeteksi: `failedGalleryPages` tetap kosong, dan
      // `_errorMessage` di bawah tidak pernah muncul meski semua/sebagian
      // halaman sebenarnya gagal tersalin ke galeri publik. Sekarang hasilnya
      // ditangkap dan `isSuccess` dicek eksplisit; try/catch tetap
      // dipertahankan sebagai jaring pengaman untuk kasus non-standar yang
      // benar-benar melempar.
      final failedGalleryPages = <int>[];
      for (var i = 0; i < saved.imagePaths.length; i++) {
        try {
          final result = await SaverGallery.saveFile(
            filePath: saved.imagePaths[i],
            fileName: 'DocScan_${id}_$i',
            androidRelativePath: 'Pictures/DocScan',
            skipIfExists: false,
          );
          if (result.isSuccess != true) {
            failedGalleryPages.add(i + 1);
          }
        } catch (_) {
          failedGalleryPages.add(i + 1);
        }
      }

      _processingStatus = 'Menyimpan data…';
      notifyListeners();

      final doc = ScannedDocument(
        id: id,
        title: title,
        imagePaths: saved.imagePaths,
        extractedText: _extractedText,
        createdAt: DateTime.now(),
        pdfPath: null,
        thumbnailPath: saved.thumbnailPath,
      );
      await _storageService.addDocument(doc);

      // Dokumen berhasil dikomit ke app terlepas dari hasil ekspor galeri
      // publik di atas — beri tahu user kalau sebagian/semua salinan
      // galeri gagal, tapi jangan tandai save-nya sebagai gagal.
      if (failedGalleryPages.isNotEmpty) {
        _errorMessage = failedGalleryPages.length == saved.imagePaths.length
            ? 'Dokumen tersimpan di aplikasi, tapi gagal disalin ke galeri '
                'publik. Pastikan penyimpanan tidak penuh.'
            : 'Dokumen tersimpan di aplikasi. ${failedGalleryPages.length} '
                'dari ${saved.imagePaths.length} halaman gagal disalin ke '
                'galeri publik.';
      }

      _setStatus(ScanStatus.done);
      _clearPreparedCache();
      return true;
    } catch (e) {
      // FIX (P0 — Partial Gallery save → orphan document files):
      // saveImages() di atas sudah men-copy byte ke folder permanen
      // Documents/{id}/ SEBELUM addDocument() dicapai. Kalau ada
      // kegagalan SEBELUM addDocument() berhasil dipanggil (mis. izin
      // storage ditolak, saveImages() sendiri gagal total, atau
      // addDocument()/penulisan metadata gagal), folder itu (dan
      // thumbnail terpisah) sudah ada di disk tapi TIDAK PERNAH tercatat
      // di documents_meta.json — sampah permanen yang menumpuk tiap
      // percobaan save yang gagal di tengah. Bersihkan di sini supaya
      // kegagalan bersih: tidak ada jejak di disk untuk dokumen yang
      // gagal disimpan. (Catatan: sejak fix di atas, kegagalan
      // SaverGallery per-halaman sendiri TIDAK lagi masuk ke catch ini —
      // loop galeri sekarang best-effort dan tidak melempar.)
      if (id != null) {
        await _storageService.discardUnsavedDocument(
          id,
          thumbnailPath: thumbnailForRollback,
        );
      }

      _errorMessage =
          'Gagal menyimpan dokumen. Pastikan penyimpanan tidak penuh, lalu coba lagi.';
      _setStatus(ScanStatus.error);
      return false;
    }
  }

  /// BUG (Ekspor PDF diam-diam / tidak ada feedback): sebelumnya method ini
  /// tidak pernah _setStatus(processing) — beda dari saveDocument() dan
  /// shareImages() yang sudah benar. Akibatnya:
  /// 1. `enabled` di ScanActionButtons (hasImages && !isProcessing) TIDAK
  ///    PERNAH false selama generatePdf() berjalan, jadi tombol "Ekspor
  ///    PDF" (dan Simpan/Bagikan, karena berbagi flag `enabled` yang sama)
  ///    tetap bisa di-tap berkali-kali — spam-tap memicu beberapa
  ///    generatePdf() berjalan bersamaan untuk gambar yang sama.
  /// 2. Tidak ada try/catch — kalau generatePdf() melempar (mis. storage
  ///    penuh), exception-nya jadi unhandled Future error karena dipanggil
  ///    fire-and-forget dari VoidCallback di tombol; user tidak pernah
  ///    lihat pesan error apa pun.
  /// 3. File PDF yang berhasil dibuat tidak pernah diserahkan ke user —
  ///    tidak ada notifyListeners(), tidak disimpan di ScannedDocument
  ///    (dokumen belum tersimpan di titik ini), tidak dibagikan/dibuka.
  ///    Hasilnya: file PDF orphan yang tidak tercatat dan tidak bisa
  ///    diakses user dari mana pun — tekan tombol serasa tidak melakukan
  ///    apa-apa.
  /// Fix: pola yang sama seperti shareImages() (status processing selama
  /// berjalan, guard terhadap pemanggilan ganda, try/catch/finally dengan
  /// _errorMessage saat gagal) + langsung buka share sheet untuk PDF yang
  /// baru dibuat (lewat PdfService.sharePdf) supaya user benar-benar
  /// dapat file-nya, bukan cuma dibuang ke disk.
  Future<void> exportPdf() async {
    if (_imagePaths.isEmpty || isProcessing) return;
    _setStatus(ScanStatus.processing);
    _processingStatus = 'Membuat PDF…';
    notifyListeners();

    try {
      // Check if we have cached PDF-prepared images we can reuse
      final preparedPaths = <String>[];
      for (final originalPath in _imagePaths) {
        // Try to find cached PDF-prepared version first (highest quality for PDF)
        if (_preparedForPdfCache.containsKey(originalPath)) {
          preparedPaths.add(_preparedForPdfCache[originalPath]!);
        }
        // Otherwise prepare fresh
        else {
          final prepared = await _enhanceService.prepareForPdf(originalPath);
          preparedPaths.add(prepared);
          _preparedForPdfCache[originalPath] = prepared;
          _sessionTempFiles.add(prepared);
        }
      }

      final rawTitle = titleController.text.trim();
      final title = rawTitle.isEmpty ? _defaultTitle() : rawTitle;

      // FIX (P1 — PDF preprocessing berpotensi dua kali): preparedPaths di
      // atas sudah lewat ImageEnhanceService.prepareForPdf() (downsize
      // 1920px + encode quality 85). skipDownsize: true supaya
      // PdfService._addImagePage() tidak decodeImage() ulang gambar yang
      // sudah pasti tidak perlu diproses lagi — lihat komentar lengkap di
      // PdfService.generatePdf().
      final pdfPath = await _pdfService.generatePdf(
        title: title,
        imagePaths: preparedPaths,
        skipDownsize: true,
      );

      // Dokumen belum tersimpan di titik ini (exportPdf dipanggil dari
      // layar Scan sebelum "Simpan"), jadi tidak ada tempat permanen untuk
      // mencatat pdfPath ini — serahkan langsung ke user lewat share sheet
      // supaya file-nya benar-benar terpakai, bukan cuma tertulis ke disk
      // tanpa ada yang tahu.
      _processingStatus = 'Membuka PDF…';
      notifyListeners();
      await _pdfService.sharePdf(pdfPath, title);
    } catch (e) {
      _errorMessage = 'Gagal membuat PDF. Coba lagi.';
    } finally {
      _setStatus(ScanStatus.ready);
    }
  }

  /// FIX (integrasi penamaan): sebelumnya share dari layar Scan ini
  /// mengirim _imagePaths mentah lewat XFile(p) TANPA `name:` sama sekali
  /// — jadi apa pun sumber judul yang dipilih user (Otomatis / Manual /
  /// Scan Barcode di ScanTitleInput) SAMA SEKALI tidak kepakai di sini;
  /// nama file yang sampai ke aplikasi tujuan cuma ikut nama file temp
  /// dari plugin scanner/galeri (mis. nama acak/generic), dan berpotensi
  /// bentrok antar halaman/sesi persis seperti bug bulk-share sebelumnya.
  /// Sekarang nama file dibangun dari judul yang sedang aktif di
  /// titleController (apa pun sumbernya) + nomor halaman, sama seperti
  /// pola yang dipakai di BulkShareService & DocumentDetailScreen.
  /// BUG (review "share gambar"): berbeda dari _shareAsImages() di
  /// DocumentDetailScreen dan _bulkShare() di HomeScreen — keduanya sudah
  /// punya guard _isSharing/_isBulkSharing — method ini TIDAK punya guard
  /// sama sekali terhadap pemanggilan ganda. Tombol "Bagikan" di
  /// ScanActionButtons cuma di-disable lewat `enabled: hasImages &&
  /// !isProcessing`, dan isProcessing di sini murni berbasis _status yang
  /// tidak pernah diset ke processing selama share berlangsung. Akibatnya
  /// tombol tetap bisa ditekan berkali-kali saat share sedang berjalan —
  /// tap ganda/cepat memicu beberapa Share.shareXFiles() berjalan
  /// bersamaan, yang di beberapa platform share bisa muncul sebagai share
  /// sheet dobel atau lampiran yang tampak duplikat.
  /// Fix: set status processing selama share berlangsung (sama pola dengan
  /// saveDocument()) supaya tombol ikut ter-disable, dan kembalikan ke
  /// ready setelah selesai (berhasil maupun gagal) karena share tidak
  /// mengubah data gambar yang ada.
  Future<void> shareImages() async {
    if (_imagePaths.isEmpty || isProcessing) return;
    _setStatus(ScanStatus.processing);
    _processingStatus = 'Membagikan…';
    notifyListeners();
    try {
      final rawTitle = titleController.text.trim();
      final title = rawTitle.isEmpty ? _defaultTitle() : rawTitle;
      final safeTitle = _safeFileName(title);
      final files = <XFile>[
        for (int i = 0; i < _imagePaths.length; i++)
          XFile(
            _imagePaths[i],
            mimeType: 'image/jpeg',
            name: '${safeTitle}_hal${i + 1}.jpg',
          ),
      ];
      await Share.shareXFiles(files, subject: title, text: title);
    } finally {
      _setStatus(ScanStatus.ready);
    }
  }

  /// Bersihkan judul supaya aman dipakai sebagai nama file — sama seperti
  /// BulkShareService._safeFileName, dipakai di sini juga supaya perilaku
  /// penamaan konsisten antara share dari layar Scan dan bulk share dari
  /// daftar dokumen, apa pun sumber judulnya (otomatis/manual/barcode).
  static String _safeFileName(String title) {
    final cleaned = title.trim().replaceAll(RegExp(r'[^\w\s-]'), '_');
    return cleaned.isEmpty ? 'Dokumen' : cleaned;
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ── Sumber penamaan dokumen: otomatis / manual / scan barcode ──────────

  /// Isi ulang nama dokumen dengan judul otomatis berbasis waktu saat ini.
  /// Dipakai saat user memilih opsi "Otomatis" di layar scan.
  void useAutoTitle() {
    titleController.text = _defaultTitle();
  }

  /// Isi nama dokumen dari hasil scan barcode/QR. [rawValue] sudah berupa
  /// hasil decode mentah dari mobile_scanner — dibersihkan dulu dari
  /// baris baru/whitespace berlebih sebelum dipakai sebagai judul, karena
  /// beberapa barcode (mis. QR multi-baris) bisa mengandung newline yang
  /// akan merusak tampilan field judul satu baris.
  void useBarcodeTitle(String rawValue) {
    final cleaned = rawValue.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return;
    titleController.text = cleaned;
  }

  // Override tunggal ini cukup untuk menjaga SEMUA pemanggilan
  // notifyListeners() di controller ini (ada 11 titik) — lihat komentar
  // _disposed di atas untuk kenapa ini diperlukan.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  // ─── Private Helpers ──────────────────────────────────────────────────────

  void _setStatus(ScanStatus s) {
    _status = s;
    notifyListeners();
  }

  /// Run OCR with caching to avoid reprocessing images
  ///
  /// BUG (race condition): _runOcr() dipanggil fire-and-forget (tanpa
  /// await) dari startScan() dan replaceImage() — kalau user edit halaman
  /// lagi sebelum proses OCR sebelumnya selesai, dua _runOcr() jalan
  /// BERSAMAAN untuk set halaman yang berbeda. Siapa pun yang selesai
  /// TERAKHIR menang menimpa _extractedText, terlepas dari mana yang
  /// benar-benar merepresentasikan halaman saat ini — kalau proses yang
  /// LAMA (untuk set halaman lama) selesai belakangan, hasilnya OCR yang
  /// ditampilkan tidak sesuai dengan halaman yang sedang aktif.
  /// _isOcrRunning juga bisa ke-reset false oleh proses lama padahal
  /// proses baru masih berjalan.
  /// Fix: token generasi (_ocrRunId) — tiap pemanggilan _runOcr() dapat id
  /// baru; hasil (extractedText/isOcrRunning) hanya diterapkan kalau id
  /// pemanggil masih yang PALING BARU saat itu selesai. Proses yang sudah
  /// "kalah start" tetap boleh selesai di background, tapi hasilnya dibuang.
  ///
  /// FIX (P0 — Save tidak menunggu OCR selesai): sebelumnya saveDocument()
  /// baca _extractedText apa adanya di titik itu, tanpa peduli apakah
  /// _runOcr() (dipanggil fire-and-forget dari startScan()/replaceImage())
  /// masih berjalan atau belum. Kalau user menekan "Simpan" cukup cepat
  /// setelah scan/edit halaman — sebelum OCR yang sedang berjalan selesai —
  /// dokumen tersimpan dengan extractedText NULL atau (lebih buruk) hasil
  /// OCR halaman yang SUDAH TIDAK RELEVAN dari run sebelumnya. Dan karena
  /// tidak ada satu pun titik lain di app ini yang meng-update
  /// extractedText dokumen setelah tersimpan (lihat updateDocument() —
  /// hanya dipakai untuk pdfPath), teks OCR itu hilang PERMANEN, bukan
  /// cuma telat — user harus hapus & scan ulang dari nol untuk dapat OCR.
  /// Fix: _runOcr() sekarang menyimpan Future dirinya sendiri ke
  /// _ocrFuture; saveDocument() await Future itu (kalau sedang berjalan)
  /// SEBELUM membaca _extractedText untuk dibungkus ke ScannedDocument.
  Future<void> _runOcr() {
    if (_imagePaths.isEmpty) {
      // FIX (P1 — OCR stale saat semua halaman dihapus): sebelumnya
      // early-return di sini cuma `return Future.value()` tanpa menyentuh
      // _extractedText sama sekali. Kalau user menghapus SEMUA halaman
      // (removeImage() sampai _imagePaths kosong), _runOcr() dipanggil
      // (lihat removeImage()) tapi langsung berhenti di sini — hasilnya
      // _extractedText tetap berisi teks OCR dari halaman TERAKHIR yang
      // baru saja dihapus, terus ditampilkan di ScanOcrSection meski
      // tidak ada satu pun halaman lagi yang menjadi sumbernya. Kalau
      // user lalu scan halaman baru yang belum sempat di-OCR (mis. OCR
      // baru masih berjalan), teks basi dari sesi sebelumnya itu bahkan
      // bisa ikut ke saveDocument() sebagai extractedText dokumen baru
      // yang sama sekali tidak berhubungan.
      // Fix: perlakukan kondisi "tidak ada halaman" sebagai state OCR
      // yang bersih eksplisit — kosongkan _extractedText, matikan
      // _isOcrRunning, dan naikkan _ocrRunId supaya run OCR manapun yang
      // masih berjalan di background (untuk _imagePaths versi sebelum
      // dikosongkan) tahu hasilnya sudah basi dan dibuang (lihat guard
      // runId != _ocrRunId di _runOcrBody()).
      _ocrRunId++;
      _extractedText = null;
      _isOcrRunning = false;
      notifyListeners();
      return Future.value();
    }
    final future = _runOcrBody();
    _ocrFuture = future;
    return future;
  }

  Future<void> _runOcrBody() async {
    final runId = ++_ocrRunId;
    _isOcrRunning = true;
    notifyListeners();

    try {
      // Prepare images for OCR, using cache if available
      final preparedPaths = <String>[];
      for (final originalPath in _imagePaths) {
        if (_preparedForOcrCache.containsKey(originalPath)) {
          // Use cached prepared version
          preparedPaths.add(_preparedForOcrCache[originalPath]!);
        } else {
          // Prepare fresh and cache
          final prepared = await _enhanceService.prepareForOcr(originalPath);
          if (runId != _ocrRunId) return; // sudah ada _runOcr() lebih baru
          preparedPaths.add(prepared);
          _preparedForOcrCache[originalPath] = prepared;
          _sessionTempFiles.add(prepared);
        }
      }

      final text = await _ocrService.extractTextFromImages(preparedPaths);
      if (runId != _ocrRunId) return; // hasil basi — sudah ada run lebih baru
      _extractedText = text;
    } catch (_) {
      if (runId != _ocrRunId) return;
      _extractedText = null;
    } finally {
      if (runId == _ocrRunId) {
        _isOcrRunning = false;
        notifyListeners();
      }
    }
  }

  /// Clear prepared image caches to free memory
  void _clearPreparedCache() {
    _preparedForOcrCache.clear();
    _preparedForPdfCache.clear();
  }

  /// BUG (Gallery permission Android 13+): sebelumnya fungsi ini mewajibkan
  /// READ_MEDIA_IMAGES (Permission.photos) di Android 13+, dan
  /// READ_EXTERNAL_STORAGE di Android 10–12, sebelum SaverGallery.saveFile()
  /// boleh dipanggil — padahal operasi di sini murni MENULIS file BARU
  /// milik app sendiri ke MediaStore (scoped storage), bukan MEMBACA galeri
  /// (tidak ada fitur "pilih dari galeri" di app ini — ImagePicker cuma
  /// dipakai untuk kamera, lihat ScannerService). Sejak Android 10 (scoped
  /// storage), menulis media baru lewat MediaStore TIDAK memerlukan izin
  /// storage/media apa pun; READ_MEDIA_IMAGES/READ_EXTERNAL_STORAGE cuma
  /// relevan untuk MEMBACA media milik app lain. AndroidManifest.xml app
  /// ini pun sudah membatasi READ_EXTERNAL_STORAGE ke maxSdkVersion=32 dan
  /// WRITE_EXTERNAL_STORAGE ke maxSdkVersion=28 — developer sudah sadar
  /// soal scoped storage, tapi logic permintaan izin di sini belum
  /// disesuaikan. Akibatnya: user yang (wajar) menolak izin akses
  /// foto/media di Android 10+ jadi TIDAK BISA menyimpan dokumen sama
  /// sekali, padahal operasi save-nya sendiri sebenarnya tidak butuh izin
  /// itu. Di Android 13+ ini makin parah: fallback ke Permission.storage
  /// setelah photos ditolak juga PASTI gagal, karena READ_EXTERNAL_STORAGE
  /// dibatasi maxSdkVersion=32 di manifest — jadi permintaan itu tidak
  /// pernah bisa granted di API 33+ sama sekali (dead-end fallback).
  /// Fix: hanya minta WRITE_EXTERNAL_STORAGE di Android ≤9 (API ≤28) —
  /// satu-satunya rentang yang benar-benar butuh izin untuk menulis file
  /// publik lewat File API langsung (sebelum MediaStore/scoped storage
  /// ada, dan konsisten dengan maxSdkVersion=28 di manifest). Android 10+
  /// langsung lanjut tanpa minta izin apa pun.
  Future<void> _requestGalleryPermission() async {
    if (!Platform.isAndroid) return;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkVersion = androidInfo.version.sdkInt;

    if (sdkVersion >= 29) return; // scoped storage — MediaStore write tidak butuh izin

    // Android 7–9 (API 24–28) → WRITE_EXTERNAL_STORAGE wajib
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      throw Exception(
        'Izin storage ditolak. Buka Pengaturan › Izin › Storage lalu aktifkan.',
      );
    }
  }

  /// FIX lanjutan: presisi cuma sampai menit bikin 2+ dokumen yang
  /// di-scan berturut-turut dalam menit yang sama dapat judul default
  /// IDENTIK — ini akar salah satu bug share ganda (nama file antar
  /// dokumen bentrok saat multi-share, lihat BulkShareService.shareAsImages).
  /// Tambah detik supaya judul default antar dokumen praktis selalu unik.
  static String _defaultTitle() {
    final now = DateTime.now();
    // FIX: sebelumnya day/month/hour tidak di-padLeft (cuma minute yang
    // di-pad), jadi hasilnya tidak konsisten, mis. "Scan 3-7-2026 9:05"
    // bukan "Scan 03-07-2026 09:05". Judul default ini juga yang jadi
    // basis nama file PDF (lihat PdfService.generatePdf), jadi
    // ketidak-konsistenan ini ikut kebawa ke nama file.
    final dd = now.day.toString().padLeft(2, '0');
    final mo = now.month.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return 'Scan $dd-$mo-${now.year} $hh:$mm:$ss';
  }

  @override
  void dispose() {
    _disposed = true;
    titleController.dispose();
    _clearPreparedCache();

    // LIFECYCLE CLEANUP: sebelumnya tidak ada satu pun titik yang menghapus
    // file sementara sesi ini dari disk — ScannerService.cleanupFiles()
    // sudah ada tapi tidak pernah dipanggil dari mana pun, sehingga setiap
    // sesi scan (halaman mentah dari kamera, hasil rotate/crop/enhance dari
    // Image Editor, versi prepared untuk OCR & PDF) meninggalkan file yatim
    // di temporary directory selamanya — baik saat user batal scan maupun
    // setelah dokumen berhasil disimpan (karena saveDocument() sudah
    // meng-copy byte-nya ke folder permanen, bukan memindahkan file ini).
    // dispose() tidak bisa async, jadi cleanup dijalankan fire-and-forget;
    // ScannerService.cleanupFiles() sendiri sudah aman menelan error per
    // file (mis. sudah kehapus lebih dulu).
    if (_sessionTempFiles.isNotEmpty) {
      unawaited(_scannerService.cleanupFiles(_sessionTempFiles.toList()));
    }

    super.dispose();
  }
}
