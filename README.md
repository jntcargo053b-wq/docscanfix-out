# 📄 DocScan — Aplikasi Scanner Dokumen Flutter

Aplikasi Android untuk scan dokumen dengan fitur:
- 📷 **Kamera Scan** — Deteksi tepi dokumen otomatis
- ✂️ **Crop Perspektif** — Koreksi sudut dan perspektif otomatis
- 📑 **Export PDF** — Simpan dan bagikan sebagai PDF
- 🔤 **OCR** — Baca teks dari gambar menggunakan Google ML Kit

---

## 🗂️ Struktur Project

```
lib/
├── main.dart
├── models/
│   └── scanned_document.dart          # Model data dokumen
├── services/
│   ├── scanner_service.dart           # Kamera & scan dokumen
│   ├── ocr_service.dart               # Google ML Kit OCR
│   ├── pdf_service.dart               # Generate & share PDF
│   ├── image_enhance_service.dart     # Resize, enhance, thumbnail
│   ├── save_service.dart              # Simpan ke galeri
│   └── document_storage_service.dart  # Penyimpanan lokal (JSON)
├── screens/
│   ├── home_screen.dart               # Daftar dokumen
│   ├── document_detail_screen.dart    # Detail & OCR view
│   ├── image_editor_screen.dart       # Edit gambar
│   └── Scan/
│       ├── scan_screen.dart           # Entry point scan flow
│       ├── scan_controller.dart       # State & business logic
│       ├── scan_body.dart             # Layout utama scan review
│       └── widgets/
│           ├── scan_action_buttons.dart
│           ├── scan_loading_overlay.dart
│           ├── scan_ocr_section.dart
│           ├── scan_page_carousel.dart
│           └── scan_title_input.dart
├── theme/
│   └── app_theme.dart                 # Tema dark mode (Material 3)
└── widgets/
    ├── document_card.dart             # Kartu dokumen di list
    ├── scan_preview.dart              # Preview halaman scan
    └── empty_state.dart              # State kosong & action button
```

---

## 🚀 Setup & Build

### Prerequisites
- Flutter SDK >= 3.3.0
- Android Studio / VS Code
- Android device atau emulator (API 21+)

### Install & Jalankan
```bash
flutter pub get
flutter run

# Release APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## 📦 Dependencies

| Package | Versi | Fungsi |
|---------|-------|--------|
| `document_scanner_flutter` | ^0.4.0 | Deteksi tepi + crop perspektif |
| `google_mlkit_text_recognition` | ^0.15.1 | OCR teks dari gambar |
| `pdf` + `printing` | ^3.11.0 / ^5.14.2 | Generate & print PDF |
| `image` | ^4.5.4 | Resize & enhance gambar (isolate) |
| `image_picker` | ^1.2.1 | Pilih gambar dari galeri |
| `saver_gallery` | ^3.0.10 | Simpan gambar ke galeri Android |
| `permission_handler` | ^11.4.0 | Runtime permission kamera & storage |
| `device_info_plus` | ^10.1.0 | SDK version Android (tanpa shell) |
| `path_provider` | ^2.1.5 | Direktori dokumen & cache |
| `share_plus` | ^10.1.4 | Share file PDF |
| `open_file` | ^3.5.10 | Buka PDF di viewer eksternal |
| `flutter_animate` | ^4.5.2 | Animasi UI |
| `gap` | ^3.0.1 | Spacing widget |

---

## 🔧 Konfigurasi Android

`AndroidManifest.xml` sudah mencakup:
- `CAMERA`
- `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE`
- `READ_MEDIA_IMAGES` (Android 13+)
- `FOREGROUND_SERVICE_LOCATION`
- FileProvider untuk sharing file

| | |
|---|---|
| minSdkVersion | **21** (Android 5.0) |
| targetSdkVersion | **34** (Android 14) |

---

## 📱 Alur Penggunaan

1. **Home** → Tap "Scan Dokumen" (permission kamera diminta di sini)
2. **Scan** → Kamera terbuka, posisikan dokumen, otomatis crop perspektif
3. **Review** → Lihat hasil scan, tambah halaman jika perlu
4. **OCR** → Teks diekstrak otomatis di background (timeout 60 detik, partial result disimpan)
5. **Simpan** → Dokumen tersimpan ke penyimpanan lokal + galeri
6. **Detail** → Lihat semua halaman, salin teks, export/share PDF

---

## 🛠️ Troubleshooting

**Camera permission denied**
→ Izin diminta saat tombol Scan ditekan; jika ditolak permanen, buka Pengaturan → Aplikasi → DocScan → Izin → Kamera

**OCR tidak berfungsi**
→ ML Kit butuh koneksi internet untuk download model pertama kali
→ Google Play Services harus aktif di device

**PDF tidak bisa dibuka**
→ Install PDF viewer (Adobe Acrobat, Google PDF Viewer, dll)
