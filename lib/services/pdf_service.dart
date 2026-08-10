import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
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
  ///
  /// BUG (PDF raw image menahan RAM besar): komentar di atas ("peak RAM ≈
  /// ukuran satu gambar") SALAH — pw.Document.addPage() menyimpan closure
  /// `build` untuk tiap halaman, dan closure itu MENAHAN referensi ke
  /// pw.MemoryImage (berikut byte gambar yang sudah di-decode) sampai
  /// pdf.save() benar-benar dipanggil di akhir, setelah SEMUA halaman
  /// selesai ditambahkan. Jadi imageBytes TIDAK keluar scope secara efektif
  /// — GC tidak bisa membebaskannya sampai save(). Untuk dokumen banyak
  /// halaman dari foto kamera resolusi asli (bisa 12+ MP / puluhan MB
  /// ter-decode per halaman), total RAM yang tertahan adalah SEMUA halaman
  /// sekaligus, bukan satu — berisiko OOM di HP kelas menengah-bawah.
  /// Sebelumnya cuma ScanController.exportPdf() yang menghindari ini
  /// (lewat ImageEnhanceService.prepareForPdf() sebagai pre-step manual);
  /// BulkShareService.shareAsPdf() & DocumentDetailScreen._exportAsPdf()
  /// memanggil generatePdf() LANGSUNG dengan imagePaths resolusi asli,
  /// tanpa downsize sama sekali.
  /// Fix: downsize + re-encode tiap gambar di dalam generatePdf() sendiri
  /// (max 1920px sisi terpanjang, sama seperti prepareForPdf), supaya
  /// SEMUA caller — bukan cuma yang sudah tahu untuk pre-process — dapat
  /// batas RAM per halaman yang wajar. Ini tidak menghilangkan penahanan
  /// oleh closure (itu keterbatasan struktural package pdf), tapi
  /// mengecilkan ukuran yang tertahan secara drastis.
  /// FIX (P1 — PDF preprocessing berpotensi dua kali): [skipDownsize] baru.
  /// ScanController.exportPdf() SUDAH menyiapkan imagePaths lewat
  /// ImageEnhanceService.prepareForPdf() (downsize 1920px + encode quality
  /// 85, dijalankan di isolate terpisah) SEBELUM manggil generatePdf() ini
  /// — tapi _addImagePage() di bawah tetap decodeImage() ULANG tiap file
  /// untuk cek apakah perlu di-resize (meski akhirnya skip resize karena
  /// sudah ≤1920px). decodeImage() itu sendiri tidak murah (baca+decode
  /// JPEG penuh) walau hasilnya dibuang — jadi ScanController.exportPdf()
  /// bayar biaya decode dua kali (sekali di prepareForPdf's isolate, sekali
  /// lagi di sini) untuk gambar yang sudah pasti tidak perlu diproses ulang.
  /// Caller yang SUDAH pre-process (skipDownsize: true) lewati decode+cek
  /// ukuran sama sekali, pakai rawBytes apa adanya. Caller yang BELUM
  /// pre-process (BulkShareService.shareAsPdf(), DocumentDetailScreen.
  /// _exportAsPdf() — keduanya generate dari imagePaths resolusi kamera
  /// asli) tetap dapat safety-net downsize seperti sebelumnya (default
  /// false, tidak berubah untuk mereka).
  Future<String> generatePdf({
    required String title,
    required List<String> imagePaths,
    String? extractedText,
    bool includeTextLayer = false,
    bool skipDownsize = false,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    if (imagePaths.isEmpty) throw Exception('Tidak ada gambar untuk dibuat PDF');

    final pdf = pw.Document(title: title, author: 'DocScan App');

    for (final path in imagePaths) {
      final file = File(path);
      if (!await file.exists()) continue;

      // Baca → buat page → biarkan imageBytes keluar scope agar GC bisa bebaskan
      await _addImagePage(pdf, path, pageFormat, skipDownsize: skipDownsize);
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

  /// Baca satu gambar, downsize kalau perlu (max 1920px sisi terpanjang,
  /// cukup untuk cetak/tampil di PDF ukuran A4 — lihat catatan RAM di
  /// generatePdf()), tambahkan sebagai [pw.Page].
  Future<void> _addImagePage(
    pw.Document pdf,
    String imagePath,
    PdfPageFormat pageFormat, {
    bool skipDownsize = false,
  }) async {
    final rawBytes = await File(imagePath).readAsBytes();
    Uint8List imageBytes = rawBytes;

    if (!skipDownsize) {
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null &&
          (decoded.width > 1920 || decoded.height > 1920)) {
        final resized = img.copyResize(
          decoded,
          width: decoded.width > decoded.height ? 1920 : -1,
          height: decoded.height >= decoded.width ? 1920 : -1,
          interpolation: img.Interpolation.linear,
        );
        imageBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
      }
    }

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
    // imageBytes keluar scope di sini (peak RAM tetap tertahan lewat
    // closure di atas sampai pdf.save(), tapi ukurannya sudah dibatasi)
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
