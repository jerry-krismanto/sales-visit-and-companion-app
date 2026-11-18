import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../models/daily_report.dart';
import '../models/form_options.dart';
import '../services/erp_api.dart';
import '../services/location_service.dart';
import '../widgets/form_widgets.dart';
import '../widgets/visit_map_preview.dart';
import 'create_lead_screen.dart';
import 'login_screen.dart';
import 'search_picker_screen.dart';

class VisitFormResult {
  const VisitFormResult(this.report, this.message);

  final TodayReport report;
  final String message;
}

enum _Mode { create, open, edit, view }

class VisitFormScreen extends StatefulWidget {
  const VisitFormScreen({super.key, this.visit, this.readOnly = false});

  /// null = new visit (check in); otherwise an existing one.
  final Visit? visit;

  /// Only applies to checked-out visits; an open visit is always editable.
  final bool readOnly;

  @override
  State<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends State<VisitFormScreen> {
  static const _commonText = ['alamat', 'note'];
  static const _existingText = [
    'pic_customer',
    'no_telepon_pic_customer',
    'social_media_customer',
    'existing_syrup_customer',
    'existing_powder_customer',
    'existing_coffee_machine_customer',
  ];
  static const _leadText = [
    'pic_lead',
    'no_telepon_pic_lead',
    'social_media',
    'existing_syrup_lead',
    'existing_powder_lead',
    'existing_coffee_machine_lead',
  ];

  final _ctrl = <String, TextEditingController>{
    for (final f in [..._commonText, ..._existingText, ..._leadText])
      f: TextEditingController(),
  };

  /// Same ID for every retry of this check in, so the server can de-duplicate.
  final _clientVisitId = const Uuid().v4();

  FormOptions? _options;
  String? _loadError;

  Visit? _visit; // null until checked in
  String _jenis = 'Existing';
  PickItem? _target;
  String? _group; // customer/lead group, read-only
  bool _loadingDetails = false;
  bool _detailsLoaded = false;
  ({double lat, double lng})? _targetLocation;
  String? _tipe, _tujuan, _priority, _kota;
  XFile? _checkInPhoto;
  final _photoCache = <String, Future<Uint8List>>{};
  int? _busySlot;
  String? _targetError, _tipeError, _tujuanError, _photoError;
  Map<String, String?> _initial = const {};

  bool _saving = false;
  String _savingStep = '';

  _Mode get _mode {
    final v = _visit;
    if (v == null) return _Mode.create;
    if (v.isOpen) return _Mode.open;
    return widget.readOnly ? _Mode.view : _Mode.edit;
  }

  bool get _isNew => _mode == _Mode.create;
  bool get _isOpen => _mode == _Mode.open;
  bool get _isView => _mode == _Mode.view;
  bool get _isExisting => _jenis == 'Existing';
  String get _targetLabel => _isExisting ? 'customer' : 'lead';
  List<String> get _typeText => _isExisting ? _existingText : _leadText;

  @override
  void initState() {
    super.initState();
    final v = widget.visit;
    if (v != null) {
      _loadVisit(v);
      if (v.isOpen) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _loadTargetLocation());
      }
    }
    _loadOptions();
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fills the form from a saved visit (no setState; call inside one if needed).
  void _loadVisit(Visit v) {
    _visit = v;
    _jenis = v.isExisting ? 'Existing' : 'New Lead';
    _target = PickItem(
      value: (v.isExisting ? v.data['nama_customer'] : v.data['nama_lead']) ?? '',
      label: v.title,
    );
    _group = v.group;
    for (final f in [..._commonText, ..._typeText]) {
      _ctrl[f]!.text = v.data[f]?.toString() ?? '';
    }
    _tipe = v.data['tipe_kunjungan'];
    _tujuan = v.data['tujuan_berkunjung'];
    _kota = v.data['kota'];
    _priority = v.data['priority'];
    _initial = _snapshot();
  }

