import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class VisitMapPreview extends StatefulWidget {
  const VisitMapPreview({
    super.key,
    required this.target,
    required this.targetLabel,
    required this.radiusM,
    required this.accuracySlackM,
  });

  /// Customer/lead location; null when not pinned yet.
  final LatLng? target;
  final String targetLabel;
  final double radiusM;
  final double accuracySlackM;

  @override
  State<VisitMapPreview> createState() => _VisitMapPreviewState();
}

class _VisitMapPreviewState extends State<VisitMapPreview> {
  final _map = MapController();
  StreamSubscription<Position>? _sub;
  Position? _pos;
  bool _mapReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _error = 'GPS tidak aktif.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _error = 'Izin lokasi diperlukan untuk menampilkan peta.');
        }
        return;
      }

      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        (p) {
          if (!mounted) return;
          setState(() {
            _pos = p;
            _error = null;
          });
          _fit();
        },
        onError: (_) {
          if (mounted) setState(() => _error = 'Lokasi tidak tersedia.');
        },
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'Lokasi tidak tersedia.');
    }
  }

  LatLng? get _me => _pos == null ? null : LatLng(_pos!.latitude, _pos!.longitude);

  double? get _distance {
    final me = _me, t = widget.target;
    if (me == null || t == null) return null;
    return Geolocator.distanceBetween(
        me.latitude, me.longitude, t.latitude, t.longitude);
  }

  double get _allowed =>
      widget.radiusM +
      math.min(math.max(_pos?.accuracy ?? 0, 0), widget.accuracySlackM);

  void _fit() {
    if (!_mapReady) return;
    final points = [if (_me != null) _me!, if (widget.target != null) widget.target!];
    if (points.isEmpty) return;
    if (points.length == 1) {
      _map.move(points.first, 17);
      return;
    }
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(48),
        maxZoom: 18,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final target = widget.target;
    final center = target ?? me;

    final distance = _distance;
    final Color zone;
    if (distance == null) {
      zone = Colors.grey;
    } else {
      zone = distance <= _allowed ? Colors.green : Colors.red;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 220,
            child: center == null
                ? _placeholder(context)
                : FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 17,
                      interactionOptions:
                          const InteractionOptions(flags: InteractiveFlag.none),
                      onMapReady: () {
                        _mapReady = true;
                        _fit();
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'id.co.delifru.sales_visit',
                      ),
                      CircleLayer(
                        circles: [
                          if (target != null)
                            CircleMarker(
                              point: target,
                              radius: widget.radiusM,
                              useRadiusInMeter: true,
                              color: zone.withValues(alpha: 0.15),
                              borderColor: zone,
                              borderStrokeWidth: 2,
                            ),
                          if (me != null && _pos!.accuracy > 0)
                            CircleMarker(
                              point: me,
                              radius: _pos!.accuracy,
                              useRadiusInMeter: true,
                              color: Colors.blue.withValues(alpha: 0.12),
                            ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          if (target != null)
                            Marker(
                              point: target,
                              width: 36,
                              height: 36,
                              alignment: Alignment.topCenter,
                              child: const Icon(Icons.location_on,
                                  color: Colors.red, size: 36),
                            ),
                          if (me != null)
                            Marker(
                              point: me,
                              width: 18,
                              height: 18,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                ),
                              ),
                            ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          color: Colors.white.withValues(alpha: 0.7),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          child: const Text(
                            '© OpenStreetMap contributors',
                            style: TextStyle(fontSize: 9, color: Colors.black87),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 6),
        _status(context, distance),
      ],
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: _error != null
          ? Text(_error!, textAlign: TextAlign.center)
          : const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Mencari lokasi Anda...'),
              ],
            ),
    );
  }

  Widget _status(BuildContext context, double? distance) {
    final theme = Theme.of(context);
    final label = widget.targetLabel;
    final acc = _pos?.accuracy;

    String text;
    Color color;
    if (_pos?.isMocked ?? false) {
      text = 'Lokasi palsu (fake GPS) terdeteksi.';
      color = Colors.red;
    } else if (_error != null) {
      text = _error!;
      color = theme.colorScheme.error;
    } else if (_pos == null) {
      text = 'Mencari lokasi Anda...';
      color = theme.colorScheme.onSurfaceVariant;
    } else if (widget.target == null) {
      text = 'Lokasi $label belum tersimpan. Titik biru akan menjadi '
          'lokasi $label saat kunjungan disimpan.';
      color = Colors.orange.shade800;
    } else if (distance! <= _allowed) {
      text = 'Anda ±${distance.round()} m dari lokasi $label, di dalam radius.';
      color = Colors.green.shade700;
    } else {
      text = 'Anda ±${distance.round()} m dari lokasi $label, di luar radius '
          '(maks ${_allowed.round()} m).';
      color = Colors.red;
    }
    if (acc != null && acc > 0 && !(_pos?.isMocked ?? false)) {
      text += ' Akurasi GPS ±${acc.round()} m.';
    }

    return Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color));
  }
}