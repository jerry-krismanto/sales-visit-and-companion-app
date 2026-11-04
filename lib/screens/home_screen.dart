import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/daily_report.dart';
import '../services/erp_api.dart';
import 'login_screen.dart';
import 'visit_form_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TodayReport? _today;
  String? _error;
  bool _loading = true;

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
      if (mounted) setState(() => _today = today);
    } on SessionExpiredException catch (e) {
      _goToLogin(e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  Future<void> _openVisitForm() async {
    final updated = await Navigator.of(context).push<TodayReport>(
      MaterialPageRoute(builder: (_) => const VisitFormScreen()),
    );
    if (updated != null && mounted) {
      setState(() => _today = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kunjungan tersimpan.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _today?.report;
    final canAdd = report != null && report.isEditable;

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
              onPressed: _openVisitForm,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Tambah Kunjungan'),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _today == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_today == null) {
      return _ErrorView(message: _error ?? '-', onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: _today!.report == null
          ? _WelcomeView(today: _today!, onStart: _openVisitForm)
          : _ReportView(today: _today!),
    );
  }
}

// ---------- welcome (no report yet) ----------

class _WelcomeView extends StatelessWidget {
  const _WelcomeView({required this.today, required this.onStart});

  final TodayReport today;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final closed = DateTime.now().hour >= today.autoSubmitHour;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 48),
        Icon(Icons.storefront_outlined, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        Text('Halo, ${today.employeeName}',
            textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(DateFormat('EEEE, d MMMM y', 'id_ID').format(today.postingDate),
            textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 32),
        Text(
          closed
              ? 'Laporan hari ini sudah ditutup (pukul ${today.cutoffLabel}).'
              : 'Belum ada kunjungan hari ini.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: closed ? null : onStart,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Mulai Laporan Hari Ini'),
        ),
      ],
    );
  }
}

// ---------- today's report ----------

class _ReportView extends StatelessWidget {
  const _ReportView({required this.today});

  final TodayReport today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = today.report!;

    final String statusText;
    final Color statusColor;
    if (report.isSubmitted) {
      statusText = 'Terkirim';
      statusColor = Colors.green;
    } else if (report.isEditable) {
      statusText = 'Draft';
      statusColor = Colors.orange;
    } else {
      statusText = 'Ditutup';
      statusColor = Colors.grey;
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), // room for the FAB
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('EEEE, d MMMM y', 'id_ID').format(today.postingDate),
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
                if (report.isEditable) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Laporan otomatis dikirim pukul ${today.cutoffLabel}.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...report.visits.map((v) => _VisitCard(visit: v)),
      ],
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.visit});

  final Visit visit;

  @override
  Widget build(BuildContext context) {
    final jam = visit.jam;
    final subtitle = [
      if (jam != null) DateFormat.Hm().format(jam),
      if (visit.tujuan != null) visit.tujuan!,
      if (visit.kota != null) visit.kota!,
    ].join(' · ');

    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${visit.idx}')),
        title: Text(visit.title),
        subtitle: Text(subtitle.isEmpty ? '-' : subtitle),
        trailing: Text(visit.jenisLabel,
            style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

// ---------- error ----------

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