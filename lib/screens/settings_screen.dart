import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/document_storage_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.refreshVersion = 0});

  /// Changes when the retained tab is selected again by [AppShellScreen].
  final int refreshVersion;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = DocumentStorageService();
  int _documentCount = 0;
  int _pageCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshVersion != widget.refreshVersion) {
      _loadSummary();
    }
  }

  Future<void> _loadSummary() async {
    try {
      final documents = await _storage.loadDocuments();
      if (!mounted) return;
      setState(() {
        _documentCount = documents.length;
        _pageCount = documents.fold<int>(0, (sum, doc) => sum + doc.pageCount);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _showInfo(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Pengaturan'),
        backgroundColor: AppTheme.background,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withValues(alpha: 0.18),
                  AppTheme.primary.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.document_scanner_rounded,
                    color: Colors.white,
                    size: 29,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DocScan',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pindai, simpan, dan kelola dokumen.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _SectionHeading('Preferensi'),
          _SettingsTile(
            icon: Icons.palette_outlined,
            title: 'Tema aplikasi',
            subtitle: 'Terang • Biru',
            trailing: const Icon(Icons.check_circle, color: AppTheme.primary, size: 20),
            onTap: () => _showInfo(
              'Tema aplikasi',
              'DocScan saat ini menggunakan tema terang dengan aksen biru agar dokumen mudah dibaca.',
            ),
          ),
          _SettingsTile(
            icon: Icons.language_rounded,
            title: 'Bahasa',
            subtitle: 'Indonesia',
            onTap: () => _showInfo(
              'Bahasa',
              'Antarmuka saat ini tersedia dalam bahasa Indonesia.',
            ),
          ),
          const SizedBox(height: 18),
          const _SectionHeading('Penyimpanan'),
          _SettingsTile(
            icon: Icons.folder_outlined,
            title: 'Lokasi penyimpanan',
            subtitle: 'Penyimpanan internal aplikasi',
            onTap: () => _showInfo(
              'Lokasi penyimpanan',
              'Dokumen dan metadata disimpan di ruang penyimpanan internal aplikasi pada perangkat ini.',
            ),
          ),
          _SettingsTile(
            icon: Icons.inventory_2_outlined,
            title: 'Ringkasan dokumen',
            subtitle: _loading
                ? 'Memuat ringkasan...'
                : '$_documentCount dokumen • $_pageCount halaman',
            onTap: _loadSummary,
          ),
          const SizedBox(height: 18),
          const _SectionHeading('Privasi dan bantuan'),
          _SettingsTile(
            icon: Icons.lock_outline_rounded,
            title: 'Privasi dokumen',
            subtitle: 'Tentang penyimpanan di perangkat',
            onTap: () => _showInfo(
              'Privasi dokumen',
              'Dokumen yang dipindai disimpan di penyimpanan internal aplikasi. Pastikan perangkat Anda terlindungi dan ekspor dokumen hanya ke aplikasi atau orang yang Anda percaya.',
            ),
          ),
          _SettingsTile(
            icon: Icons.help_outline_rounded,
            title: 'Bantuan',
            subtitle: 'Cara memindai dan mengekspor dokumen',
            onTap: () => _showInfo(
              'Cara menggunakan DocScan',
              '1. Tekan Scan di Beranda.\n2. Ambil atau tambahkan halaman.\n3. Periksa hasil dan simpan.\n4. Buka detail dokumen untuk melihat OCR, berbagi, atau mengekspor PDF.',
            ),
          ),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            title: 'Tentang DocScan',
            subtitle: 'Versi 1.0.0',
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'DocScan',
              applicationVersion: '1.0.0',
              applicationIcon: const Icon(
                Icons.document_scanner_rounded,
                color: AppTheme.primary,
                size: 36,
              ),
              children: const [
                Text('Pindai, simpan, cari teks OCR, dan ekspor dokumen ke PDF.'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(
                const ClipboardData(text: 'DocScan • Versi 1.0.0'),
              );
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(content: Text('Info aplikasi disalin.')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Salin info aplikasi'),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'DocScan • 2026',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppTheme.textSecondary,
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
