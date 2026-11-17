class TodayReport {
  TodayReport({
    required this.salesPerson,
    required this.employeeName,
    required this.postingDate,
    this.report,
    this.openVisit,
    this.pendingReports = const [],
  });

  final String salesPerson;
  final String employeeName;
  final DateTime postingDate;
  final DailyReport? report;

  /// Checked in but not checked out yet (may belong to an earlier day's report).
  final OpenVisit? openVisit;

  /// Earlier days' drafts that were never submitted.
  final List<PendingReport> pendingReports;

  factory TodayReport.fromJson(Map<String, dynamic> j) => TodayReport(
        salesPerson: j['sales_person'] ?? '',
        employeeName: j['employee_name'] ?? '',
        postingDate: DateTime.parse(j['posting_date'].toString()),
        report: j['report'] == null
            ? null
            : DailyReport.fromJson(Map<String, dynamic>.from(j['report'])),
        openVisit: j['open_visit'] == null
            ? null
            : OpenVisit.fromJson(Map<String, dynamic>.from(j['open_visit'])),
        pendingReports: (j['pending_reports'] as List? ?? [])
            .map((p) => PendingReport.fromJson(Map<String, dynamic>.from(p)))
            .toList(),
      );
}

class OpenVisit {
  OpenVisit({required this.report, required this.postingDate, required this.visit});

  final String report;
  final DateTime postingDate;
  final Visit visit;

  factory OpenVisit.fromJson(Map<String, dynamic> j) => OpenVisit(
        report: j['report'],
        postingDate: DateTime.parse(j['posting_date'].toString()),
        visit: Visit(Map<String, dynamic>.from(j['visit'])),
      );
}

class PendingReport {
  PendingReport({
    required this.name,
    required this.postingDate,
    required this.visits,
    required this.hasOpenVisit,
  });

  final String name;
  final DateTime postingDate;
  final int visits;
  final bool hasOpenVisit;

  factory PendingReport.fromJson(Map<String, dynamic> j) => PendingReport(
        name: j['name'],
        postingDate: DateTime.parse(j['posting_date'].toString()),
        visits: (j['visits'] as num?)?.toInt() ?? 0,
        hasOpenVisit: j['has_open_visit'] == true,
      );
}

class DailyReport {
  DailyReport({
    required this.name,
    required this.docstatus,
    required this.isEditable,
    required this.visits,
  });

  final String name;
  final int docstatus;
  final bool isEditable;
  final List<Visit> visits;

  bool get isSubmitted => docstatus == 1;

  factory DailyReport.fromJson(Map<String, dynamic> j) => DailyReport(
        name: j['name'],
        docstatus: (j['docstatus'] as num).toInt(),
        isEditable: j['is_editable'] == true,
        visits: (j['kunjungan'] as List? ?? [])
            .map((v) => Visit(Map<String, dynamic>.from(v)))
            .toList(),
      );
}

class Visit {
  Visit(this.data);

  static const photoFields = [
    'screenshot',
    'screenshot_1',
    'screenshot_2',
    'screenshot_3',
  ];

  final Map<String, dynamic> data;

  String get name => data['name'];
  int get idx => (data['idx'] as num?)?.toInt() ?? 0;
  bool get isExisting => data['jenis_kunjungan'] == 'Existing';
  String get jenisLabel => isExisting ? 'Existing' : 'New Lead';

  String get title =>
      (isExisting
          ? data['fullname_customer'] ?? data['nama_customer']
          : data['fullname_lead'] ?? data['nama_lead']) ??
      '-';

  String? get tujuan => data['tujuan_berkunjung'];
  String? get kota => data['kota'];
  String? get group =>
      (isExisting ? data['customer_group'] : data['lead_group'])?.toString();

  DateTime? _dt(String key) {
    final raw = data[key];
    return raw == null ? null : DateTime.tryParse(raw.toString());
  }

  DateTime? get jam => _dt('jam_kunjungan');
  DateTime? get checkIn => _dt('check_in');
  DateTime? get checkOut => _dt('check_out');

  /// Visits saved before check in/out existed have no check_in, so they count as finished.
  bool get isOpen => checkIn != null && checkOut == null;

  /// One entry per photo slot (null = empty).
  List<String?> get photos => photoFields.map((f) {
        final v = data[f];
        return (v is String && v.isNotEmpty) ? v : null;
      }).toList();

  int get photoCount => photos.whereType<String>().length;
}