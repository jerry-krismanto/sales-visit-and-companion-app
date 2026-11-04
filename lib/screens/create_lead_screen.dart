import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/form_options.dart';
import '../services/erp_api.dart';
import '../widgets/form_widgets.dart';
import 'login_screen.dart';
import 'search_picker_screen.dart';

class CreateLeadScreen extends StatefulWidget {
  const CreateLeadScreen({super.key, this.initialName = ''});

  final String initialName;

  @override
  State<CreateLeadScreen> createState() => _CreateLeadScreenState();
}

class _CreateLeadScreenState extends State<CreateLeadScreen> {
  static const _textFields = [
    'company_name',
    'nama_pic',
    'whatsapp_no',
    'mobile_no',
    'social_media',
    'existing_syrup',
    'existing_powder',
    'existing_coffee_machine',
    'custom_source',
    'alamat',
  ];

  final _formKey = GlobalKey<FormState>();
  final _ctrl = <String, TextEditingController>{
    for (final f in _textFields) f: TextEditingController(),
  };

  FormOptions? _options;
  String? _loadError;

  bool _sameAsWa = true;
  String? _territory, _hotlist, _leadGroup, _leadChannel, _priority;
  DateTime? _nextContact;
  final _errors = <String, String?>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl['company_name']!.text = widget.initialName;
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

  bool _isUntouched() {
    for (final f in _textFields) {
      final text = _ctrl[f]!.text.trim();
      final initial = f == 'company_name' ? widget.initialName.trim() : '';
      if (text != initial) return false;
    }
    return _territory == null &&
        _hotlist == null &&
        _leadGroup == null &&
        _leadChannel == null &&
        _priority == null &&
        _nextContact == null;
  }

  // ---------- pickers ----------

