import 'dart:async';

import 'package:flutter/material.dart';

import '../models/form_options.dart';

typedef PickerSearch = Future<List<PickItem>> Function(String txt);

/// Filters a local list (used for Kota).
PickerSearch localSearch(List<String> options) => (txt) async {
      final q = txt.toLowerCase();
      return options
          .where((o) => o.toLowerCase().contains(q))
          .take(50)
          .map((o) => PickItem(value: o, label: o))
          .toList();
    };

class SearchPickerScreen extends StatefulWidget {
  const SearchPickerScreen({
    super.key,
    required this.hint,
    required this.search,
    this.emptyText = 'Tidak ada data.',
    this.createLabel,
    this.onCreate,
  });

  final String hint;
  final PickerSearch search;
  final String emptyText;
  final String? createLabel;
  final Future<PickItem?> Function(String query)? onCreate;

  @override
  State<SearchPickerScreen> createState() => _SearchPickerScreenState();
}

class _SearchPickerScreenState extends State<SearchPickerScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<PickItem> _items = [];
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _run(value.trim()),
    );
  }

  Future<void> _run(String txt) async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.search(txt);
      if (mounted && id == _requestId) setState(() => _items = items);
    } catch (e) {
      if (mounted && id == _requestId) setState(() => _error = e.toString());
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final item = await widget.onCreate!(_ctrl.text.trim());
    if (item != null && mounted) Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: widget.hint,
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (widget.onCreate != null) ...[
            ListTile(
              leading: Icon(Icons.add_circle_outline,
                  color: Theme.of(context).colorScheme.primary),
              title: Text(
                widget.createLabel ?? 'Buat Baru',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              onTap: _create,
            ),
            const Divider(height: 1),
          ],
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_items.isEmpty) {
      return _loading ? const SizedBox() : Center(child: Text(widget.emptyText));
    }
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final item = _items[i];
        final sub = [
          if (item.value != item.label) item.value,
          if (item.subtitle != null) item.subtitle!,
        ].join(' · ');
        return ListTile(
          title: Text(item.label),
          subtitle: sub.isEmpty ? null : Text(sub),
          onTap: () => Navigator.pop(context, item),
        );
      },
    );
  }
}