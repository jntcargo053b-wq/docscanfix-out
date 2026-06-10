import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';

class PdfService {
  static final PdfService _instance = PdfService._internal();
  factory PdfService() => _instance;
  PdfService._internal();

  /// Generate PDF hemat RAM: setiap gambar di-decode, di-encode ke pw.Page,
  /// lalu referensi [imageBytes] dibuang sebelum gambar berikutnya dimuat.
  ///
  /// Tidak ada merge — semua halaman masuk ke satu [pw.Document] lewat
  /// [addPage] biasa, sehingga tidak bergantung pada API internal package pdf.
  /// Peak RAM ≈ ukuran satu gambar + ukuran PDF yang sedang dibangun.
  Future<String> generatePdf({
    required String title,
    required List<String> imagePaths,
    String? extractedText,
    bool includeTextLayer = false,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    if (imagePaths.isEmpty) throw Exception('Tidak ada gambar untuk dibuat PDF');

    final pdf = pw.Document(title: title, author: 'DocScan App');

    for (final path in imagePaths) {
      final file = File(path);
      if (!await file.exists()) continue;

      // Baca → buat page → biarkan imageBytes keluar scope agar GC bisa bebaskan
      await _addImagePage(pdf, path, pageFormat);
    }

    if (includeTextLayer && (extractedText?.isNotEmpty ?? false)) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(32),
          build: (_) => [
            pw.Text(
              '$title — Hasil OCR',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.Text(extractedText!, style: const pw.TextStyle(fontSize: 11)),
          ],
        ),
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory('${dir.path}/DocScan');
    await pdfDir.create(recursive: true);

    final safeTitle = title.replaceAll(RegExp(r'[^\w\s]'), '_');
    final fileName = '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final outFile = File('${pdfDir.path}/$fileName');
    await outFile.writeAsBytes(await pdf.save());

    return outFile.path;
  }

  /// Baca satu gambar, tambahkan sebagai [pw.Page], lalu kembalikan.
  /// Dipisah ke method sendiri agar [imageBytes] keluar scope setelah return
  /// dan GC dapat membebaskan memori sebelum iterasi berikutnya.
  Future<void> _addImagePage(
    pw.Document pdf,
    String imagePath,
    PdfPageFormat pageFormat,
  ) async {
    final imageBytes = await File(imagePath).readAsBytes();
    final image = pw.MemoryImage(imageBytes);
    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ),
      ),
    );
    // imageBytes keluar scope di sini
  }

  /// Share PDF
  Future<void> sharePdf(String path, String title) async {
    if (!await File(path).exists()) throw Exception('File tidak ditemukan');
    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/pdf')],
      subject: title,
      text: 'Dokumen: $title',
    );
  }

  /// Open PDF
  Future<void> openPdf(String path) async {
    final result = await OpenFile.open(path);
    if (result.type != ResultType.done) {
      throw Exception('Gagal membuka file: ${result.message}');
    }
  }

  /// Print PDF
  Future<void> printPdf(String path, String title) async {
    final bytes = await File(path).readAsBytes();
    await Printing.layoutPdf(name: title, onLayout: (_) async => bytes);
  }

  /// Get file size (human-readable)
  Future<String> getPdfSize(String path) async {
    if (!await File(path).exists()) return 'Unknown';
    final bytes = await File(path).length();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  /// Delete PDF
  Future<void> deletePdf(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
