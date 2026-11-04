import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/erp_api.dart';

/// Tappable field that looks like a dropdown. onTap == null shows it as locked.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.errorText,
    this.loading = false,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final String? errorText;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final Widget suffix;
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

/// Bottom sheet for short option lists (Tujuan, Priority, Hotlist).
Future<String?> pickOption(
  BuildContext context,
  String title,
  List<String> options,
  String? current,
) {
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

/// Runs [action]; if the session expired, asks for the password and retries once.
Future<T> withRelogin<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } on SessionExpiredException {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString('last_user');
    if (user == null || !context.mounted) rethrow;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReloginDialog(user: user),
    );
    if (ok != true) rethrow;
    return await action();
  }
}

class ReloginDialog extends StatefulWidget {
  const ReloginDialog({super.key, required this.user});

  final String user;

  @override
  State<ReloginDialog> createState() => _ReloginDialogState();
}

class _ReloginDialogState extends State<ReloginDialog> {
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
            'Data yang sudah diisi tidak hilang.',
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