import 'dart:io';

import 'package:flutter/material.dart';

import '../models/scanned_document.dart';
import '../services/document_storage_service.dart';
import '../theme/app_theme.dart';
import 'document_detail_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, this.refreshVersion = 0});

  /// Changes when the retained tab is selected again by [AppShellScreen].
  final int refreshVersion;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _storage = DocumentStorageService();
  List<ScannedDocument> _documents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GalleryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshVersion != widget.refreshVersion) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final docs = await _storage.loadDocuments();
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat galeri: $error')),
      );
    }
  }

  Future<void> _open(ScannedDocument document) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentDetailScreen(document: document),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Galeri Dokumen'),
        backgroundColor: AppTheme.background,
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _documents.isEmpty
              ? const _EmptyGallery()
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: _documents.length,
                  itemBuilder: (context, index) {
                    final document = _documents[index];
                    final thumbnail = document.thumbnailPath ??
                        (document.imagePaths.isNotEmpty
                            ? document.imagePaths.first
                            : null);
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _open(document),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.surfaceLight),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: thumbnail == null
                                  ? const _ImagePlaceholder()
                                  : Image.file(
                                      File(thumbnail),
                                      fit: BoxFit.cover,
                                      cacheWidth: 360,
                                      errorBuilder: (_, __, ___) =>
                                          const _ImagePlaceholder(),
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    document.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${document.pageCount} halaman • ${document.createdAt.day} '
                                    '${_month(document.createdAt.month)} '
                                    '${document.createdAt.year}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _month(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return months[month - 1];
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surfaceLight,
      child: const Center(
        child: Icon(
          Icons.description_outlined,
          size: 44,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined, size: 48, color: AppTheme.textSecondary),
            SizedBox(height: 12),
            Text('Galeri masih kosong'),
            SizedBox(height: 6),
            Text(
              'Dokumen yang Anda scan akan muncul di sini.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