  Future<void> _loadOptions() async {
    setState(() => _loadError = null);
    try {
      final opts = await ErpApi.instance.getFormOptions();
      if (mounted) setState(() => _options = opts);
    } on SessionExpiredException catch (e) {
      _sessionExpired(e);
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  /// Open visit: fetch the customer/lead pin for the map and the check-out precheck.
  Future<void> _loadTargetLocation() async {
    final v = _visit;
    if (v == null) return;
    try {
      final d = await _withRelogin(() => v.isExisting
          ? ErpApi.instance.getCustomerDetails(v.data['nama_customer'])
          : ErpApi.instance.getLeadDetails(v.data['nama_lead']));
      if (!mounted) return;
      setState(() {
        _targetLocation = _parseLokasi(d['lokasi']);
        _detailsLoaded = true;
      });
    } on SessionExpiredException catch (e) {
      _sessionExpired(e);
    } catch (_) {
      // no map then; the server still checks the radius at check out
    }
  }

  ({double lat, double lng})? _parseLokasi(dynamic lokasi) {
    if (lokasi is Map &&
        lokasi['latitude'] is num &&
        lokasi['longitude'] is num) {
      return (
        lat: (lokasi['latitude'] as num).toDouble(),
        lng: (lokasi['longitude'] as num).toDouble(),
      );
    }
    return null;
  }

  Map<String, String?> _snapshot() => {
        for (final f in [..._commonText, ..._typeText]) f: _ctrl[f]!.text.trim(),
        'tipe_kunjungan': _tipe,
        'tujuan_berkunjung': _tujuan,
        'kota': _kota,
        'priority': _priority,
      };

  bool _hasChanges() {
    final now = _snapshot();
    return now.keys.any((k) => now[k] != _initial[k]);
  }

  // ---------- session handling ----------

  void _sessionExpired(SessionExpiredException e) {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.message)));
  }

  Future<T> _withRelogin<T>(Future<T> Function() action) =>
      withRelogin(context, action);

  // ---------- helpers ----------

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showError(
    String title,
    String message, {
    String? actionLabel,
    Future<bool> Function()? action,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          if (action != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                action();
              },
              child: Text(actionLabel ?? 'Buka Pengaturan'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String message, String confirmLabel,
      {String cancelLabel = 'Batal'}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// After a photo/save call on the open visit: refresh it, or leave if it's no longer open.
  void _applyOpenVisit(TodayReport r) {
    final ov = r.openVisit;
    if (ov != null && ov.visit.name == _visit?.name) {
      setState(() => _visit = ov.visit);
    } else {
      Navigator.of(context)
          .pop(VisitFormResult(r, 'Kunjungan sudah tidak berlangsung.'));
    }
  }

  // ---------- selection (before check in) ----------

  void _switchJenis(String jenis) {
    if (jenis == _jenis) return;
    setState(() {
      _jenis = jenis;
      _target = null;
      _group = null;
      _targetError = null;
      _detailsLoaded = false;
      _targetLocation = null;
      _kota = null;
      _priority = null;
      for (final f in [..._existingText, ..._leadText, 'alamat']) {
        _ctrl[f]!.clear();
      }
    });
  }

  Future<void> _pickTarget() async {
    final jenis = _jenis;
    final item = await Navigator.of(context).push<PickItem>(
      MaterialPageRoute(
        builder: (_) => SearchPickerScreen(
          hint: _isExisting ? 'Cari customer...' : 'Cari lead...',
          search: _isExisting
              ? ErpApi.instance.searchCustomers
              : ErpApi.instance.searchLeads,
          emptyText: _isExisting
              ? 'Customer tidak ditemukan.'
              : 'Lead tidak ditemukan.',
          createLabel: _isExisting ? null : 'Buat Lead Baru',
          onCreate: _isExisting ? null : _createLead,
        ),
      ),
    );
    if (item == null || !mounted) return;

    setState(() {
      _target = item;
      _group = null;
      _targetError = null;
      _detailsLoaded = false;
      _targetLocation = null;
      _loadingDetails = true;
    });
    try {
      final details = await _withRelogin(() => jenis == 'Existing'
          ? ErpApi.instance.getCustomerDetails(item.value)
          : ErpApi.instance.getLeadDetails(item.value));
      if (!mounted || jenis != _jenis || _target?.value != item.value) return;
      _applyDetails(details);
    } on SessionExpiredException catch (e) {
      _sessionExpired(e);
    } catch (e) {
      if (mounted) _showSnack('Gagal memuat detail: $e');
    } finally {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  Future<PickItem?> _createLead(String query) {
    return Navigator.of(context).push<PickItem>(
      MaterialPageRoute(builder: (_) => CreateLeadScreen(initialName: query)),
    );
  }

  void _applyDetails(Map<String, dynamic> d) {
    setState(() {
      for (final f in [..._typeText, 'alamat']) {
        _ctrl[f]!.text = d[f]?.toString() ?? '';
      }
      _group = (_isExisting ? d['customer_group'] : d['lead_group'])?.toString();
      final kota = d['kota'];
      _kota = (kota != null && _options!.kota.contains(kota)) ? kota : null;
      if (!_isExisting) {
        final p = d['priority'];
        _priority = (p != null && _options!.priority.contains(p)) ? p : null;
      }
      _targetLocation = _parseLokasi(d['lokasi']);
      _detailsLoaded = true;
    });
  }

  Future<void> _pickKota() async {
    final item = await Navigator.of(context).push<PickItem>(
      MaterialPageRoute(
        builder: (_) => SearchPickerScreen(
          hint: 'Cari kota...',
          search: localSearch(_options!.kota),
        ),
      ),
    );
    if (item != null && mounted) setState(() => _kota = item.value);
  }

  // ---------- photos ----------

  Future<XFile?> _capturePhoto() async {
    try {
      return await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 70,
        maxWidth: 1600,
        maxHeight: 1600,
      );
    } catch (e) {
      if (mounted) _showSnack('Kamera tidak dapat dibuka: $e');
      return null;
    }
  }

  Future<void> _takeCheckInPhoto() async {
    final photo = await _capturePhoto();
    if (photo != null && mounted) {
      setState(() {
        _checkInPhoto = photo;
        _photoError = null;
      });
    }
  }

  Future<void> _uploadPhoto(int slot) async {
    final photo = await _capturePhoto();
    if (photo == null || !mounted) return;

    setState(() {
      _busySlot = slot;
      _photoError = null;
    });
    try {
      final loc = await LocationService.getVisitLocation();
      final gps = {
        'latitude': loc.latitude,
        'longitude': loc.longitude,
        'gps_accuracy': loc.accuracy,
        'is_mock_location': loc.isMocked ? 1 : 0,
      };
      final r = await _withRelogin(
        () => ErpApi.instance.uploadVisitPhoto(_visit!.name, slot, photo.path, gps),
      );
      if (mounted) _applyOpenVisit(r);
    } on LocationException catch (e) {
      if (mounted) {
        await _showError(
          'Lokasi Tidak Tersedia',
          e.message,
          actionLabel: e.fixLabel,
          action: e.fix,
        );
      }
    } on SessionExpiredException catch (e) {
      _sessionExpired(e);
    } catch (e) {
      if (mounted) await _showError('Gagal Mengunggah Foto', e.toString());
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

  Future<void> _deletePhoto(int slot) async {
    final ok = await _confirm(
        'Hapus foto?', 'Foto ini akan dihapus dari kunjungan.', 'Hapus');
    if (!ok || !mounted) return;

    setState(() => _busySlot = slot);
    try {
      final r = await _withRelogin(
        () => ErpApi.instance.deleteVisitPhoto(_visit!.name, slot),
      );
      if (mounted) _applyOpenVisit(r);
    } on SessionExpiredException catch (e) {
      _sessionExpired(e);
    } catch (e) {
      if (mounted) await _showError('Gagal Menghapus Foto', e.toString());
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

  // ---------- payloads ----------

  Map<String, dynamic> _buildCheckInPayload() => {
        'jenis_kunjungan': _jenis,
        if (_isExisting)
          'nama_customer': _target!.value
        else
          'nama_lead': _target!.value,
        'tipe_kunjungan': _tipe,
        'tujuan_berkunjung': _tujuan,
        'kota': _kota,
        if (!_isExisting) 'priority': _priority,
        for (final f in [..._commonText, ..._typeText])
          f: _ctrl[f]!.text.trim(),
      };

  Map<String, dynamic> _editableFields() => {
        'tipe_kunjungan': _tipe,
        'tujuan_berkunjung': _tujuan,
        'kota': _kota,
        if (!_isExisting) 'priority': _priority,
        for (final f in [..._commonText, ..._typeText])
          f: _ctrl[f]!.text.trim(),
      };

  // ---------- geofence (phone-side precheck; the server repeats it) ----------

  /// Returns null to cancel, '' when no reason is needed, or the rep's reason
  /// for being outside the radius.
  Future<String?> _geofenceCheck(VisitLocation loc, {bool checkOut = false}) async {
    if (!_detailsLoaded) return ''; // let the server decide
    final opts = _options!;
    final label = _targetLabel;
    final target = _targetLocation;

    if (target != null) {
      final distance = Geolocator.distanceBetween(
        loc.latitude,
        loc.longitude,
        target.lat,
        target.lng,
      );
      final allowed =
          opts.radiusM + math.min(math.max(loc.accuracy, 0), opts.accuracySlackM);
      if (distance <= allowed) return '';
      if (!mounted) return null;
      return showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OutsideRadiusDialog(
          distance: distance,
          allowed: allowed,
          label: label,
          checkOut: checkOut,
        ),
      );
    }

    if (checkOut) return ''; // nothing to compare against

    // No location yet: this check in will pin it.
    if (loc.accuracy <= 0 || loc.accuracy > opts.pinMaxAccuracyM) {
      await _showError(
        'Sinyal GPS Kurang Akurat',
        'Lokasi $label belum tersimpan, dan akurasi GPS Anda '
            '±${loc.accuracy.round()} m (maksimal ±${opts.pinMaxAccuracyM.round()} m). '
            'Coba di luar ruangan atau dekat jendela, lalu coba lagi.',
      );
      return null;
    }
    if (!mounted) return null;
    final ok = await _confirm(
      'Simpan Lokasi ${label[0].toUpperCase()}${label.substring(1)}?',
      'Lokasi Anda saat ini akan disimpan sebagai lokasi ${_target!.label}. '
          'Kunjungan berikutnya akan dibandingkan dengan titik ini '
          '(radius ${opts.radiusM.round()} m).\n\n'
          'Pastikan Anda sedang berada di lokasi $label.',
      'Simpan',
    );
    return ok ? '' : null;
  }

  // ---------- check in ----------

  Future<void> _checkIn() async {
    setState(() {
      _targetError = _target == null
          ? (_isExisting ? 'Pilih customer' : 'Pilih lead')
          : null;
      _tipeError = _tipe == null ? 'Pilih tipe kunjungan' : null;
      _tujuanError = _tujuan == null ? 'Pilih tujuan berkunjung' : null;
      _photoError = _checkInPhoto == null ? 'Foto check in wajib diambil' : null;
    });
    if (_targetError != null ||
        _tipeError != null ||
        _tujuanError != null ||
        _photoError != null) {
      return;
    }

    setState(() {
      _saving = true;
      _savingStep = 'Mengambil lokasi...';
    });
    try {
      final loc = await LocationService.getVisitLocation();
      if (!mounted) return;
      final reason = await _geofenceCheck(loc);
      if (reason == null || !mounted) return;
      setState(() => _savingStep = 'Check in...');

      final payload = {
        ..._buildCheckInPayload(),
        'client_visit_id': _clientVisitId,
        'latitude': loc.latitude,
        'longitude': loc.longitude,
        'gps_accuracy': loc.accuracy,
        'is_mock_location': loc.isMocked ? 1 : 0,
        'device_rooted': loc.deviceRooted ? 1 : 0,
        if (reason.isNotEmpty) 'alasan_luar_radius': reason,
      };

      final report = await _withRelogin(
        () => ErpApi.instance.addVisit(payload, _checkInPhoto!.path),
      );
      if (!mounted) return;

      final ov = report.openVisit;
      if (ov == null) {
        Navigator.of(context).pop(VisitFormResult(report, 'Check in berhasil.'));
        return;
      }
      setState(() {
        _loadVisit(ov.visit); // switch to the open-visit screen
        _checkInPhoto = null;
        _targetLocation ??= (lat: loc.latitude, lng: loc.longitude); // just pinned
        _detailsLoaded = true;
      });
      _showSnack('Check in berhasil. Tambahkan foto, lalu tekan Check Out saat selesai.');
    } on LocationException catch (e) {
      await _showError(
        'Lokasi Tidak Tersedia',
        e.message,
        actionLabel: e.fixLabel,
        action: e.fix,
      );
    } on SessionExpiredException catch (e) {
      _sessionExpired(e);
    } catch (e) {
      if (mounted) await _showError('Gagal Check In', e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- check out ----------

  Future<void> _checkOut() async {
    final count = _visit!.photoCount;
    final min = _options!.minPhotosCheckOut;
    setState(() {
      _tipeError = _tipe == null ? 'Pilih tipe kunjungan' : null;
      _tujuanError = _tujuan == null ? 'Pilih tujuan berkunjung' : null;
      _photoError = count < min
          ? 'Minimal $min foto sebelum check out (sekarang $count).'
          : null;
    });
    if (_tipeError != null || _tujuanError != null || _photoError != null) return;

    setState(() {
      _saving = true;
      _savingStep = 'Mengambil lokasi...';
    });
    try {
      final loc = await LocationService.getVisitLocation();
      if (!mounted) return;
      final reason = await _geofenceCheck(loc, checkOut: true);
      if (reason == null || !mounted) return;
      setState(() => _savingStep = 'Check out...');

      final fields = {
        ..._editableFields(),
        'latitude': loc.latitude,
        'longitude': loc.longitude,
        'gps_accuracy': loc.accuracy,
        'is_mock_location': loc.isMocked ? 1 : 0,
        if (reason.isNotEmpty) 'alasan_luar_radius': reason,
      };
      final report = await _withRelogin(
        () => ErpApi.instance.checkOutVisit(_visit!.name, fields),
      );
      if (mounted) {
        Navigator.of(context).pop(VisitFormResult(report, 'Check out berhasil.'));
      }
    } on LocationException catch (e) {
      await _showError(
        'Lokasi Tidak Tersedia',
        e.message,
        actionLabel: e.fixLabel,
        action: e.fix,
      );
    } on SessionExpiredException catch (e) {
      _sessionExpired(e);
    } catch (e) {
      if (mounted) await _showError('Gagal Check Out', e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- save / delete ----------

  Future<void> _saveChanges() async {
    setState(() {
      _tipeError = _tipe == null ? 'Pilih tipe kunjungan' : null;
      _tujuanError = _tujuan == null ? 'Pilih tujuan berkunjung' : null;
    });
    if (_tipeError != null || _tujuanError != null) return;

    setState(() {
      _saving = true;
      _savingStep = 'Menyimpan...';
    });
    try {
      final report = await _withRelogin(
        () => ErpApi.instance.updateVisit(_visit!.name, _editableFields()),
      );
      if (!mounted) return;
      if (_isOpen) {
        _applyOpenVisit(report);
        if (mounted) {
          setState(() => _initial = _snapshot());
          _showSnack('Perubahan tersimpan.');
        }
      } else {
        Navigator.of(context).pop(VisitFormResult(report, 'Perubahan tersimpan.'));
      }
    } on SessionExpiredException catch (e) {
      _sessionExpired(e);
    } catch (e) {
      if (mounted) await _showError('Gagal Menyimpan', e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await _confirm(
      'Hapus kunjungan?',
      'Kunjungan ke ${_visit!.title} akan dihapus beserta semua fotonya.',
      'Hapus',
    );
    if (!ok || !mounted) return;

    setState(() {
      _saving = true;
      _savingStep = 'Menghapus...';
    });
    try {
      final report = await _withRelogin(
        () => ErpApi.instance.deleteVisit(_visit!.name),
      );
      if (mounted) {
        Navigator.of(context).pop(VisitFormResult(report, 'Kunjungan dihapus.'));
      }
    } on SessionExpiredException catch (e) {
      _sessionExpired(e);
    } catch (e) {
      if (mounted) await _showError('Gagal Menghapus', e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final String title = switch (_mode) {
      _Mode.create => 'Kunjungan Baru',
      _Mode.open => 'Kunjungan Berlangsung',
      _Mode.edit => 'Edit Kunjungan',
      _Mode.view => 'Detail Kunjungan',
    };

    return PopScope(
      canPop: _isView || (_isNew && _target == null && !_saving),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        if (_isOpen) {
          _showSnack('Kunjungan sedang berlangsung. Tekan Check Out untuk menyelesaikan.');
          return;
        }
        final navigator = Navigator.of(context);
        if (!_isNew && !_hasChanges()) {
          navigator.pop();
          return;
        }
        final leave = _isNew
            ? await _confirm('Batalkan kunjungan?',
                'Data yang sudah diisi akan hilang.', 'Batalkan',
                cancelLabel: 'Lanjut Mengisi')
            : await _confirm('Batalkan perubahan?',
                'Perubahan yang belum disimpan akan hilang.', 'Batalkan',
                cancelLabel: 'Lanjut Mengedit');
        if (leave) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !_isOpen,
          title: Text(title),
          actions: [
            if (_mode == _Mode.open || _mode == _Mode.edit)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Hapus',
                onPressed: (_saving || _busySlot != null) ? null : _delete,
              ),
          ],
        ),
        body: _buildBody(),
        bottomNavigationBar: _bottomBar(),
      ),
    );
  }

  Widget? _bottomBar() {
    if (_options == null || _isView) return null;

    final Widget child;
    if (_saving) {
      child = SizedBox(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(_savingStep),
          ],
        ),
      );
    } else if (_isNew) {
      child = FilledButton.icon(
        onPressed: _loadingDetails ? null : _checkIn,
        icon: const Icon(Icons.login),
        label: const Text('Check In'),
      );
    } else if (_isOpen) {
      final busy = _busySlot != null;
      child = Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : _saveChanges,
              child: const Text('Simpan'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: busy ? null : _checkOut,
              icon: const Icon(Icons.logout),
              label: const Text('Check Out'),
            ),
          ),
        ],
      );
    } else {
      child = FilledButton(
        onPressed: _saveChanges,
        child: const Text('Simpan Perubahan'),
      );
    }

    return SafeArea(
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _buildBody() {
    if (_options == null) {
      if (_loadError == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _loadOptions,
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    final showMap = (_isNew || _isOpen) && _detailsLoaded;

    return AbsorbPointer(
      absorbing: _saving || _isView,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'Existing',
                label: Text('Existing'),
                icon: Icon(Icons.store),
              ),
              ButtonSegment(
                value: 'New Lead',
                label: Text('New Lead'),
                icon: Icon(Icons.person_add_alt),
              ),
            ],
            selected: {_jenis},
            onSelectionChanged: _isNew ? (s) => _switchJenis(s.first) : null,
          ),
          const SizedBox(height: 16),
          PickerField(
            label: _isExisting ? 'Customer *' : 'Lead *',
            value: _target?.label,
            errorText: _targetError,
            loading: _loadingDetails,
            onTap: _isNew ? _pickTarget : null,
          ),
          if (_target != null)
            PickerField(
              label: _isExisting ? 'Customer Group' : 'Lead Group',
              value: _group,
              onTap: null, // read-only
            ),
          if (!_isNew) _visitInfo(),
          if (showMap) ...[
            const SizedBox(height: 8),
            VisitMapPreview(
              key: ValueKey('${_target?.value}-${_targetLocation != null}'),
              target: _targetLocation == null
                  ? null
                  : LatLng(_targetLocation!.lat, _targetLocation!.lng),
              targetLabel: _targetLabel,
              radiusM: _options!.radiusM,
              accuracySlackM: _options!.accuracySlackM,
            ),
          ],
          if (_target != null) ..._detailFields(),
        ],
      ),
    );
  }

  Widget _visitInfo() {
    final v = _visit!;
    final fmt = DateFormat.Hm();
    final checkIn = v.checkIn ?? v.jam;
    final acc = v.data['gps_accuracy'];
    final parts = [
      if (checkIn != null) 'Check in ${fmt.format(checkIn)}',
      if (v.checkOut != null) 'Check out ${fmt.format(v.checkOut!)}',
      if (acc is num && acc > 0) 'akurasi GPS ±${acc.round()} m',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join(' · '), style: Theme.of(context).textTheme.bodySmall);
  }

  String _photoTitle() {
    if (_isNew) return 'Foto Check In *';
    if (_isOpen) {
      return 'Foto Kunjungan (${_visit!.photoCount}/${_options!.maxPhotos}, '
          'minimal ${_options!.minPhotosCheckOut} untuk check out)';
    }
    return 'Foto Kunjungan';
  }

  List<Widget> _detailFields() {
    final o = _options!;
    return [
      _section(_photoTitle()),
      _isNew ? _checkInPhotoField() : _photoGrid(),
      _section('Kunjungan'),
      PickerField(
        label: 'Tipe Kunjungan *',
        value: _tipe,
        errorText: _tipeError,
        onTap: () async {
          final v = await pickOption(context, 'Tipe Kunjungan', o.tipeKunjungan, _tipe);
          if (v != null && mounted) {
            setState(() {
              _tipe = v;
              _tipeError = null;
            });
          }
        },
      ),
      PickerField(
        label: 'Tujuan Berkunjung *',
        value: _tujuan,
        errorText: _tujuanError,
        onTap: () async {
          final v = await pickOption(context, 'Tujuan Berkunjung', o.tujuan, _tujuan);
          if (v != null && mounted) {
            setState(() {
              _tujuan = v;
              _tujuanError = null;
            });
          }
        },
      ),
      if (!_isExisting)
        PickerField(
          label: 'Priority',
          value: _priority,
          onTap: () async {
            final v = await pickOption(context, 'Priority', o.priority, _priority);
            if (v != null && mounted) setState(() => _priority = v);
          },
        ),
      _text('note', 'Note (Keterangan Tambahan)', maxLines: 3),
      _section('Lokasi'),
      PickerField(label: 'Kota', value: _kota, onTap: _pickKota),
      _text('alamat', 'Alamat', maxLines: 3),
      _section('PIC'),
      _text(_isExisting ? 'pic_customer' : 'pic_lead', 'Nama PIC'),
      _text(
        _isExisting ? 'no_telepon_pic_customer' : 'no_telepon_pic_lead',
        _isExisting ? 'No Telepon PIC' : 'No WA PIC',
        keyboard: TextInputType.phone,
      ),
      _text(_isExisting ? 'social_media_customer' : 'social_media', 'Social Media'),
      _section('Produk Existing'),
      _text(
        _isExisting ? 'existing_syrup_customer' : 'existing_syrup_lead',
        'Existing Syrup',
      ),
      _text(
        _isExisting ? 'existing_powder_customer' : 'existing_powder_lead',
        'Existing Powder',
      ),
      _text(
        _isExisting
            ? 'existing_coffee_machine_customer'
            : 'existing_coffee_machine_lead',
        'Existing Coffee Machine',
      ),
    ];
  }

  Widget _photoErrorText() {
    if (_photoError == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 12),
      child: Text(
        _photoError!,
        style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
      ),
    );
  }

  Widget _checkInPhotoField() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_checkInPhoto == null)
            OutlinedButton.icon(
              onPressed: _takeCheckInPhoto,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Ambil Foto'),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(_checkInPhoto!.path),
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
            TextButton.icon(
              onPressed: _takeCheckInPhoto,
              icon: const Icon(Icons.refresh),
              label: const Text('Ambil Ulang'),
            ),
          ],
          _photoErrorText(),
          const SizedBox(height: 4),
          Text(
            'Foto tambahan bisa diambil setelah check in.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _photoGrid() {
    final photos = _visit!.photos;
    final slots = _isOpen
        ? List.generate(photos.length, (i) => i)
        : [for (var i = 0; i < photos.length; i++) if (photos[i] != null) i];

    if (slots.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text('Tidak ada foto.'),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 4 / 3,
            children: [for (final i in slots) _photoTile(i, photos[i])],
          ),
          _photoErrorText(),
        ],
      ),
    );
  }

  Widget _photoTile(int slot, String? url) {
    final theme = Theme.of(context);
    final busy = _busySlot == slot;
    final canChange = _isOpen && slot > 0 && _busySlot == null && !_saving;

    if (url == null) {
      return InkWell(
        onTap: canChange ? () => _uploadPhoto(slot) : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: busy
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_a_photo_outlined),
                      const SizedBox(height: 4),
                      Text('Tambah Foto', style: theme.textTheme.bodySmall),
                    ],
                  ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _serverImage(url),
          if (busy)
            Container(
              color: Colors.black38,
              child: const Center(child: CircularProgressIndicator()),
            ),
          if (slot == 0)
            Positioned(left: 6, top: 6, child: _badge('Check in', Icons.lock_outline)),
          if (canChange)
            Positioned(
              right: 0,
              top: 0,
              child: PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 4)],
                ),
                onSelected: (v) =>
                    v == 'retake' ? _uploadPhoto(slot) : _deletePhoto(slot),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'retake', child: Text('Ambil Ulang')),
                  PopupMenuItem(value: 'delete', child: Text('Hapus')),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _badge(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _serverImage(String url) {
    final theme = Theme.of(context);
    final future =
        _photoCache.putIfAbsent(url, () => ErpApi.instance.getFileBytes(url));
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snap) {
        if (snap.hasData) {
          return Image.memory(snap.data!, fit: BoxFit.cover);
        }
        return Container(
          color: theme.colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: snap.hasError
              ? const Icon(Icons.broken_image_outlined)
              : const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
        );
      },
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _text(String field, String label,
      {TextInputType? keyboard, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _ctrl[field],
        keyboardType: maxLines > 1 ? TextInputType.multiline : keyboard,
        minLines: 1,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// Outside the radius: explain, ask for a reason. Pops the reason, or null to cancel.
class _OutsideRadiusDialog extends StatefulWidget {
  const _OutsideRadiusDialog({
    required this.distance,
    required this.allowed,
    required this.label,
    required this.checkOut,
  });

  final double distance;
  final double allowed;
  final String label;
  final bool checkOut;

  @override
  State<_OutsideRadiusDialog> createState() => _OutsideRadiusDialogState();
}

class _OutsideRadiusDialogState extends State<_OutsideRadiusDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _reason.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Alasan wajib diisi');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.checkOut ? 'Check out' : 'Check in';
    return AlertDialog(
      title: const Text('Di Luar Radius'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Anda berada ${widget.distance.round()} m dari lokasi ${widget.label} '
              '(maksimal ${widget.allowed.round()} m). $action tetap bisa '
              'dilakukan, tapi akan ditandai untuk dicek supervisor.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Alasan *',
                hintText: 'Contoh: meeting di cafe lain',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Lanjutkan')),
      ],
    );
  }
}