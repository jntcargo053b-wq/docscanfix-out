import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import '../models/scanned_document.dart';

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

  /// Save document list to disk with debouncing to batch writes
  Future<void> _deferredSaveDocuments() async {
    // Cancel previous timer
    _writeTimer?.cancel();

    // Schedule write after delay to batch rapid updates
    _writeTimer = Timer(_writeDelay, () async {
      if (_cachedDocuments == null) return;
      try {
        final file = await _metaFilePath;
        final jsonStr = json.encode(
          _cachedDocuments!.map((d) => d.toJson()).toList(),
        );
        await file.writeAsString(jsonStr);
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
      final file = await _metaFilePath;
      final jsonStr = json.encode(
        _cachedDocuments!.map((d) => d.toJson()).toList(),
      );
      await file.writeAsString(jsonStr);
    } catch (e) {
      throw Exception('Failed to save documents: $e');
    }
  }

  /// Add a new document
  Future<void> addDocument(ScannedDocument document) async {
    // Load from cache if valid, otherwise from disk
    final docs = await loadDocuments();

    // Modify in-memory cache
    _cachedDocuments = [document, ...docs];
    _cacheValid = true;

    // Schedule write with debounce
    await _deferredSaveDocuments();
  }

  /// Update an existing document
  Future<void> updateDocument(ScannedDocument document) async {
    final docs = await loadDocuments();
    final idx = docs.indexWhere((d) => d.id == document.id);
    if (idx == -1) return;

    // Modify cache in-place
    _cachedDocuments![idx] = document;
    _cacheValid = true;

    // Schedule write with debounce
    await _deferredSaveDocuments();
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

    for (int i = 0; i < tempPaths.length; i++) {
      // FIX: skip path kosong/null-string sebelum membuat File object
      final rawPath = tempPaths[i].trim();
      if (rawPath.isEmpty) continue;

      final tempFile = File(rawPath);
      if (!await tempFile.exists()) continue;

      final newPath = '${docDir.path}/page_${i + 1}.jpg';
      try {
        await tempFile.copy(newPath);
      } catch (e) {
        // Lewati halaman ini jika copy gagal (misal: storage penuh / permission I/O)
        // Jangan lempar — biarkan halaman lain tetap diproses
        continue;
      }
      savedPaths.add(newPath);

      if (i == 0) thumbnailPath = newPath;
    }

    // FIX: jika tidak ada satu pun file berhasil di-copy, lempar error
    // agar caller tidak menyimpan dokumen kosong ke storage
    if (savedPaths.isEmpty) {
      throw Exception('Semua file gambar tidak ditemukan atau tidak dapat dibaca.');
    }

    return (imagePaths: savedPaths, thumbnailPath: thumbnailPath);
  }

  /// Generate unique document ID
  String generateId() {
    return 'doc_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Clear cache (useful when external changes might occur)
  void invalidateCache() {
    _cacheValid = false;
    _writeTimer?.cancel();
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
