import 'dart:async';

import 'package:flutter/material.dart';

import '../models/scanned_document.dart';
import '../services/document_search_service.dart';
import '../services/document_storage_service.dart';
import '../theme/app_theme.dart';
import 'document_detail_screen.dart';

class SearchDocumentsScreen extends StatefulWidget {
  const SearchDocumentsScreen({super.key, this.refreshVersion = 0});

  /// Changes when the retained tab is selected again by [AppShellScreen].
  final int refreshVersion;

  @override
  State<SearchDocumentsScreen> createState() => _SearchDocumentsScreenState();
}

class _SearchDocumentsScreenState extends State<SearchDocumentsScreen> {
  final _storage = DocumentStorageService();
  final _queryController = TextEditingController();
  Timer? _debounce;
  List<ScannedDocument> _allDocuments = [];
  List<ScannedDocument> _results = [];
  bool _loading = true;
  int _generation = 0;
  DateTimeRange? _dateRange;
  DocumentSortOrder _sortOrder = DocumentSortOrder.newest;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SearchDocumentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshVersion != widget.refreshVersion) {
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final docs = await _storage.loadDocuments();
      if (!mounted) return;
      setState(() {
        _allDocuments = docs;
        _results = docs;
        _loading = false;
      });
      await _search(_queryController.text);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat dokumen: $error')),
      );
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(value));
    setState(() {});
  }

  Future<void> _search(String query) async {
    final generation = ++_generation;
    final result = await DocumentSearchService.filter(
      _allDocuments,
      query,
      startDate: _dateRange?.start,
      endDate: _dateRange?.end,
      sortOrder: _sortOrder,
    );
    if (!mounted || generation != _generation) return;
    setState(() => _results = result);
  }

  Future<void> _chooseDateRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _dateRange,
      helpText: 'Filter tanggal dokumen',
      saveText: 'Terapkan',
      cancelText: 'Batal',
      confirmText: 'Terapkan',
    );
    if (!mounted || selected == null) return;
    setState(() => _dateRange = selected);
    await _search(_queryController.text);
  }

  String _shortDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  Future<void> _openDocument(ScannedDocument document) async {
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
        title: const Text('Pencarian'),
        backgroundColor: AppTheme.background,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: TextField(
                controller: _queryController,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Cari judul atau teks OCR...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _queryController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Hapus pencarian',
                          onPressed: () {
                            _queryController.clear();
                            _search('');
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _chooseDateRange,
                    icon: const Icon(Icons.date_range_rounded, size: 18),
                    label: Text(_dateRange == null
                        ? 'Filter tanggal'
                        : '${_shortDate(_dateRange!.start)} – ${_shortDate(_dateRange!.end)}'),
                  ),
                  if (_dateRange != null) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Hapus filter tanggal',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() => _dateRange = null);
                        _search(_queryController.text);
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                  const Spacer(),
                  PopupMenuButton<DocumentSortOrder>(
                    tooltip: 'Urutkan dokumen',
                    initialValue: _sortOrder,
                    onSelected: (value) {
                      setState(() => _sortOrder = value);
                      _search(_queryController.text);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: DocumentSortOrder.newest,
                        child: Text('Terbaru'),
                      ),
                      PopupMenuItem(
                        value: DocumentSortOrder.oldest,
                        child: Text('Terlama'),
                      ),
                      PopupMenuItem(
                        value: DocumentSortOrder.title,
                        child: Text('Nama A–Z'),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sort_rounded, size: 20),
                          const SizedBox(width: 4),
                          Text(switch (_sortOrder) {
                            _DocumentSortOrder.newest => 'Terbaru',
                            _DocumentSortOrder.oldest => 'Terlama',
                            _DocumentSortOrder.title => 'Nama A–Z',
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? _EmptySearch(hasQuery: _queryController.text.trim().isNotEmpty)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final document = _results[index];
                            return Material(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                leading: Container(
                                  width: 44,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.description_outlined,
                                    color: AppTheme.primary,
                                  ),
                                ),
                                title: Text(
                                  document.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text(
                                  '${document.pageCount} halaman • ${document.formattedDate}'
                                  '${document.extractedText?.trim().isNotEmpty == true ? '\nTeks OCR tersedia' : ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _openDocument(document),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.search_off_rounded : Icons.manage_search_rounded,
              size: 48,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              hasQuery ? 'Dokumen tidak ditemukan' : 'Cari dokumen Anda',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              hasQuery
                  ? 'Coba kata kunci lain atau periksa teks OCR.'
                  : 'Pencarian mencakup judul dan teks hasil OCR.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
