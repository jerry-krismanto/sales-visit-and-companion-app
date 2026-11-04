import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/daily_report.dart';
import '../models/form_options.dart';
import '../services/erp_api.dart';
import '../services/location_service.dart';
import 'login_screen.dart';
import 'search_picker_screen.dart';

class VisitFormResult {
  const VisitFormResult(this.report, this.message);

  final TodayReport report;
  final String message;
}

class VisitFormScreen extends StatefulWidget {
  const VisitFormScreen({super.key, this.visit, this.readOnly = false});

  /// null = new visit; otherwise view/edit an existing one.
  final Visit? visit;
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

  /// Same ID for every retry of this form, so the server can de-duplicate.
  final _clientVisitId = const Uuid().v4();

  FormOptions? _options;
  String? _loadError;

  String _jenis = 'Existing';
  PickItem? _target;
  bool _loadingDetails = false;
  String? _tujuan, _priority, _kota;
  XFile? _photo;
  Future<Uint8List>? _savedPhoto;
  String? _targetError, _tujuanError, _photoError;
  Map<String, String?> _initial = const {};

  bool _saving = false;
  String _savingStep = '';

  bool get _isNew => widget.visit == null;
  bool get _isExisting => _jenis == 'Existing';
  List<String> get _typeText => _isExisting ? _existingText : _leadText;

