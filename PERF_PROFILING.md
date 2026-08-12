# Panduan Profiling OCR Multi-Halaman & Memori PDF (10/20/30 halaman)

Instrumentasi sudah ditanam di kode (`PerfProbe` di `lib/utils/perf_probe.dart`,
dipakai di `ScanController._prepareAndExtractPipelined()`,
`PdfService.generatePdf()`, `PdfService.generatePdfChunked()`) + test harness
on-device di `integration_test/ocr_pdf_perf_test.dart`.

Saya tidak bisa mengeksekusi ini di sandbox (tidak ada Flutter SDK/emulator
di sini), jadi berikut cara jalanin di sisi kamu dan cara baca hasilnya.

## 1. Setup

```bash
flutter pub get
flutter devices    # pastikan device/emulator tersambung
```

**Pakai device/emulator dengan RAM rendah-menengah (2-4GB)** kalau bisa —
angka RSS di emulator RAM besar bisa menyembunyikan masalah yang baru
kelihatan di HP kelas bawah, yang notabene target real user app ini.

## 2. Jalankan

```bash
flutter test integration_test/ocr_pdf_perf_test.dart -d <device_id>
```

Test ini generate gambar sintetis (~2480x3508, mirip foto dokumen A4 kamera)
berisi teks rendered supaya OCR beneran punya kerjaan, lalu jalankan:
- Pipeline OCR (prepare+extract pipelined) untuk N = 10, 20, 30 halaman
- `generatePdf()` single-file untuk N = 10, 20, 30 halaman
- `generatePdfChunked()` untuk N = 30 (persis di `chunkPageThreshold`)

Setiap run mencetak laporan `PerfProbe` ke console (timing + RSS per
checkpoint) — **copy-paste output itu**, itu bahan analisis utamanya.

## 3. Cara baca laporan

Contoh format output:
```
── PerfProbe [OCR_pipeline_20pages] ──────────────────────────
total: 18420ms | peak RSS: 312.4MB (+142.1MB dari awal)
  [   850ms]   210.3MB (Δ40.0MB)  page 0: prepare done
  [  1620ms]   215.1MB (Δ44.8MB)  page 0: ocr done (1204 chars)
  ...
─────────────────────────────────────────────────
```

Yang perlu dicek:

**Untuk OCR pipeline:**
- **Scaling waktu**: bandingkan `total` di N=10 vs 20 vs 30. Kalau linear
  (mis. ~2x waktu di 2x halaman) → pipeline sehat. Kalau super-linear
  (mis. 3x+ waktu di 2x halaman) → ada kontensi (kemungkinan: MLKit
  recognizer instance shared jadi antrian, atau isolate `compute()` untuk
  prepare kehabisan isolate pool/CPU core di device).
- **Overlap prepare vs ocr**: jarak waktu antara `page i: prepare done` dan
  `page i: ocr done` dibanding jarak `page i-1: ocr done` ke `page i: prepare
  done` — kalau prepare halaman berikutnya BENERAN overlap, harusnya "page i
  prepare done" muncul tak lama setelah "page i-1: ocr done" (bukan nunggu
  penuh durasi prepare setelahnya). Buka juga Timeline view di DevTools
  (`flutter test` device masih bisa attach DevTools) buat lihat visual
  overlap-nya.
- **Peak RSS**: kalau naik terus tanpa plateau seiring N naik → ada leak
  (kandidat: `_preparedForOcrCache` yang menahan file path/reference makin
  banyak makin banyak halaman — ini EXPECTED karena cache memang menyimpan
  1 entry per halaman, tapi entry-nya cuma path String jadi harusnya kecil;
  kalau RSS naik jauh melebihi itu, curigai native MLKit buffer yang tidak
  dibebaskan antar `processImage()` call).

**Untuk PDF single-file (`generatePdf`):**
- Checkpoint `before pdf.save()` adalah **titik peak RAM** (closure
  `pw.Document` menahan semua halaman sampai situ — lihat komentar di kode).
  RSS di titik ini seharusnya naik proporsional dengan N, DIKALIKAN ukuran
  per-halaman dari `_pageBudgetTier()` (makin banyak halaman → tier makin
  agresif kompresinya → kenaikan per-halaman makin kecil, bukan flat).
- Bandingkan peak RSS N=10 vs N=30: kalau naik jauh lebih dari yang
  diprediksi tier (mis. 3x bukan ~2x karena tier N=30 sudah turun ke
  1280px/q70), berarti asumsi "ukuran tertahan per halaman turun seiring N"
  di komentar kode TIDAK match kenyataan di device — worth diselidiki lebih
  lanjut (kemungkinan encoder JPEG native menahan buffer tambahan yang
  tidak keitung di estimasi).

**Untuk PDF chunked (`generatePdfChunked`, N=30):**
- Checkpoint `chunk N done` — RSS di checkpoint SETELAH chunk 1 selesai vs
  RSS SETELAH chunk 2 selesai vs dst. Ini yang paling penting: kalau RSS
  terus naik dari chunk ke chunk (bukan plateau/turun), berarti klaim di
  komentar kode ("GC bebasin chunk sebelumnya sebelum chunk berikutnya
  mulai") **tidak terbukti** — kemungkinan penyebab: GC Dart tidak langsung
  jalan tanpa memory pressure trigger (normal — GC generational tidak selalu
  langsung collect meski referensi sudah lepas), atau ada referensi tak
  sengaja yang masih hidup.
  - Kalau ini terjadi: opsi lanjutan adalah panggil `await
    Future.delayed(Duration.zero)` + cek, atau (lebih robust) jalankan tiap
    chunk generation di isolate terpisah lewat `compute()` supaya memori
    chunk BENERAN dilepas ke OS saat isolate itu berakhir — bukan cuma
    "eligible for GC" di isolate utama.

## 4. Cross-check dengan ADB (opsional, tapi disarankan)

`ProcessInfo.currentRss` di Dart cuma dari sudut pandang Dart VM. Untuk
verifikasi angka total proses Android (termasuk buffer native MLKit/JPEG
codec yang mungkin tidak sepenuhnya tercermin), jalankan paralel:

```bash
# cari package name & PID
adb shell pidof com.yourcompany.docscan
# pantau tiap beberapa detik selama test jalan
watch -n 2 'adb shell dumpsys meminfo <pid> | head -30'
```

Bandingkan angka `TOTAL PSS` dari `dumpsys meminfo` dengan `peak RSS` dari
laporan `PerfProbe` di waktu yang sama — kalau selisihnya besar, artinya
sebagian besar overhead memori ada di native (bukan tertangkap oleh
`ProcessInfo.currentRss`), yang mengarahkan investigasi ke sisi MLKit/JPEG
codec native, bukan ke kode Dart.

## 5. Setelah dapat angka

Kirim balik output `flutter test` (atau screenshot DevTools Timeline +
Memory view) — dari situ saya bisa bantu:
- Tentukan apakah OCR pipeline butuh batching lebih lanjut (mis. windowed
  pipeline 2-3 halaman look-ahead alih-alih 1) atau limitasi jumlah isolate
  concurrent.
- Tentukan apakah `chunkPageThreshold` (saat ini 30) perlu diturunkan, atau
  `generatePdfChunked` perlu isolate-per-chunk kalau plateau tidak terbukti.
- Tentukan apakah `_pageBudgetTier` perlu tier tambahan/lebih agresif untuk
  dokumen sangat panjang (50+ halaman).
