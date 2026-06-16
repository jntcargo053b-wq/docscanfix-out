import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import '../models/scanned_document.dart';
import '../services/document_storage_service.dart';
import '../services/scanner_service.dart';
import '../theme/app_theme.dart';
import '../widgets/document_card.dart';
import '../widgets/empty_state.dart';
import 'Scan/scan_screen.dart';
import 'document_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storageService = DocumentStorageService();
  List<ScannedDocument> _documents = [];
  List<ScannedDocument>? _cachedFilteredDocs;
  bool _isScanning = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  // ── Debounce timer for search ──
  Timer? _searchDebounceTimer;
  static const Duration _searchDelay = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    // Permission NOT requested here — only when scan button is pressed
    // This follows Android UX guidelines
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  /// Debounced search to avoid expensive filtering on every keystroke
  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDelay, () {
      setState(() {
        _searchQuery = _searchController.text;
        _cachedFilteredDocs = null; // Invalidate cache
      });
    });
  }

  /// Get filtered documents with caching
  List<ScannedDocument> _getFilteredDocs(List<ScannedDocument> docs) {
    if (_cachedFilteredDocs != null) return _cachedFilteredDocs!;

    if (_searchQuery.isEmpty) {
      _cachedFilteredDocs = docs;
      return docs;
    }

    final query = _searchQuery.toLowerCase();
    _cachedFilteredDocs = docs.where((d) {
      // Only search title by default for performance
      // Extracting full text search for every keystroke is expensive
      return d.title.toLowerCase().contains(query) ||
          (d.extractedText?.toLowerCase().contains(query) ?? false);
    }).toList();

    return _cachedFilteredDocs!;
  }

  /// Permission + Navigation
  Future<void> _openScanner() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);

    try {
      final granted = await ScannerService.ensureCameraPermission();
      if (!mounted) return;

      if (granted) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ScanScreen()),
        );
        if (result == true && mounted) {
          // Invalidate cache and reload
          _storageService.invalidateCache();
          setState(() {
            _cachedFilteredDocs = null;
          });
        }
        return;
      }

      final status = await Permission.camera.status;
      if (!mounted) return;
      _showPermissionDialog(permanent: status.isPermanentlyDenied);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _showPermissionDialog({required bool permanent}) {
    showDialog(
      context: context,
      barrierDismissible: !permanent,
      builder: (_) => AlertDialog(
        title: const Text('Izin Kamera Diperlukan'),
        content: Text(
          permanent
              ? 'Izin kamera ditolak permanen.\n\n'
                'Buka Pengaturan → Aplikasi → DocScan → '
                'Izin → aktifkan Kamera.'
              : 'DocScan butuh akses kamera untuk scan dokumen. '
                'Mohon izinkan akses kamera.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Nanti'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (permanent) {
                await openAppSettings();
              } else {
                await _openScanner();
              }
            },
            child: Text(permanent ? 'Buka Pengaturan' : 'Izinkan'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDocument(ScannedDocument doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Dokumen?'),
        content: Text('Dokumen "${doc.title}" akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await _storageService.deleteDocument(doc.id);
      _storageService.invalidateCache();
      setState(() {
        _cachedFilteredDocs = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildSearchBar(),
            Expanded(child: _buildDocumentList()),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DocScan',
                style: Theme.of(context).textTheme.displayMedium,
              ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1),
              FutureBuilder<List<ScannedDocument>>(
                future: _storageService.loadDocuments(),
                builder: (ctx, snapshot) => Text(
                  '${snapshot.data?.length ?? 0} dokumen tersimpan',
                  style: Theme.of(context).textTheme.bodyMedium,
                ).animate().fadeIn(delay: 100.ms),
              ),
            ],
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.settings_outlined,
                color: AppTheme.textSecondary, size: 20),
          ).animate().fadeIn(delay: 200.ms),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'Cari dokumen...',
            hintStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary, size: 20),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ).animate().fadeIn(delay: 150.ms),
    );
  }

  Widget _buildDocumentList() {
    return FutureBuilder<List<ScannedDocument>>(
      future: _storageService.loadDocuments(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          );
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text('Error loading documents'),
          );
        }

        _documents = snapshot.data ?? [];
        final filteredDocs = _getFilteredDocs(_documents);

        if (filteredDocs.isEmpty) {
          return EmptyState(
            isSearching: _searchQuery.isNotEmpty,
            onScanPressed: _openScanner,
            scanEnabled: !_isScanning,
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            _storageService.invalidateCache();
            setState(() {
              _cachedFilteredDocs = null;
            });
          },
          color: AppTheme.primary,
          backgroundColor: AppTheme.surface,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: filteredDocs.length,
            itemBuilder: (ctx, i) {
              final doc = filteredDocs[i];
              return DocumentCard(
                key: ValueKey(doc.id),
                document: doc,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DocumentDetailScreen(document: doc),
                    ),
                  );
                  if (mounted) {
                    _storageService.invalidateCache();
                    setState(() {
                      _cachedFilteredDocs = null;
                    });
                  }
                },
                onDelete: () => _deleteDocument(doc),
              ).animate().fadeIn(
                    delay: Duration(milliseconds: i * 60),
                    duration: 300.ms,
                  ).slideY(begin: 0.05);
            },
          ),
        );
      },
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: _isScanning ? null : _openScanner,
      backgroundColor: _isScanning ? AppTheme.surfaceLight : AppTheme.primary,
      foregroundColor: Colors.black,
      elevation: 4,
      icon: _isScanning
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.textSecondary,
              ),
            )
          : const Icon(Icons.document_scanner_outlined, size: 22),
      label: Text(
        _isScanning ? 'Membuka...' : 'Scan Dokumen',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: _isScanning ? AppTheme.textSecondary : Colors.black,
        ),
      ),
    ).animate().scale(delay: 300.ms, curve: Curves.elasticOut);
  }
}