  @override
  void initState() {
    super.initState();
    final v = widget.visit;
    if (v != null) {
      _jenis = v.isExisting ? 'Existing' : 'New Lead';
      _target = PickItem(
        value: (v.isExisting ? v.data['nama_customer'] : v.data['nama_lead']) ?? '',
        label: v.title,
      );
      for (final f in [..._commonText, ..._typeText]) {
        _ctrl[f]!.text = v.data[f]?.toString() ?? '';
      }
      _tujuan = v.data['tujuan_berkunjung'];
      _kota = v.data['kota'];
      _priority = v.data['priority'];

      final shot = v.data['screenshot'];
      if (shot is String && shot.isNotEmpty) {
        _savedPhoto = ErpApi.instance.getFileBytes(shot);
      }
      _initial = _snapshot();
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

  Map<String, String?> _snapshot() => {
        for (final f in [..._commonText, ..._typeText]) f: _ctrl[f]!.text.trim(),
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

  /// Runs [action]; if the session expired, asks for the password and retries once.
  Future<T> _withRelogin<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SessionExpiredException {
      if (!await _relogin()) rethrow;
      return await action();
    }
  }

  Future<bool> _relogin() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString('last_user');
    if (user == null || !mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReloginDialog(user: user),
    );
    return ok == true;
  }

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

  // ---------- selection ----------

  void _switchJenis(String jenis) {
    if (jenis == _jenis) return;
    setState(() {
      _jenis = jenis;
      _target = null;
      _targetError = null;
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
        ),
      ),
    );
    if (item == null || !mounted) return;

    setState(() {
      _target = item;
      _targetError = null;
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

  void _applyDetails(Map<String, dynamic> d) {
    setState(() {
      for (final f in [..._typeText, 'alamat']) {
        _ctrl[f]!.text = d[f]?.toString() ?? '';
      }
      final kota = d['kota'];
      _kota = (kota != null && _options!.kota.contains(kota)) ? kota : null;
      if (!_isExisting) {
        final p = d['priority'];
        _priority = (p != null && _options!.priority.contains(p)) ? p : null;
      }
    });
  }

  Future<String?> _pickOption(
      String title, List<String> options, String? current) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final o in options)
              ListTile(
                title: Text(o),
                trailing: o == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, o),
              ),
          ],
        ),
      ),
    );
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

  Future<void> _takePhoto() async {
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 70,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (photo != null && mounted) {
        setState(() {
          _photo = photo;
          _photoError = null;
        });
      }
    } catch (e) {
      if (mounted) _showSnack('Kamera tidak dapat dibuka: $e');
    }
  }

  // ---------- new visit ----------

  Map<String, dynamic> _buildPayload() => {
        'jenis_kunjungan': _jenis,
        if (_isExisting)
          'nama_customer': _target!.value
        else
          'nama_lead': _target!.value,
        'tujuan_berkunjung': _tujuan,
        'kota': _kota,
        if (!_isExisting) 'priority': _priority,
        for (final f in [..._commonText, ..._typeText])
          f: _ctrl[f]!.text.trim(),
      };

  Future<void> _submit() async {
    setState(() {
      _targetError = _target == null
          ? (_isExisting ? 'Pilih customer' : 'Pilih lead')
          : null;
      _tujuanError = _tujuan == null ? 'Pilih tujuan berkunjung' : null;
      _photoError = _photo == null ? 'Foto kunjungan wajib diambil' : null;
    });
    if (_targetError != null || _tujuanError != null || _photoError != null) {
      return;
    }

    setState(() {
      _saving = true;
      _savingStep = 'Mengambil lokasi...';
    });
    try {
      final loc = await LocationService.getVisitLocation();
      if (!mounted) return;
      setState(() => _savingStep = 'Menyimpan kunjungan...');

      final payload = {
        ..._buildPayload(),
        'client_visit_id': _clientVisitId,
        'latitude': loc.latitude,
        'longitude': loc.longitude,
        'gps_accuracy': loc.accuracy,
        'is_mock_location': 0,
        'device_rooted': loc.deviceRooted ? 1 : 0,
      };

      final report = await _withRelogin(
        () => ErpApi.instance.addVisit(payload, _photo!.path),
      );
      if (mounted) {
        Navigator.of(context).pop(VisitFormResult(report, 'Kunjungan tersimpan.'));
      }
    } on MockLocationException catch (e) {
      await _showError('Fake GPS Terdeteksi', e.message);
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
      await _showError('Gagal Menyimpan', e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- edit / delete ----------

  Future<void> _saveChanges() async {
    setState(() {
      _tujuanError = _tujuan == null ? 'Pilih tujuan berkunjung' : null;
    });
    if (_tujuanError != null) return;

    setState(() {
      _saving = true;
      _savingStep = 'Menyimpan perubahan...';
    });
    try {
      final fields = <String, dynamic>{
        'tujuan_berkunjung': _tujuan,
        'kota': _kota,
        if (!_isExisting) 'priority': _priority,
        for (final f in [..._commonText, ..._typeText])
          f: _ctrl[f]!.text.trim(),
      };
      final report = await _withRelogin(
        () => ErpApi.instance.updateVisit(widget.visit!.name, fields),
      );
      if (mounted) {
        Navigator.of(context).pop(VisitFormResult(report, 'Perubahan tersimpan.'));
      }
    } on SessionExpiredException catch (e) {
      _sessionExpired(e);
    } catch (e) {
      await _showError('Gagal Menyimpan', e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await _confirm(
      'Hapus kunjungan?',
      'Kunjungan ke ${widget.visit!.title} akan dihapus beserta fotonya.',
      'Hapus',
    );
    if (!ok || !mounted) return;

    setState(() {
      _saving = true;
      _savingStep = 'Menghapus...';
    });
    try {
      final report = await _withRelogin(
        () => ErpApi.instance.deleteVisit(widget.visit!.name),
      );
      if (mounted) {
        Navigator.of(context).pop(VisitFormResult(report, 'Kunjungan dihapus.'));
      }
    } on SessionExpiredException catch (e) {
      _sessionExpired(e);
    } catch (e) {
      await _showError('Gagal Menghapus', e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final String title;
    if (_isNew) {
      title = 'Kunjungan Baru';
    } else if (widget.readOnly) {
      title = 'Detail Kunjungan';
    } else {
      title = 'Edit Kunjungan';
    }

    return PopScope(
      canPop: widget.readOnly || (_isNew && _target == null && !_saving),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
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
          title: Text(title),
          actions: [
            if (!_isNew && !widget.readOnly)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Hapus',
                onPressed: _saving ? null : _delete,
              ),
          ],
        ),
        body: _buildBody(),
        bottomNavigationBar: (_options == null || widget.readOnly)
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: (_loadingDetails || _saving)
                        ? null
                        : (_isNew ? _submit : _saveChanges),
                    child: _saving
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 12),
                              Text(_savingStep),
                            ],
                          )
                        : Text(_isNew ? 'Simpan Kunjungan' : 'Simpan Perubahan'),
                  ),
                ),
              ),
      ),
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

    return AbsorbPointer(
      absorbing: _saving || widget.readOnly,
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
          _PickerField(
            label: _isExisting ? 'Customer *' : 'Lead *',
            value: _target?.label,
            errorText: _targetError,
            loading: _loadingDetails,
            onTap: _isNew ? _pickTarget : null,
          ),
          if (!_isNew) _visitInfo(),
          if (_target != null) ..._detailFields(),
        ],
      ),
    );
  }

  Widget _visitInfo() {
    final v = widget.visit!;
    final jam = v.jam;
    final acc = v.data['gps_accuracy'];
    final parts = [
      if (jam != null) 'Waktu kunjungan ${DateFormat.Hm().format(jam)}',
      if (acc is num && acc > 0) 'akurasi GPS ±${acc.round()} m',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join(' · '), style: Theme.of(context).textTheme.bodySmall);
  }

  List<Widget> _detailFields() {
    final o = _options!;
    return [
      _section(_isNew ? 'Foto Kunjungan *' : 'Foto Kunjungan'),
      _isNew ? _photoField() : _savedPhotoField(),
      _section('Kunjungan'),
      _PickerField(
        label: 'Tujuan Berkunjung *',
        value: _tujuan,
        errorText: _tujuanError,
        onTap: () async {
          final v = await _pickOption('Tujuan Berkunjung', o.tujuan, _tujuan);
          if (v != null && mounted) {
            setState(() {
              _tujuan = v;
              _tujuanError = null;
            });
          }
        },
      ),
      if (!_isExisting)
        _PickerField(
          label: 'Priority',
          value: _priority,
          onTap: () async {
            final v = await _pickOption('Priority', o.priority, _priority);
            if (v != null && mounted) setState(() => _priority = v);
          },
        ),
      _text('note', 'Note (Keterangan Tambahan)', maxLines: 3),
      _section('Lokasi'),
      _PickerField(label: 'Kota', value: _kota, onTap: _pickKota),
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

  Widget _photoField() {
    final theme = Theme.of(context);
    if (_photo == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _takePhoto,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Ambil Foto'),
            ),
            if (_photoError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 12),
                child: Text(
                  _photoError!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(_photo!.path),
              height: 200,
              fit: BoxFit.cover,
            ),
          ),
          TextButton.icon(
            onPressed: _takePhoto,
            icon: const Icon(Icons.refresh),
            label: const Text('Ambil Ulang'),
          ),
        ],
      ),
    );
  }

  Widget _savedPhotoField() {
    final theme = Theme.of(context);
    if (_savedPhoto == null) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text('Tidak ada foto.'),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FutureBuilder<Uint8List>(
          future: _savedPhoto,
          builder: (context, snap) {
            if (snap.hasData) {
              return Image.memory(snap.data!, height: 200, fit: BoxFit.cover);
            }
            if (snap.hasError) {
              return Container(
                height: 200,
                color: theme.colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: const Text('Foto tidak dapat dimuat.'),
              );
            }
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          },
        ),
      ),
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

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.errorText,
    this.loading = false,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap; // null = locked
  final String? errorText;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final Widget? suffix;
    if (loading) {
      suffix = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (onTap == null) {
      suffix = const Icon(Icons.lock_outline, size: 18);
    } else {
      suffix = const Icon(Icons.arrow_drop_down);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          isEmpty: value == null,
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            border: const OutlineInputBorder(),
            suffixIcon: suffix,
          ),
          child: Text(value ?? ''),
        ),
      ),
    );
  }
}

class _ReloginDialog extends StatefulWidget {
  const _ReloginDialog({required this.user});

  final String user;

  @override
  State<_ReloginDialog> createState() => _ReloginDialogState();
}

class _ReloginDialogState extends State<_ReloginDialog> {
  final _pwd = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _pwd.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_pwd.text.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ErpApi.instance.login(widget.user, _pwd.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sesi Berakhir'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Masukkan password untuk melanjutkan. '
            'Data kunjungan Anda tidak hilang.',
          ),
          const SizedBox(height: 12),
          Text(widget.user, style: Theme.of(context).textTheme.bodySmall),
          TextField(
            controller: _pwd,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Password', errorText: _error),
            onSubmitted: (_) => _login(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _loading ? null : _login,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Masuk'),
        ),
      ],
    );
  }
}