import 'dart:io';
import 'package:crypto/crypto.dart';

/// Hitung MD5 sebuah file lewat streaming (openRead()), BUKAN
/// readAsBytes() penuh ke memori.
///
/// FIX (P1 — MD5 readAsBytes() baca seluruh file ke RAM): sebelumnya
/// setiap tempat yang butuh hash konten file (ScannerService._dedupeByContent,
/// ScanController._hashAll/_dedupeAgainstHashes) memanggil
/// `File(path).readAsBytes()` lalu `md5.convert(bytes)` — untuk foto kamera
/// resolusi asli (bisa 10-20+ MB per file) ini berarti SELURUH isi file
/// dimuat ke memori sekaligus cuma untuk dibuang lagi setelah hash selesai.
/// Untuk sesi scan dengan banyak halaman, hash dihitung berulang kali
/// (existing snapshot + newPaths + tiap _dedupeByContent call) — beban RAM
/// sesaat bisa menumpuk kalau beberapa hash dihitung berdekatan.
///
/// Fix: pakai `File.openRead()` (Stream<List<int>>, baca per-chunk dari
/// disk) dipipa langsung ke `md5.bind()`, yang meng-update digest MD5
/// incremental per chunk tanpa pernah menahan seluruh isi file di memori
/// sekaligus. Hasil akhirnya identik (MD5 dari isi file yang sama), cuma
/// peak RAM per hash turun dari "ukuran file" ke "ukuran satu chunk baca".
Future<String?> hashFileStreaming(String path) async {
  try {
    final file = File(path);
    final digest = await md5.bind(file.openRead()).first;
    return digest.toString();
  } catch (_) {
    return null;
  }
}
