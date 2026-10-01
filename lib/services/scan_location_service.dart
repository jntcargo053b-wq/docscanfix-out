import 'package:geolocator/geolocator.dart';

/// Snapshot lokasi opsional yang diambil setelah pemindaian berhasil.
/// Data ini disimpan bersama metadata dokumen, bukan ditulis ke piksel foto.
class ScanLocation {
  const ScanLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime capturedAt;
}

class ScanLocationService {
  /// Minta izin seperlunya dan ambil posisi terkini.
  /// Mengembalikan null jika layanan/izin tidak tersedia atau pengambilan
  /// gagal; kegagalan lokasi tidak boleh menggagalkan proses scan dokumen.
  Future<ScanLocation?> capture() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          !position.accuracy.isFinite ||
          position.latitude < -90 ||
          position.latitude > 90 ||
          position.longitude < -180 ||
          position.longitude > 180) {
        return null;
      }

      return ScanLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        capturedAt: position.timestamp,
      );
    } catch (_) {
      // GPS merupakan metadata tambahan; jangan menghalangi penyimpanan scan.
      return null;
    }
  }
}
