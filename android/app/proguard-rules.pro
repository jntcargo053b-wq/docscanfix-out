# ════════════════════════════════════════════════════
#  ProGuard / R8 Rules — DocScan
# ════════════════════════════════════════════════════

# ── Flutter ─────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ── ML Kit Text Recognition ─────────────────────────
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_latin.** { *; }
-dontwarn com.google.mlkit.**

# ── iTextG / PDF library ─────────────────────────────
-keep class com.itextpdf.** { *; }
-dontwarn com.itextpdf.**

# ── cunning_document_scanner (OpenCV) ───────────────
-keep class com.cunning.document.** { *; }
-dontwarn org.opencv.**

# ── Kotlin & Coroutines ──────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlin.**

# ── Gson / JSON (dipakai storage service) ────────────
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }

# ── FileProvider ─────────────────────────────────────
-keep class androidx.core.content.FileProvider { *; }
