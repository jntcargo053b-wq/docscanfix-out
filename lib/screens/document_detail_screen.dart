import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../models/scanned_document.dart';
import '../services/pdf_service.dart';
import '../services/ocr_service.dart';
import '../services/document_storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/scan_preview.dart' show ActionButton;

class DocumentDetailScreen extends StatefulWidget {
  final ScannedDocument document;

  const DocumentDetailScreen({super.key, required this.document});

  @override
  State<DocumentDetailScreen> createState() =>
      _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _pdfService = PdfService();
  final _ocrService = OcrService();
  final _storageService = DocumentStorageService();

  late ScannedDocument _doc;
  bool _isExportingPdf = false;
  bool _isRunningOcr = false;
  bool _isSharing = false;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _exportPdf() async {
    // FIX: guard race condition — jangan jalankan jika sedang proses
    if (_isExportingPdf || _isSharing) return;
    setState(() => _isExportingPdf = true);
    try {
      String pdfPath = _doc.pdfPath ?? '';

      if (pdfPath.isEmpty || !File(pdfPath).existsSync()) {
        pdfPath = await _pdfService.generatePdf(
          title: _doc.title,
          imagePaths: _doc.imagePaths,
          extractedText: _doc.extractedText,
        );

        final updated = _doc.copyWith(pdfPath: pdfPath);
        await _storageService.updateDocument(updated);
        setState(() => _doc = updated);
      }

      await _pdfService.sharePdf(pdfPath, _doc.title);
    } catch (e) {
      _showError('Gagal export PDF: $e');
    } finally {
      setState(() => _isExportingPdf = false);
    }
  }

  Future<void> _openPdf() async {
    if (_doc.pdfPath == null) {
      await _exportPdf();
      return;
    }
    try {
      await _pdfService.openPdf(_doc.pdfPath!);
    } catch (e) {
      _showError('Gagal membuka PDF');
    }
  }

  Future<void> _runOcr() async {
    setState(() => _isRunningOcr = true);
    try {
      final text =
          await _ocrService.extractTextFromImages(_doc.imagePaths);
      final updated = _doc.copyWith(
        extractedText: text,
      );
      await _storageService.updateDocument(updated);
      setState(() {
        _doc = updated;
        _isRunningOcr = false;
      });
    } catch (e) {
      setState(() => _isRunningOcr = false);
      _showError('OCR gagal: $e');
    }
  }