  Future<String?> _searchLocal(String hint, List<String> options) async {
    final item = await Navigator.of(context).push<PickItem>(
      MaterialPageRoute(
        builder: (_) => SearchPickerScreen(
          hint: hint,
          search: localSearch(options),
        ),
      ),
    );
    return item?.value;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextContact ?? today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _nextContact = picked;
        _errors['next_contact'] = null;
      });
    }
  }

  // ---------- validation ----------

  String? Function(String?) _required(String label) =>
      (v) => (v == null || v.trim().isEmpty) ? '$label wajib diisi' : null;

  String? _phone(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'Wajib diisi';
    if (digits.length < 10) return 'Nomor tidak valid';
    return null;
  }

  // ---------- submit ----------

  Future<void> _submit() async {
    final textOk = _formKey.currentState!.validate();
    setState(() {
      _errors['territory'] = _territory == null ? 'Pilih kota' : null;
      _errors['hotlist'] = _hotlist == null ? 'Pilih hotlist' : null;
      _errors['lead_group'] = _leadGroup == null ? 'Pilih lead group' : null;
      _errors['lead_channel'] = _leadChannel == null ? 'Pilih lead channel' : null;
      _errors['next_contact'] = _nextContact == null ? 'Pilih tanggal' : null;
    });
    if (!textOk || _errors.values.any((e) => e != null)) return;

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        for (final f in _textFields) f: _ctrl[f]!.text.trim(),
      };
      if (_sameAsWa) payload['mobile_no'] = payload['whatsapp_no'];
      payload.addAll({
        'territory': _territory,
        'custom_hotlist': _hotlist,
        'custom_lead_group': _leadGroup,
        'custom_lead_channel': _leadChannel,
        'priority': _priority,
        'next_contact_date': DateFormat('yyyy-MM-dd').format(_nextContact!),
      });

      final item = await withRelogin(
        context,
        () => ErpApi.instance.createLead(payload),
      );
      if (mounted) Navigator.of(context).pop(item);
    } on SessionExpiredException catch (e) {
      _sessionExpired(e);
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Gagal Membuat Lead'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan lead baru?'),
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
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        final navigator = Navigator.of(context);
        if (_isUntouched() || await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Lead Baru')),
        body: _buildBody(),
        bottomNavigationBar: _options == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Simpan Lead'),
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

    final o = _options!;
    return AbsorbPointer(
      absorbing: _saving,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Usaha'),
            _text('company_name', 'Nama Usaha *',
                validator: _required('Nama usaha')),
            PickerField(
              label: 'Kota *',
              value: _territory,
              errorText: _errors['territory'],
              onTap: () async {
                final v = await _searchLocal('Cari kota...', o.kota);
                if (v != null && mounted) {
                  setState(() {
                    _territory = v;
                    _errors['territory'] = null;
                  });
                }
              },
            ),
            _text('alamat', 'Alamat', maxLines: 3),
            _section('PIC'),
            _text('nama_pic', 'Nama PIC *', validator: _required('Nama PIC')),
            _text('whatsapp_no', 'No WhatsApp *',
                keyboard: TextInputType.phone, validator: _phone),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('No HP sama dengan No WhatsApp'),
              value: _sameAsWa,
              onChanged: (v) => setState(() => _sameAsWa = v ?? true),
            ),
            if (!_sameAsWa)
              _text('mobile_no', 'No HP *',
                  keyboard: TextInputType.phone, validator: _phone),
            _text('social_media', 'Social Media *',
                validator: _required('Social media')),
            _section('Produk Existing'),
            _text('existing_syrup', 'Existing Syrup *',
                hint: 'Isi "-" bila tidak ada',
                validator: _required('Existing syrup')),
            _text('existing_powder', 'Existing Powder *',
                hint: 'Isi "-" bila tidak ada',
                validator: _required('Existing powder')),
            _text('existing_coffee_machine', 'Existing Coffee Machine *',
                hint: 'Isi "-" bila tidak ada',
                validator: _required('Existing coffee machine')),
            _section('Klasifikasi'),
            PickerField(
              label: 'Hotlist *',
              value: _hotlist,
              errorText: _errors['hotlist'],
              onTap: () async {
                final v = await pickOption(context, 'Hotlist', o.hotlist, _hotlist);
                if (v != null && mounted) {
                  setState(() {
                    _hotlist = v;
                    _errors['hotlist'] = null;
                  });
                }
              },
            ),
            PickerField(
              label: 'Lead Group *',
              value: _leadGroup,
              errorText: _errors['lead_group'],
              onTap: () async {
                final v = await _searchLocal('Cari lead group...', o.leadGroup);
                if (v != null && mounted) {
                  setState(() {
                    _leadGroup = v;
                    _errors['lead_group'] = null;
                  });
                }
              },
            ),
            PickerField(
              label: 'Lead Channel *',
              value: _leadChannel,
              errorText: _errors['lead_channel'],
              onTap: () async {
                final v =
                    await _searchLocal('Cari lead channel...', o.leadChannel);
                if (v != null && mounted) {
                  setState(() {
                    _leadChannel = v;
                    _errors['lead_channel'] = null;
                  });
                }
              },
            ),
            PickerField(
              label: 'Priority',
              value: _priority,
              onTap: () async {
                final v =
                    await pickOption(context, 'Priority', o.priority, _priority);
                if (v != null && mounted) setState(() => _priority = v);
              },
            ),
            _text('custom_source', 'Source Lead'),
            _section('Follow Up'),
            PickerField(
              label: 'Next Contact Date *',
              value: _nextContact == null
                  ? null
                  : DateFormat('d MMMM y', 'id_ID').format(_nextContact!),
              errorText: _errors['next_contact'],
              onTap: _pickDate,
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _text(
    String field,
    String label, {
    String? hint,
    TextInputType? keyboard,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _ctrl[field],
        keyboardType: maxLines > 1 ? TextInputType.multiline : keyboard,
        minLines: 1,
        maxLines: maxLines,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}