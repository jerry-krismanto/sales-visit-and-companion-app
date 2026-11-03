import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/form_options.dart';
import '../services/erp_api.dart';
import 'login_screen.dart';
import 'search_picker_screen.dart';

class VisitFormScreen extends StatefulWidget {
  const VisitFormScreen({super.key});

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

  FormOptions? _options;
  String? _loadError;

  String _jenis = 'Existing';
  PickItem? _target;
  bool _loadingDetails = false;
  String? _tujuan, _priority, _kota;
  String? _targetError, _tujuanError;

  bool get _isExisting => _jenis == 'Existing';
  List<String> get _typeText => _isExisting ? _existingText : _leadText;

  @override
  void initState() {
    super.initState();
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

  void _sessionExpired(SessionExpiredException e) {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.message)));
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
      final details = jenis == 'Existing'
          ? await ErpApi.instance.getCustomerDetails(item.value)
          : await ErpApi.instance.getLeadDetails(item.value);
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

  // ---------- submit (part 1: preview only) ----------

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

  void _onNext() {
    setState(() {
      _targetError = _target == null
          ? (_isExisting ? 'Pilih customer' : 'Pilih lead')
          : null;
      _tujuanError = _tujuan == null ? 'Pilih tujuan berkunjung' : null;
    });
    if (_targetError != null || _tujuanError != null) return;

    // Part 2 replaces this with GPS + photo + add_visit.
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payload (preview)'),
        content: SingleChildScrollView(
          child: Text(
            const JsonEncoder.withIndent('  ').convert(_buildPayload()),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan kunjungan?'),
        content: const Text('Data yang sudah diisi akan hilang.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Lanjut Mengisi'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Batalkan'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _target == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Kunjungan Baru')),
        body: _buildBody(),
        bottomNavigationBar: _options == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: _loadingDetails ? null : _onNext,
                    child: const Text('Lanjut'),
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

    return ListView(
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
          onSelectionChanged: (s) => _switchJenis(s.first),
        ),
        const SizedBox(height: 16),
        _PickerField(
          label: _isExisting ? 'Customer *' : 'Lead *',
          value: _target?.label,
          errorText: _targetError,
          loading: _loadingDetails,
          onTap: _pickTarget,
        ),
        if (_target != null) ..._detailFields(),
      ],
    );
  }

  List<Widget> _detailFields() {
    final o = _options!;
    return [
      _section('Kunjungan'),
      _PickerField(
        label: 'Tujuan Berkunjung *',
        value: _tujuan,
        errorText: _tujuanError,
        onTap: () async {
          final v = await _pickOption('Tujuan Berkunjung', o.tujuan, _tujuan);
          if (v != null) {
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
            if (v != null) setState(() => _priority = v);
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
  final VoidCallback onTap;
  final String? errorText;
  final bool loading;

  @override
  Widget build(BuildContext context) {
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
            suffixIcon: loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.arrow_drop_down),
          ),
          child: Text(value ?? ''),
        ),
      ),
    );
  }
}