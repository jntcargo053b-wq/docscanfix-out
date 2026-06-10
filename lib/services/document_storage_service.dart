import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/scanned_document.dart';

class DocumentStorageService {
  static final DocumentStorageService _instance =
      DocumentStorageService._internal();
  factory DocumentStorageService() => _instance;
  DocumentStorageService._internal();

  static const String _metaFile = 'documents_meta.json';

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

  /// Load all documents from local storage
  Future<List<ScannedDocument>> loadDocuments() async {
    try {
      final file = await _metaFilePath;
      if (!await file.exists()) return [];

      final jsonStr = await file.readAsString();
      final List<dynamic> jsonList = json.decode(jsonStr);
      return jsonList.map((j) => ScannedDocument.fromJson(j)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      return [];
    }
  }

  /// Save document list to local storage
  Future<void> saveDocuments(List<ScannedDocument> documents) async {
    try {
      final file = await _metaFilePath;
      final jsonStr = json.encode(documents.map((d) => d.toJson()).toList());
      await file.writeAsString(jsonStr);
    } catch (e) {
      throw Exception('Failed to save documents: $e');
    }
  }

  /// Add a new document
  Future<void> addDocument(ScannedDocument document) async {
    final docs = await loadDocuments();
    docs.insert(0, document);
    await saveDocuments(docs);
  }

  /// Update an existing document
  Future<void> updateDocument(ScannedDocument document) async {
    final docs = await loadDocuments();
    final idx = docs.indexWhere((d) => d.id == document.id);
    if (idx != -1) {
      docs[idx] = document;
      await saveDocuments(docs);
    }
  }

  /// FIX: gunakan firstWhereOrNull pattern untuk menghindari StateError
  /// jika ID tidak ditemukan — sebelumnya firstWhere tanpa orElse akan crash.
  Future<void> deleteDocument(String documentId) async {
    final docs = await loadDocuments();

    // Cari dokumen; jika tidak ada, langsung return (idempotent delete)
    final docIndex = docs.indexWhere((d) => d.id == documentId);
    if (docIndex == -1) return;

    final doc = docs[docIndex];

    // Delete image files
    for (final path in doc.imagePaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    // Delete PDF if exists
    if (doc.pdfPath != null) {
      try {
        final pdf = File(doc.pdfPath!);
        if (await pdf.exists()) await pdf.delete();
      } catch (_) {}
    }

    docs.removeAt(docIndex);
    await saveDocuments(docs);
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
}
