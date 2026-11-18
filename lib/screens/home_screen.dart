import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/daily_report.dart';
import '../services/erp_api.dart';
import '../widgets/form_widgets.dart';
import 'login_screen.dart';
import 'visit_form_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final _dateFmt = DateFormat('EEEE, d MMMM y', 'id_ID');

  TodayReport? _today;
  String? _error;
  bool _loading = true;
  bool _formOpen = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _today == null;
      _error = null;
    });
    try {
      final today = await ErpApi.instance.getTodayReport();
      if (!mounted) return;
      setState(() => _today = today);
      _resumeOpenVisit();
    } on SessionExpiredException catch (e) {
      _goToLogin(e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A checked-in visit must be finished first, so jump straight back into it.
  void _resumeOpenVisit() {
    final ov = _today?.openVisit;
    if (ov == null || _formOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openVisitForm(ov.visit);
    });
  }

  void _goToLogin([String? message]) {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _logout() async {
    await ErpApi.instance.logout();
    _goToLogin();
  }

  Future<void> _openVisitForm([Visit? visit]) async {
    if (_formOpen) return;
    _formOpen = true;

    final editable = _today?.report?.isEditable ?? false;
    final result = await Navigator.of(context).push<VisitFormResult>(
      MaterialPageRoute(
        builder: (_) => VisitFormScreen(
          visit: visit,
          readOnly: visit != null && !visit.isOpen && !editable,
        ),
      ),
    );

    _formOpen = false;
    if (!mounted) return;

    if (result != null) {
      setState(() => _today = result.report);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
      _resumeOpenVisit();
    } else {
      _load();
    }
  }

  Future<void> _submitReport(String reportName, DateTime date) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit Laporan?'),
        content: Text(
          'Laporan ${_dateFmt.format(date)} akan disubmit. '
          'Setelah disubmit, laporan tidak bisa diubah lagi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final today = await withRelogin(
        context,
        () => ErpApi.instance.submitReport(reportName),
      );
      if (!mounted) return;
      setState(() => _today = today);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Laporan berhasil disubmit.')));
    } on SessionExpiredException catch (e) {
      _goToLogin(e.message);
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Gagal Submit Laporan'),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _today?.report;
    final canAdd = report != null &&
        report.isEditable &&
        _today?.openVisit == null &&
        !_submitting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Report Sales'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Keluar',
            onPressed: _logout,
          ),
        ],
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () => _openVisitForm(),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Tambah Kunjungan'),
            )
          : null,
      body: Column(
        children: [
          if (_submitting) const LinearProgressIndicator(),
          Expanded(
            child: AbsorbPointer(absorbing: _submitting, child: _buildBody()),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _today == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_today == null) {
      return _ErrorView(message: _error ?? '-', onRetry: _load);
    }

    final t = _today!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), // room for the FAB
        children: [
          for (final p in t.pendingReports) _pendingCard(p),
          if (t.report == null) ..._welcome(t) else ..._reportSection(t),
        ],
      ),
    );
  }

  Widget _pendingCard(PendingReport p) {
    final theme = Theme.of(context);
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Laporan ${_dateFmt.format(p.postingDate)} belum disubmit',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${p.visits} kunjungan'
              '${p.hasOpenVisit ? ' · ada kunjungan yang belum check out' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: p.hasOpenVisit
                    ? null
                    : () => _submitReport(p.name, p.postingDate),
                child: const Text('Submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _welcome(TodayReport t) {
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 32),
      Icon(Icons.storefront_outlined, size: 72, color: theme.colorScheme.primary),
      const SizedBox(height: 24),
      Text('Halo, ${t.employeeName}',
          textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(_dateFmt.format(t.postingDate),
          textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
      const SizedBox(height: 32),
      const Text('Belum ada kunjungan hari ini.', textAlign: TextAlign.center),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: () => _openVisitForm(),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Mulai Laporan Hari Ini'),
      ),
    ];
  }

  List<Widget> _reportSection(TodayReport t) {
    final theme = Theme.of(context);
    final report = t.report!;
    final hasOpen = t.openVisit != null;
    final canSubmit = !report.isSubmitted && report.visits.isNotEmpty && !hasOpen;

    final statusText = report.isSubmitted ? 'Submitted' : 'Draft';
    final statusColor = report.isSubmitted ? Colors.green : Colors.orange;

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _dateFmt.format(t.postingDate),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Chip(
                    label: Text(statusText),
                    labelStyle: TextStyle(color: statusColor),
                    side: BorderSide(color: statusColor),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${report.name} · ${report.visits.length} kunjungan',
                  style: theme.textTheme.bodySmall),
              if (!report.isSubmitted) ...[
                const SizedBox(height: 12),
                if (hasOpen)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Selesaikan kunjungan yang sedang berlangsung '
                      'sebelum submit laporan.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                FilledButton.icon(
                  onPressed: canSubmit
                      ? () => _submitReport(report.name, t.postingDate)
                      : null,
                  icon: const Icon(Icons.send),
                  label: const Text('Submit Laporan'),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      ...report.visits.map(
        (v) => _VisitCard(visit: v, onTap: () => _openVisitForm(v)),
      ),
    ];
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.visit, required this.onTap});

  final Visit visit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat.Hm();
    final start = visit.checkIn ?? visit.jam;
    final end = visit.checkOut;

    String? time;
    if (start != null) {
      if (visit.isOpen) {
        time = '${fmt.format(start)} – berlangsung';
      } else if (end != null) {
        time = '${fmt.format(start)}–${fmt.format(end)}';
      } else {
        time = fmt.format(start);
      }
    }

    final subtitle = [
      if (time != null) time,
      if (visit.tujuan != null) visit.tujuan!,
      if (visit.kota != null) visit.kota!,
    ].join(' · ');

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(child: Text('${visit.idx}')),
        title: Text(visit.title),
        subtitle: Text(subtitle.isEmpty ? '-' : subtitle),
        trailing: visit.isOpen
            ? Text('Berlangsung',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.orange.shade800))
            : Text(visit.jenisLabel, style: theme.textTheme.labelSmall),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Coba Lagi')),
          ],
        ),
      ),
    );
  }
}