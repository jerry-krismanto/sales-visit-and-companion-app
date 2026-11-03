class TodayReport {
  TodayReport({
    required this.salesPerson,
    required this.employeeName,
    required this.postingDate,
    required this.autoSubmitHour,
    this.report,
  });

  final String salesPerson;
  final String employeeName;
  final DateTime postingDate;
  final int autoSubmitHour;
  final DailyReport? report;

  String get cutoffLabel => '${autoSubmitHour.toString().padLeft(2, '0')}:00';

  factory TodayReport.fromJson(Map<String, dynamic> j) => TodayReport(
        salesPerson: j['sales_person'] ?? '',
        employeeName: j['employee_name'] ?? '',
        postingDate: DateTime.parse(j['posting_date']),
        autoSubmitHour: (j['auto_submit_hour'] as num?)?.toInt() ?? 18,
        report: j['report'] == null
            ? null
            : DailyReport.fromJson(Map<String, dynamic>.from(j['report'])),
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

  DateTime? get jam {
    final raw = data['jam_kunjungan'];
    return raw == null ? null : DateTime.tryParse(raw.toString());
  }
}