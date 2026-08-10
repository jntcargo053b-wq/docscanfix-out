import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

// BUG (review UI: huruf tidak keliatan, tampilan tidak rapi): AppTheme.darkTheme
// sudah didefinisikan lengkap (warna, textTheme, appBarTheme, cardTheme, dst)
// tapi tidak pernah dipasang ke MaterialApp — jadi seluruh app jalan pakai
// ThemeData default Flutter (brightness terang). Banyak Scaffold di app ini
// explicitly set backgroundColor gelap (AppTheme.background/surface), tapi
// Text yang mengambil warna dari Theme.of(context).textTheme (bukan warna
// hardcoded) ikut default ThemeData terang → jadi teks gelap di atas
// background gelap = HURUF TIDAK KELIATAN. Komponen lain (AppBar, tombol,
// Card, Divider, SnackBar) juga tidak ikut styling custom (appBarTheme,
// elevatedButtonTheme, cardTheme, dividerTheme, snackBarTheme) sehingga
// tampilannya campur-aduk antara style default Material dan warna custom
// yang di-hardcode di sana-sini → TAMPILAN TIDAK RAPI.
// Fix: pasang AppTheme.darkTheme sebagai theme aplikasi.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
