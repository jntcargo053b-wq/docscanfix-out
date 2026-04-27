# 📄 DocScan - Aplikasi Scanner Dokumen Flutter

Aplikasi Android untuk scan dokumen dengan fitur:
- 📷 **Kamera Scan** — Otomatis deteksi tepi dokumen
- ✂️ **Crop Perspektif** — Koreksi sudut dan perspektif otomatis
- 📑 **Export PDF** — Simpan dan bagikan sebagai PDF
- 🔤 **OCR (Text Recognition)** — Baca teks dari gambar menggunakan Google ML Kit

---

## 🗂️ Struktur Project

```
docscan/
├── lib/
│   ├── main.dart                    # Entry point
│   ├── theme/
│   │   └── app_theme.dart           # Tema dark mode
│   ├── models/
│   │   └── scanned_document.dart    # Model data dokumen
│   ├── services/
│   │   ├── scanner_service.dart     # Kamera & scan dokumen
│   │   ├── ocr_service.dart         # Google ML Kit OCR
│   │   ├── pdf_service.dart         # Generate & share PDF
│   │   └── document_storage_service.dart  # Simpan data lokal
│   ├── screens/
│   │   ├── home_screen.dart         # Daftar dokumen
│   │   ├── scan_screen.dart         # Proses scan & review
│   │   └── document_detail_screen.dart   # Detail & OCR view
│   └── widgets/
│       ├── document_card.dart       # Kartu dokumen di list
│       ├── scan_preview.dart        # Preview halaman scan
│       └── empty_state.dart         # State kosong & action button
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml      # Permissions kamera & storage
│       └── res/xml/file_paths.xml   # FileProvider paths
└── pubspec.yaml                     # Dependencies
```

---

## 🚀 Cara Setup & Build

### 1. Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) versi >= 3.0.0
- Android Studio / VS Code
- Android device atau emulator (API Level 21+)

### 2. Clone & Install Dependencies
```bash
cd docscan
flutter pub get
```

### 3. Jalankan di Device
```bash
# Debug mode
flutter run

# Release APK
flutter build apk --release

# File APK ada di:
# build/app/outputs/flutter-apk/app-release.apk
```

---

## 📦 Dependencies Utama

| Package | Fungsi |
|---------|--------|
| `cunning_document_scanner` | Deteksi tepi + crop perspektif otomatis |
| `google_mlkit_text_recognition` | OCR membaca teks dari gambar |
| `pdf` + `printing` | Generate & print PDF |
| `image_picker` | Pilih gambar dari galeri |
| `permission_handler` | Request permission kamera & storage |
| `share_plus` | Share file PDF |
| `flutter_animate` | Animasi UI |

---

## 🔧 Konfigurasi Android

### `AndroidManifest.xml` sudah include:
- `CAMERA` permission
- `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE`
- `READ_MEDIA_IMAGES` (Android 13+)
- FileProvider untuk sharing file

### Minimum SDK
- minSdkVersion: **21** (Android 5.0)
- targetSdkVersion: **34** (Android 14)

---

## 📱 Alur Penggunaan

1. **Home** → Tap tombol "Scan Dokumen"
2. **Scan** → Kamera terbuka, posisikan dokumen, otomatis crop perspektif
3. **Review** → Lihat hasil scan, tambah halaman jika perlu
4. **OCR** → Teks otomatis diekstrak dengan Google ML Kit
5. **Simpan** → Dokumen + PDF tersimpan di penyimpanan lokal
6. **Detail** → Lihat semua halaman, salin teks, export/share PDF

---

## 🛠️ Troubleshooting

**Camera permission denied:**
→ Pastikan permission di `AndroidManifest.xml` sudah benar
→ Coba uninstall + reinstall app

**OCR tidak berfungsi:**
→ Pastikan koneksi internet aktif saat pertama kali (ML Kit download model)
→ Google Play Services harus aktif di device

**PDF tidak bisa dibuka:**
→ Install PDF viewer di device (mis. Adobe Acrobat, Google PDF Viewer)

---

## 📋 Fitur yang Bisa Dikembangkan

- [ ] Cloud backup (Google Drive / Dropbox)
- [ ] Password protection dokumen
- [ ] Folder/kategori organisasi
- [ ] Berbagai bahasa OCR (Arabic, Chinese, dll)
- [ ] Signature/annotation pada PDF
- [ ] Dark/Light mode toggle
- [ ] Batch export multiple dokumen
