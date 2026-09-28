import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'gallery_screen.dart';
import 'home_screen.dart';
import 'search_documents_screen.dart';
import 'settings_screen.dart';

/// Main navigation for the DocScan experience.
/// The existing HomeScreen remains the source of truth for scan and document
/// actions; the shell adds dedicated Search, Gallery, and Settings destinations.
class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  int _selectedIndex = 0;
  int _refreshVersion = 0;

  List<Widget> get _screens => [
        const HomeScreen(),
        SearchDocumentsScreen(refreshVersion: _refreshVersion),
        GalleryScreen(refreshVersion: _refreshVersion),
        SettingsScreen(refreshVersion: _refreshVersion),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
            // IndexedStack keeps tab states alive. Bump this token whenever
            // Search/Gallery is selected so those screens reload persisted
            // documents after scans, edits, or deletions on another tab.
            if (index == 1 || index == 2) _refreshVersion++;
          });
        },
        backgroundColor: AppTheme.surface,
        indicatorColor: AppTheme.primary.withValues(alpha: 0.13),
        surfaceTintColor: Colors.transparent,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: 'Pencarian',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library_rounded),
            label: 'Galeri',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Pengaturan',
          ),
        ],
      ),
    );
  }
}