  Future<void> _copyText() async {
    if (_doc.extractedText?.isNotEmpty ?? false) {
      await Clipboard.setData(ClipboardData(text: _doc.extractedText!));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Teks disalin ke clipboard ✓')),
        );
      }
    }
  }

  // ── Share feature ──────────────────────────────────────────────────────────

  void _showShareSheet() {
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
              // Handle bar
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
                'Bagikan Dokumen',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Gap(4),
              Text(
                _doc.title,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Gap(16),
              _ShareOption(
                icon: Icons.picture_as_pdf_outlined,
                title: 'Bagikan sebagai PDF',
                subtitle: 'Ekspor lalu kirim file PDF',
                color: const Color(0xFFE53935),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareAsPdf();
                },
              ),
              const Gap(8),
              _ShareOption(
                icon: Icons.image_outlined,
                title: 'Bagikan Gambar',
                subtitle: '${_doc.pageCount} halaman sebagai gambar',
                color: const Color(0xFF1E88E5),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareAsImages();
                },
              ),
              if (_doc.extractedText?.isNotEmpty ?? false) ...[
                const Gap(8),
                _ShareOption(
                  icon: Icons.text_snippet_outlined,
                  title: 'Bagikan Teks OCR',
                  subtitle: 'Kirim teks hasil pembacaan',
                  color: const Color(0xFF43A047),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareAsText();
                  },
                ),
              ],
              const Gap(8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareAsPdf() async {
    // FIX: guard race condition — jangan jalankan jika sedang export/share
    if (_isSharing || _isExportingPdf) return;
    setState(() => _isSharing = true);
    try {
      String pdfPath = _doc.pdfPath ?? '';

      if (pdfPath.isEmpty || !File(pdfPath).existsSync()) {
        pdfPath = await _pdfService.generatePdf(
          title: _doc.title,
          imagePaths: _doc.imagePaths,
          extractedText: _doc.extractedText,
        );
        final updated = _doc.copyWith(pdfPath: pdfPath);
        await _storageService.updateDocument(updated);
        setState(() => _doc = updated);
      }

      await Share.shareXFiles(
        [XFile(pdfPath, mimeType: 'application/pdf')],
        subject: _doc.title,
        text: _doc.title,
      );
    } catch (e) {
      _showError('Gagal berbagi PDF: $e');
    } finally {
      setState(() => _isSharing = false);
    }
  }

  Future<void> _shareAsImages() async {
    setState(() => _isSharing = true);
    try {
      final existingFiles = _doc.imagePaths
          .where((p) => File(p).existsSync())
          .map((p) => XFile(p, mimeType: 'image/jpeg'))
          .toList();

      if (existingFiles.isEmpty) {
        _showError('Tidak ada gambar yang tersedia');
        return;
      }

      await Share.shareXFiles(
        existingFiles,
        subject: _doc.title,
        text: '${_doc.title} (${existingFiles.length} halaman)',
      );
    } catch (e) {
      _showError('Gagal berbagi gambar: $e');
    } finally {
      setState(() => _isSharing = false);
    }
  }

  Future<void> _shareAsText() async {
    if (_doc.extractedText?.isNotEmpty ?? false) {
      try {
        await Share.share(
          _doc.extractedText!,
          subject: _doc.title,
        );
      } catch (e) {
        _showError('Gagal berbagi teks: $e');
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: [
            Tab(
              icon: const Icon(Icons.image_outlined, size: 18),
              text: 'Halaman (${_doc.pageCount})',
            ),
            const Tab(
              icon: Icon(Icons.text_snippet_outlined, size: 18),
              text: 'Teks OCR',
            ),
          ],
        ),
        actions: [
          // Share button in AppBar
          IconButton(
            icon: _isSharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  )
                : const Icon(Icons.share_outlined),
            onPressed: _isSharing ? null : _showShareSheet,
            tooltip: 'Bagikan',
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _isExportingPdf ? null : _exportPdf,
            tooltip: 'Export PDF',
          ),
        ],
      ),
      body: Column(
        children: [
          // Action Buttons
          _buildActionBar(),
          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPagesTab(),
                _buildOcrTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          ActionButton(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Export PDF',
            isLoading: _isExportingPdf,
            onTap: _exportPdf,
          ),
          const Gap(8),
          ActionButton(
            icon: Icons.open_in_new_outlined,
            label: 'Buka PDF',
            onTap: _openPdf,
            color: AppTheme.surfaceLight,
            textColor: AppTheme.textPrimary,
          ),
          const Gap(8),
          ActionButton(
            icon: Icons.print_outlined,
            label: 'Print',
            onTap: () async {
              if (_doc.pdfPath != null) {
                await _pdfService.printPdf(_doc.pdfPath!, _doc.title);
              }
            },
            color: AppTheme.surfaceLight,
            textColor: AppTheme.textPrimary,
          ),
          const Gap(8),
          ActionButton(
            icon: Icons.share_outlined,
            label: 'Share',
            isLoading: _isSharing,
            onTap: _showShareSheet,
            color: AppTheme.primary.withValues(alpha: 0.15),
            textColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildPagesTab() {
    return Column(
      children: [
        // Large page viewer
        Expanded(
          flex: 3,
          child: PageView.builder(
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: _doc.imagePaths.length,
            itemBuilder: (ctx, i) {
              final path = _doc.imagePaths[i];
              final file = File(path);
              return Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: file.existsSync()
                      ? Image.file(file, fit: BoxFit.contain)
                      : Container(
                          color: AppTheme.surface,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined,
                                color: AppTheme.textSecondary, size: 48),
                          ),
                        ),
                ),
              );
            },
          ),
        ),
        // Page indicator
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Halaman ${_currentPage + 1} / ${_doc.pageCount}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        // Thumbnail strip
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _doc.imagePaths.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final isSelected = i == _currentPage;
              final file = File(_doc.imagePaths[i]);
              return GestureDetector(
                onTap: () => setState(() => _currentPage = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: file.existsSync()
                        ? Image.file(file, fit: BoxFit.cover)
                        : Container(color: AppTheme.surface),
                  ),
                ),
              );
            },
          ),
        ),
        const Gap(12),
      ],
    );
  }

  Widget _buildOcrTab() {
    final hasText =
        _doc.extractedText != null && _doc.extractedText!.isNotEmpty;

    if (_isRunningOcr) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            Gap(16),
            Text('Membaca teks...', style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    if (!hasText) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.text_fields, size: 64, color: AppTheme.textSecondary),
            const Gap(16),
            Text('Belum ada teks terdeteksi',
                style: Theme.of(context).textTheme.titleMedium),
            const Gap(8),
            Text('Jalankan OCR untuk membaca teks dari dokumen',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center),
            const Gap(24),
            ElevatedButton.icon(
              onPressed: _runOcr,
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Jalankan OCR'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Text stats bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppTheme.surface,
          child: Row(
            children: [
              _statChip('${_doc.extractedText!.split(' ').length} kata',
                  Icons.text_fields),
              const Gap(8),
              _statChip('${_doc.extractedText!.split('\n').length} baris',
                  Icons.format_list_bulleted),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy_outlined,
                    color: AppTheme.primary, size: 18),
                onPressed: _copyText,
                tooltip: 'Salin teks',
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined,
                    color: AppTheme.primary, size: 18),
                onPressed: _shareAsText,
                tooltip: 'Bagikan teks',
              ),
              IconButton(
                icon: const Icon(Icons.refresh_outlined,
                    color: AppTheme.textSecondary, size: 18),
                onPressed: _runOcr,
                tooltip: 'Ulang OCR',
              ),
            ],
          ),
        ),
        // Scrollable text
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              _doc.extractedText!,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                height: 1.7,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textSecondary),
          const Gap(4),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Share Option Tile ────────────────────────────────────────────────────────

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ShareOption({
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
