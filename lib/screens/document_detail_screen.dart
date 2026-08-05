import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/scanned_document.dart';
import '../services/document_storage_service.dart';
import '../services/pdf_service.dart';
import '../theme/app_theme.dart';
import '../widgets/image_grid.dart';

class DocumentDetailScreen extends StatefulWidget {
  final ScannedDocument document;
  const DocumentDetailScreen({super.key, required this.document});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  late ScannedDocument _doc;
  final _storageService = DocumentStorageService();
  final _pdfService = PdfService();
  bool _isSharing = false;
  bool _isExportingPdf = false;

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
  }

  // ── Share as Images ──────────────────────────────────────────────

  Future<void> _shareAsImages() async {
    // FIX: guard race condition — sebelumnya tidak ada, jadi tap cepat 2x
    // bisa memicu Share.shareXFiles() dobel sekaligus.
    if (_isSharing || _isExportingPdf) return;
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
        text: 'Dokumen: ${_doc.title}',
      );
    } catch (e) {
      _showError('Gagal berbagi gambar: $e');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  // ── Export as PDF ────────────────────────────────────────────────

  Future<void> _exportAsPdf() async {
    if (_isExportingPdf || _isSharing) return;
    setState(() => _isExportingPdf = true);
    try {
      String pdfPath;
      if (_doc.pdfPath != null && File(_doc.pdfPath!).existsSync()) {
        pdfPath = _doc.pdfPath!;
      } else {
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
        text: 'PDF: ${_doc.title}',
      );
    } catch (e) {
      _showError('Gagal mengekspor PDF: $e');
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.error),
    );
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_doc.title),
        backgroundColor: AppTheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: _isSharing ? null : _shareAsImages,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _isExportingPdf ? null : _exportAsPdf,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_doc.imagePaths.length} halaman',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ImageGrid(
                imagePaths: _doc.imagePaths,
                onTap: (index) {
                  // Navigasi ke fullscreen viewer jika ada
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
