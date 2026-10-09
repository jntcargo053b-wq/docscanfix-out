class ScannedDocument {
  final String id;
  final String title;
  final List<String> imagePaths;
  /// OCR text aligned with [imagePaths]. Empty entries mean no text or failure.
  final List<String> pageTexts;
  final String? extractedText;
  final DateTime createdAt;
  final String? pdfPath;
  final String? thumbnailPath;

  ScannedDocument({
    required this.id,
    required this.title,
    required this.imagePaths,
    this.pageTexts = const [],
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
      '${title.toLowerCase()} ${(extractedText ?? '').toLowerCase()} ${pageTexts.join(' ').toLowerCase()}';

  /// Cek apakah dokumen cocok dengan [lowerCaseQuery] (harus sudah lowercase
  /// & trimmed oleh pemanggil, supaya tidak diulang per-dokumen).
  bool matchesQuery(String lowerCaseQuery) =>
      _searchIndex.contains(lowerCaseQuery);



  /// Returns a short OCR/title excerpt around the first match.
  /// The returned text is intended for list previews, not for exporting.
  String? searchSnippet(String lowerCaseQuery, {int radius = 58}) {
    final query = lowerCaseQuery.trim().toLowerCase();
    if (query.isEmpty) return null;

    final sources = <String>[
      title,
      if (extractedText?.trim().isNotEmpty == true) extractedText!,
      ...pageTexts.where((text) => text.trim().isNotEmpty),
    ];

    for (final source in sources) {
      final lower = source.toLowerCase();
      final matchIndex = lower.indexOf(query);
      if (matchIndex < 0) continue;

      final start = matchIndex > radius ? matchIndex - radius : 0;
      final end = (matchIndex + query.length + radius).clamp(0, source.length);
      var snippet = source.substring(start, end).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (start > 0) snippet = '…$snippet';
      if (end < source.length) snippet = '$snippet…';
      return snippet;
    }
    return null;
  }

  /// Empty document for safe defaults
  ScannedDocument.empty()
      : id = '',
        title = '',
        imagePaths = [],
        pageTexts = const [],
        extractedText = null,
        createdAt = DateTime.now(),
        pdfPath = null,
        thumbnailPath = null;

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'imagePaths': imagePaths,
        'pageTexts': pageTexts,
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
        pageTexts: List<String>.from(json['pageTexts'] as List? ?? []),
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
    List<String>? pageTexts,
    String? extractedText,
    DateTime? createdAt,
    String? pdfPath,
    String? thumbnailPath,
    bool clearPdfPath = false,
    bool clearThumbnailPath = false,
    bool clearExtractedText = false,
  }) =>
      ScannedDocument(
        id: id ?? this.id,
        title: title ?? this.title,
        imagePaths: imagePaths ?? this.imagePaths,
        pageTexts: pageTexts ?? this.pageTexts,
        extractedText: clearExtractedText ? null : (extractedText ?? this.extractedText),
        createdAt: createdAt ?? this.createdAt,
        pdfPath: clearPdfPath ? null : (pdfPath ?? this.pdfPath),
        thumbnailPath:
            clearThumbnailPath ? null : (thumbnailPath ?? this.thumbnailPath),
      );

  @override
  String toString() =>
      'ScannedDocument($id, "$title", ${imagePaths.length} pages)';
}
