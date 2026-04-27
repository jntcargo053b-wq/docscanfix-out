class ScannedDocument {
  final String id;
  final String title;
  final List<String> imagePaths;
  final String? extractedText;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? pdfPath;
  final String? thumbnailPath; // ← baru: thumbnail cache

  ScannedDocument({
    required this.id,
    required this.title,
    required this.imagePaths,
    this.extractedText,
    required this.createdAt,
    this.updatedAt,
    this.pdfPath,
    this.thumbnailPath,
  });

  int get pageCount => imagePaths.length;

  ScannedDocument copyWith({
    String? title,
    List<String>? imagePaths,
    String? extractedText,
    DateTime? updatedAt,
    String? pdfPath,
    String? thumbnailPath,
  }) {
    return ScannedDocument(
      id: id,
      title: title ?? this.title,
      imagePaths: imagePaths ?? this.imagePaths,
      extractedText: extractedText ?? this.extractedText,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pdfPath: pdfPath ?? this.pdfPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'imagePaths': imagePaths,
      'extractedText': extractedText,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'pdfPath': pdfPath,
      'thumbnailPath': thumbnailPath,
    };
  }

  factory ScannedDocument.fromJson(Map<String, dynamic> json) {
    return ScannedDocument(
      id: json['id'],
      title: json['title'],
      imagePaths: List<String>.from(json['imagePaths']),
      extractedText: json['extractedText'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
      pdfPath: json['pdfPath'],
      thumbnailPath: json['thumbnailPath'],
    );
  }
}
