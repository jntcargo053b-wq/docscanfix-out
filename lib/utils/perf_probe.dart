import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Utility profiling ringan untuk mengukur waktu & memori (RSS proses) per
/// tahap — dipakai untuk investigasi bottleneck OCR multi-halaman & PDF
/// generation (lihat PERF_PROFILING.md).
///
/// Dua sumber data yang dikombinasikan:
/// 1. `dart:developer` Timeline events (`Timeline.startSync`/`finishSync`)
///    — muncul di timeline DevTools, berguna untuk lihat konkurensi antar
///    tahap (mis. verifikasi prepare(i+1) benar-benar tumpang tindih
///    dengan ocr(i) di pipeline OCR).
/// 2. `ProcessInfo.currentRss` — resident set size TOTAL proses (Dart heap
///    + native heap, termasuk memori native MLKit/image codec yang TIDAK
///    kelihatan di Dart heap saja). Ini angka paling relevan untuk
///    pertanyaan "apakah bisa OOM di HP RAM rendah", dan bisa dibaca lewat
///    print() log biasa tanpa perlu DevTools nempel — jadi bisa dipakai di
///    integration_test yang jalan lewat `flutter test` di device/emulator.
///
/// PENTING: currentRss tersedia dari Dart SDK 2.15+ dan cuma akurat kalau
/// dijalankan native (device/emulator asli), BUKAN di web.
class PerfProbe {
  final String label;
  final List<_Checkpoint> _checkpoints = [];
  final int _startRss;
  final Stopwatch _stopwatch = Stopwatch()..start();

  PerfProbe(this.label)
      : _startRss = _safeRss() {
    developer.Timeline.startSync(label);
  }

  static int _safeRss() {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0; // platform tidak dukung (mis. web) — degradasi aman
    }
  }

  /// Catat satu titik ukur bernama (mis. nama halaman/tahap).
  void mark(String name) {
    final rss = _safeRss();
    _checkpoints.add(_Checkpoint(
      name: name,
      elapsedMs: _stopwatch.elapsedMilliseconds,
      rssBytes: rss,
      rssDeltaFromStartBytes: rss - _startRss,
    ));
    developer.Timeline.instantSync(name, arguments: {
      'elapsedMs': _stopwatch.elapsedMilliseconds,
      'rssMB': (rss / (1024 * 1024)).toStringAsFixed(1),
    });
  }

  /// Tutup probe, cetak laporan ringkas + kembalikan data mentah untuk
  /// diagregasi lintas-run (mis. bandingkan N=10 vs 20 vs 30 halaman).
  PerfReport finish() {
    developer.Timeline.finishSync();
    _stopwatch.stop();
    final peakRss = _checkpoints.isEmpty
        ? _startRss
        : _checkpoints.map((c) => c.rssBytes).reduce((a, b) => a > b ? a : b);
    final report = PerfReport(
      label: label,
      totalMs: _stopwatch.elapsedMilliseconds,
      startRssBytes: _startRss,
      peakRssBytes: peakRss,
      checkpoints: List.unmodifiable(_checkpoints),
    );
    if (kDebugMode) {
      // ignore: avoid_print
      print(report.formatted());
    }
    return report;
  }
}

class _Checkpoint {
  final String name;
  final int elapsedMs;
  final int rssBytes;
  final int rssDeltaFromStartBytes;
  _Checkpoint({
    required this.name,
    required this.elapsedMs,
    required this.rssBytes,
    required this.rssDeltaFromStartBytes,
  });
}

class PerfReport {
  final String label;
  final int totalMs;
  final int startRssBytes;
  final int peakRssBytes;
  final List<_Checkpoint> checkpoints;

  PerfReport({
    required this.label,
    required this.totalMs,
    required this.startRssBytes,
    required this.peakRssBytes,
    required this.checkpoints,
  });

  double get peakRssMB => peakRssBytes / (1024 * 1024);
  double get rssGrowthMB => (peakRssBytes - startRssBytes) / (1024 * 1024);

  String formatted() {
    final buf = StringBuffer();
    buf.writeln('── PerfProbe [$label] ──────────────────────────');
    buf.writeln('total: ${totalMs}ms | peak RSS: ${peakRssMB.toStringAsFixed(1)}MB '
        '(+${rssGrowthMB.toStringAsFixed(1)}MB dari awal)');
    for (final c in checkpoints) {
      buf.writeln('  [${c.elapsedMs.toString().padLeft(6)}ms] '
          '${(c.rssBytes / (1024 * 1024)).toStringAsFixed(1).padLeft(7)}MB '
          '(Δ${(c.rssDeltaFromStartBytes / (1024 * 1024)).toStringAsFixed(1)}MB)  ${c.name}');
    }
    buf.writeln('─────────────────────────────────────────────────');
    return buf.toString();
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'totalMs': totalMs,
        'peakRssMB': peakRssMB,
        'rssGrowthMB': rssGrowthMB,
        'checkpoints': checkpoints
            .map((c) => {
                  'name': c.name,
                  'elapsedMs': c.elapsedMs,
                  'rssMB': c.rssBytes / (1024 * 1024),
                })
            .toList(),
      };
}
