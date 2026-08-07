class ScannedDocument {
  final String id;
  final String title;
  final List<String> imagePaths;
  final String? extractedText;
  final DateTime createdAt;
  final String? pdfPath;
  final String? thumbnailPath;

  ScannedDocument({
    required this.id,
    required this.title,
    required this.imagePaths,
    this.extractedText,
    required this.createdAt,
    this.pdfPath,
    this.thumbnailPath,
  });

  // ── Search index cache ──────────────────────────────────────────────────
  // Objek ini immutable (semua field final), jadi gabungan title+extractedText
  // dalam huruf kecil aman dihitung sekali lalu di-cache di sini. Ini
  // menghindari toLowerCase() berulang atas extractedText (bisa ribuan
  // karakter hasil OCR) di setiap keystroke pencarian saat koleksi besar.
  String? _searchIndexCache;

  String get _searchIndex => _searchIndexCache ??=
      '${title.toLowerCase()} ${(extractedText ?? '').toLowerCase()}';

  /// Cek apakah dokumen cocok dengan [lowerCaseQuery] (harus sudah lowercase
  /// & trimmed oleh pemanggil, supaya tidak diulang per-dokumen).
  bool matchesQuery(String lowerCaseQuery) =>
      _searchIndex.contains(lowerCaseQuery);

  /// Empty document for safe defaults
  ScannedDocument.empty()
      : id = '',
        title = '',
        imagePaths = [],
        extractedText = null,
        createdAt = DateTime.now(),
        pdfPath = null,
        thumbnailPath = null;

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'imagePaths': imagePaths,
        'extractedText': extractedText,
        'createdAt': createdAt.toIso8601String(),
        'pdfPath': pdfPath,
        'thumbnailPath': thumbnailPath,
      };

  /// Create from JSON
  factory ScannedDocument.fromJson(Map<String, dynamic> json) =>
      ScannedDocument(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Untitled',
        imagePaths: List<String>.from(json['imagePaths'] as List? ?? []),
        extractedText: json['extractedText'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        pdfPath: json['pdfPath'] as String?,
        thumbnailPath: json['thumbnailPath'] as String?,
      );

  /// Format created date for display
  String get formattedDate {
    try {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour.toString().padLeft(2,'0')}:${createdAt.minute.toString().padLeft(2,'0')}';
    } catch (_) {
      return 'Unknown date';
    }
  }

  /// Get page count
  int get pageCount => imagePaths.length;

  /// Copy with modifications
  ScannedDocument copyWith({
    String? id,
    String? title,
    List<String>? imagePaths,
    String? extractedText,
    DateTime? createdAt,
    String? pdfPath,
    String? thumbnailPath,
  }) =>
      ScannedDocument(
        id: id ?? this.id,
        title: title ?? this.title,
        imagePaths: imagePaths ?? this.imagePaths,
        extractedText: extractedText ?? this.extractedText,
        createdAt: createdAt ?? this.createdAt,
        pdfPath: pdfPath ?? this.pdfPath,
        thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      );

  @override
  String toString() =>
      'ScannedDocument($id, "$title", ${imagePaths.length} pages)';
}
