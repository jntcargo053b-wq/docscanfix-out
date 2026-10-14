# 📄 DocScan — Aplikasi Scanner Dokumen Flutter

Aplikasi Android untuk memindai dokumen dengan deteksi tepi/crop, OCR, PDF, penyimpanan lokal, dan berbagi file.

## Fitur

- 📷 **Scan Dokumen** — scanner native dengan deteksi tepi dan crop.
- 📑 **Multi-page Review** — tambah, hapus, dan tinjau halaman sebelum disimpan.
- 🔤 **OCR** — ekstraksi teks menggunakan Google ML Kit.
- ✨ **Tinjauan teks AI opsional** — mengirim teks OCR (bukan foto) ke endpoint backend tepercaya untuk mendapat saran perbaikan; hasil asli tidak otomatis diganti.
- 📄 **Export PDF** — generate PDF dari hasil scan.
- 🖼️ **Image Processing** — resize/enhance untuk kebutuhan OCR/PDF.
- 💾 **Local Storage** — metadata dan halaman dokumen dikelola oleh storage service.
- 📤 **Share/Open** — berbagi gambar/PDF dan membuka PDF dengan aplikasi eksternal.
- 📱 **Barcode** — tersedia melalui flow barcode yang sudah ada di aplikasi.

## Struktur Project Aktif

```text
lib/
├── main.dart
├── models/
│   └── scanned_document.dart
├── services/
│   ├── scanner_service.dart
│   ├── ocr_service.dart
│   ├── pdf_service.dart
│   ├── image_enhance_service.dart
│   ├── document_storage_service.dart
│   ├── document_search_service.dart
│   └── bulk_share_service.dart
├── screens/
│   ├── home_screen.dart
│   ├── document_detail_screen.dart
│   ├── image_editor_screen.dart
│   └── Scan/
│       ├── scan_screen.dart
│       ├── scan_controller.dart
│       ├── scan_body.dart
│       ├── barcode_scan_screen.dart
│       └── widgets/
│           ├── scan_loading_overlay.dart
│           ├── scan_ocr_section.dart
│           ├── scan_page_carousel.dart
│           ├── scan_title_input.dart
│           └── scan_action_buttons.dart
├── theme/
│   └── app_theme.dart
├── utils/
│   ├── file_hash.dart
│   └── perf_probe.dart
└── widgets/
    ├── document_card.dart
    ├── scan_preview.dart
    ├── bulk_progress_dialog.dart
    └── empty_state.dart
```

> File di luar flow aktif yang merupakan sisa implementasi lama dihapus untuk mencegah perubahan berikutnya diterapkan ke file yang salah.

## Persyaratan

- Flutter SDK dengan Dart SDK yang memenuhi constraint di `pubspec.yaml`.
- Android SDK / device API 21+
- Java 17 untuk build Android

## Menjalankan Project

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## Build APK

Debug:

```bash
flutter build apk --debug
```

Release:

```bash
flutter build apk --release
```

## Dependency Utama

| Package | Versi di project | Fungsi |
|---|---:|---|
| `cunning_document_scanner` | ^2.2.0 | Scanner dokumen native |
| `google_mlkit_text_recognition` | ^0.13.0 | OCR |
| `pdf` | ^3.11.0 | Generate PDF |
| `printing` | ^5.14.2 | PDF/print support |
| `image` | ^4.5.4 | Image processing |
| `image_picker` | ^1.1.2 | Import gambar |
| `saver_gallery` | ^3.0.10 | Simpan ke galeri |
| `permission_handler` | ^12.0.1 | Permission |
| `device_info_plus` | ^10.1.0 | Informasi device |
| `path_provider` | ^2.1.5 | Direktori aplikasi |
| `share_plus` | ^10.1.4 | Share file |
| `open_file` | ^3.5.10 | Membuka file eksternal |
| `flutter_animate` | ^4.5.2 | Animasi UI |
| `gap` | ^3.0.1 | Spacing |

## Integrasi AI OCR opsional (Hugging Face)

Fitur **Tinjau dengan AI** adalah lapisan tambahan; OCR Google ML Kit, penyimpanan, barcode, dan ekspor PDF tetap berjalan tanpa fitur ini. Untuk mencegah token rahasia tertanam di APK, aplikasi **tidak** memanggil Hugging Face dengan token langsung. Konfigurasikan endpoint backend milik Anda ketika build:

```bash
flutter build apk --release --dart-define=DOCSCAN_AI_OCR_ENDPOINT=https://YOUR-TRUSTED-BACKEND.example/api/ocr-review
```

Ganti URL contoh dengan endpoint HTTPS yang Anda kendalikan. Jika variabel tidak diatur, tombol AI tidak ditampilkan. Aplikasi mengirim `POST` JSON dengan bentuk `{"text":"...","language":"id","task":"review_ocr_text"}`. Backend harus memvalidasi permintaan, menyimpan token Hugging Face sebagai secret di server, dan mengembalikan JSON `{"text":"saran hasil tinjauan"}`. Timeout klien dibatasi; respons kosong/tidak valid dianggap gagal.

Sebelum mengirim, aplikasi meminta persetujuan setiap kali dan menjelaskan bahwa teks OCR akan dikirim ke endpoint tersebut. Foto, file gambar, database, dan metadata dokumen tidak dikirim oleh fitur ini. Hasil AI hanya ditampilkan sebagai saran yang dapat disalin; **teks OCR asli dan data yang disimpan tidak diubah**. Tinjau hasil AI sebelum menggunakannya karena model dapat mengubah angka atau menambahkan informasi yang keliru. Jangan gunakan endpoint yang tidak dipercaya untuk dokumen sensitif.

Endpoint ini adalah kontrak backend aplikasi, bukan URL Hugging Face langsung. Backend perlu meneruskan tugas ke model Hugging Face yang dipilih dan diuji, dengan instruksi agar tidak mengarang atau mengubah angka. Uji lisensi, bahasa Indonesia, akurasi, latensi, dan biaya model sebelum produksi.

## Android

Konfigurasi Android harus tetap mengikuti file Gradle yang ada di repository. Java target build menggunakan 17.

Scanner Android menggunakan `AndroidScannerMode.base` pada flow aktif.

## GitHub Actions

Workflow utama berada di:

```text
.github/workflows/build.yml
```

Pipeline melakukan:

1. checkout repository;
2. setup Java 17;
3. setup Flutter stable;
4. `flutter pub get`;
5. `flutter analyze`;
6. `flutter test`;
7. build APK debug pada pull request ke `build_branch`, push ke `build_branch`, atau manual run;
8. build APK release saat tag `v*` dibuat;
9. upload APK sebagai artifact.

Workflow hygiene juga menolak release keystore (`.jks`/`.keystore`) yang masuk repository.

## Alur Penggunaan

1. **Home** → mulai scan dokumen.
2. **Scan** → ambil satu atau beberapa halaman.
3. **Review** → tinjau hasil dan tambah/hapus halaman bila diperlukan.
4. **OCR** → teks diproses oleh service OCR.
5. **Simpan** → dokumen dan halaman disimpan melalui storage service.
6. **Detail** → lihat dokumen, OCR, dan export/share PDF.

## Catatan Maintenance

- Jangan menghidupkan kembali file legacy yang sudah dihapus jika tidak benar-benar diperlukan.
- Perubahan scanner harus dilakukan pada `lib/screens/Scan/` yang aktif.
- Jangan menyimpan `keystore.jks`, password signing, atau credential release di repository.
- Sebelum merge perubahan penting, jalankan `flutter analyze`, `flutter test`, dan `flutter build apk --debug`.
