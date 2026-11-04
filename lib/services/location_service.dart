import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:safe_device/safe_device.dart';

class LocationException implements Exception {
  LocationException(this.message, {this.fixLabel, this.fix});

  final String message;
  final String? fixLabel;
  final Future<bool> Function()? fix;

  @override
  String toString() => message;
}

class MockLocationException extends LocationException {
  MockLocationException()
      : super('Lokasi palsu (fake GPS) terdeteksi. '
            'Matikan aplikasi fake GPS, lalu coba lagi.');
}

class VisitLocation {
  const VisitLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.deviceRooted,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final bool deviceRooted;
}

class LocationService {
  static Future<VisitLocation> getVisitLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationException(
        'GPS tidak aktif. Aktifkan lokasi di HP Anda.',
        fixLabel: 'Aktifkan GPS',
        fix: Geolocator.openLocationSettings,
      );
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      throw LocationException('Izin lokasi diperlukan untuk mencatat kunjungan.');
    }
    if (perm == LocationPermission.deniedForever) {
      throw LocationException(
        'Izin lokasi ditolak. Izinkan akses lokasi di pengaturan aplikasi.',
        fixLabel: 'Buka Pengaturan',
        fix: Geolocator.openAppSettings,
      );
    }

    // Android 12+: the user may grant only "approximate" location (~km off)
    if (await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced) {
      throw LocationException(
        'Aplikasi hanya mendapat lokasi perkiraan. '
        'Aktifkan "Lokasi akurat" di pengaturan aplikasi.',
        fixLabel: 'Buka Pengaturan',
        fix: Geolocator.openAppSettings,
      );
    }

    final Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } on TimeoutException {
      throw LocationException(
        'Gagal mendapatkan lokasi. Pastikan sinyal GPS bagus, lalu coba lagi.',
      );
    }

    if (pos.isMocked) {
      throw MockLocationException();
    }

    var rooted = false;
    try {
      rooted = await SafeDevice.isJailBroken;
    } catch (_) {
      // flag only; never block on a failed check
    }

    return VisitLocation(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracy: pos.accuracy,
      deviceRooted: rooted,
    );
  }
}