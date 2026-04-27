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

  /// Generate PDF
  Future<String> generatePdf({
    required String title,
    required List<String> imagePaths,
    String? extractedText,
    bool includeTextLayer = false,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    if (imagePaths.isEmpty) {
      throw Exception("Tidak ada gambar untuk dibuat PDF");
    }

    final pdf = pw.Document(
      title: title,
      author: 'DocScan App',
    );

    for (final path in imagePaths) {
      try {
        final file = File(path);
        if (!await file.exists()) continue;

        final bytes = await file.readAsBytes();
        final image = pw.MemoryImage(bytes);

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
      } catch (e) {
        print("Error load image: $e");
      }
    }

    // OCR text page
    if (includeTextLayer && (extractedText?.isNotEmpty ?? false)) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(32),
          build: (_) => [
            pw.Text(
              "$title - Hasil OCR",
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(extractedText!, style: const pw.TextStyle(fontSize: 11)),
          ],
        ),
      );
    }

    // Save file
    final dir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory('${dir.path}/DocScan');
    await pdfDir.create(recursive: true);

    final fileName =
        "${title.replaceAll(RegExp(r'[^\w\s]'), '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf";

    final file = File('${pdfDir.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  /// Share PDF (FIX API terbaru)
  Future<void> sharePdf(String path, String title) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception("File tidak ditemukan");
    }

    final xFile = XFile(path, mimeType: 'application/pdf');

    await Share.shareXFiles(
      [xFile],
      subject: title,
      text: "Dokumen: $title",
    );
  }

  /// Open PDF
  Future<void> openPdf(String path) async {
    final result = await OpenFile.open(path);

    if (result.type != ResultType.done) {
      throw Exception("Gagal membuka file: ${result.message}");
    }
  }

  /// Print PDF
  Future<void> printPdf(String path, String title) async {
    final file = File(path);
    final bytes = await file.readAsBytes();

    await Printing.layoutPdf(
      name: title,
      onLayout: (_) async => bytes,
    );
  }

  /// Get file size
  Future<String> getPdfSize(String path) async {
    final file = File(path);
    if (!await file.exists()) return "Unknown";

    final bytes = await file.length();

    if (bytes < 1024) return "${bytes} B";
    if (bytes < 1024 * 1024) {
      return "${(bytes / 1024).toStringAsFixed(1)} KB";
    }
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  /// Delete PDF
  Future<void> deletePdf(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
