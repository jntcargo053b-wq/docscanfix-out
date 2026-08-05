import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'dart:io';
import '../models/scanned_document.dart';
import '../services/document_storage_service.dart';
import '../services/scanner_service.dart';
import '../services/pdf_service.dart';
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
  final _pdfService = PdfService();
  List<ScannedDocument> _documents = [];
  List<ScannedDocument>? _cachedFilteredDocs;
  bool _isScanning = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  // FEATURE: mode pilih-banyak (multi-select) dari halaman list.
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isBulkSharing = false;
  bool _isBulkDeleting = false;

  // ── Debounce timer for search ──
  Timer? _searchDebounceTimer;
  static const Duration _searchDelay = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    final docs = await _storageService.loadDocuments();
    if (mounted) {
      setState(() {
        _documents = docs;
        _cachedFilteredDocs = null;
      });
    }
  }

  List<ScannedDocument> get _filteredDocs {
    if (_cachedFilteredDocs != null) return _cachedFilteredDocs!;
    if (_searchQuery.isEmpty) {
      _cachedFilteredDocs = _documents;
      return _documents;
    }
    final query = _searchQuery.toLowerCase();
    final filtered = _documents.where((doc) {
      return doc.title.toLowerCase().contains(query) ||
          (doc.extractedText?.toLowerCase().contains(query) ?? false);
    }).toList();
    _cachedFilteredDocs = filtered;
    return filtered;
  }

  void _onSearchChanged(String value) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDelay, () {
      setState(() {
        _searchQuery = value.trim();
        _cachedFilteredDocs = null;
      });
    });
  }

  // ── Mode pilih-banyak ──────────────────────────────────────────────────

  void _enterSelectionMode(String docId) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(docId);
    });
  }

  void _toggleSelect(String docId) {
    setState(() {
      if (_selectedIds.contains(docId)) {
        _selectedIds.remove(docId);
      } else {
        _selectedIds.add(docId);
      }
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  List<ScannedDocument> get _selectedDocs =>
      _documents.where((d) => _selectedIds.contains(d.id)).toList();

  Future<void> _shareSelectedAsImages() async {
    if (_isBulkSharing) return;
    setState(() => _isBulkSharing = true);
    try {
      final docs = _selectedDocs;
      final files = <XFile>[];
      for (final doc in docs) {
        files.addAll(
          doc.imagePaths
              .where((p) => File(p).existsSync())
              .map((p) => XFile(p, mimeType: 'image/jpeg')),
        );
      }

      if (files.isEmpty) {
        _showError('Tidak ada gambar yang tersedia dari dokumen terpilih');
        return;
      }

      await Share.shareXFiles(
        files,
        subject: '${docs.length} dokumen',
        text: '${docs.length} dokumen (${files.length} halaman total)',
      );
      if (mounted) _cancelSelection();
    } catch (e) {
      _showError('Gagal berbagi gambar: $e');
    } finally {
      if (mounted) setState(() => _isBulkSharing = false);
    }
  }

  Future<void> _shareSelectedAsPdf() async {
    if (_isBulkSharing) return;
    setState(() => _isBulkSharing = true);
    try {
      final docs = _selectedDocs;
      final files = <XFile>[];

      for (final doc in docs) {
        var pdfPath = doc.pdfPath ?? '';
        if (pdfPath.isEmpty || !File(pdfPath).existsSync()) {
          pdfPath = await _pdfService.generatePdf(
            title: doc.title,
            imagePaths: doc.imagePaths,
            extractedText: doc.extractedText,
          );
          final updated = doc.copyWith(pdfPath: pdfPath);
          await _storageService.updateDocument(updated);
        }
        files.add(XFile(pdfPath, mimeType: 'application/pdf'));
      }

      if (files.isEmpty) {
        _showError('Tidak ada PDF yang bisa dibagikan');
        return;
      }

      _storageService.invalidateCache();
      await Share.shareXFiles(
        files,
        subject: '${docs.length} dokumen',
        text: '${docs.length} dokumen sebagai PDF',
      );
      if (mounted) {
        setState(() => _cachedFilteredDocs = null);
        _cancelSelection();
      }
    } catch (e) {
      _showError('Gagal berbagi PDF: $e');
    } finally {
      if (mounted) setState(() => _isBulkSharing = false);
    }
  }

  void _showBulkShareSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Gap(16),
              Text(
                'Bagikan ${_selectedIds.length} Dokumen',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Gap(16),
              _BulkShareOption(
                icon: Icons.image_outlined,
                title: 'Bagikan sebagai Gambar',
                subtitle: 'Semua halaman digabung jadi satu kiriman',
                color: const Color(0xFF1E88E5),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareSelectedAsImages();
                },
              ),
              const Gap(8),
              _BulkShareOption(
                icon: Icons.picture_as_pdf_outlined,
                title: 'Bagikan sebagai PDF',
                subtitle: 'Ekspor lalu kirim semua sebagai file PDF',
                color: const Color(0xFFE53935),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareSelectedAsPdf();
                },
              ),
              const Gap(8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    if (_isBulkDeleting) return;
    final ids = _selectedIds.toList();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Dokumen?'),
        content: Text('${ids.length} dokumen akan dihapus permanen.'),
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

    if (confirm != true || !mounted) return;

    setState(() => _isBulkDeleting = true);
    try {
      await _storageService.deleteDocuments(ids);
      _storageService.invalidateCache();
      if (mounted) {
        setState(() => _cachedFilteredDocs = null);
        _cancelSelection();
      }
    } finally {
      if (mounted) setState(() => _isBulkDeleting = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.error),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _selectionMode ? _buildSelectionHeader() : _buildHeader(),
            _buildSearchBar(),
            Expanded(child: _buildDocumentList()),
          ],
        ),
      ),
      floatingActionButton: _selectionMode ? null : _buildFAB(),
    );
  }

  Widget _buildSelectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: _cancelSelection,
            icon: const Icon(Icons.close, color: AppTheme.textPrimary),
          ),
          Expanded(
            child: Text(
              '${_selectedIds.length} dipilih',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: (_isBulkSharing || _selectedIds.isEmpty)
                ? null
                : _showBulkShareSheet,
            icon: _isBulkSharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary),
                  )
                : const Icon(Icons.share_outlined, color: AppTheme.primary),
          ),
          IconButton(
            onPressed: (_isBulkDeleting || _selectedIds.isEmpty)
                ? null
                : _deleteSelected,
            icon: _isBulkDeleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.error),
                  )
                : const Icon(Icons.delete_outline, color: AppTheme.error),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Dokumen Saya',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Cari dokumen...',
          prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
          filled: true,
          fillColor: AppTheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildDocumentList() {
    final docs = _filteredDocs;
    if (docs.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_open_outlined,
        title: 'Belum ada dokumen',
        subtitle: 'Scan dokumen pertama Anda',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        return DocumentCard(
          key: ValueKey(doc.id),
          document: doc,
          isSelectionMode: _selectionMode,
          isSelected: _selectedIds.contains(doc.id),
          onLongPress: () {
            if (!_selectionMode) _enterSelectionMode(doc.id);
          },
          onSelectToggle: () => _toggleSelect(doc.id),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DocumentDetailScreen(document: doc),
              ),
            );
            _loadDocuments(); // refresh after detail
          },
          onDelete: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text('Hapus Dokumen?'),
                content: const Text('Dokumen akan dihapus permanen.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.error,
                    ),
                    child: const Text('Hapus'),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              await _storageService.deleteDocument(doc.id);
              _storageService.invalidateCache();
              if (mounted) {
                setState(() => _cachedFilteredDocs = null);
                _loadDocuments();
              }
            }
          },
        ).animate().fadeIn(duration: 300.ms, delay: (index * 50).ms);
      },
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton(
      onPressed: _isScanning
          ? null
          : () async {
              setState(() => _isScanning = true);
              final status = await Permission.camera.request();
              if (status.isGranted) {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ScanScreen()),
                );
                if (result == true) {
                  _loadDocuments();
                }
              } else {
                _showError('Izin kamera diperlukan');
              }
              if (mounted) setState(() => _isScanning = false);
            },
      backgroundColor: AppTheme.primary,
      child: _isScanning
          ? const CircularProgressIndicator(color: Colors.black)
          : const Icon(Icons.add),
    ).animate().scale(delay: 300.ms, curve: Curves.elasticOut);
  }
}

/// Tile opsi untuk bottom sheet bagikan gabungan (multi-select).
class _BulkShareOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _BulkShareOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        )),
                    const Gap(2),
                    Text(subtitle,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        )),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
