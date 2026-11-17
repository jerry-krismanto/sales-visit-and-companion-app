class PickItem {
  const PickItem({required this.value, required this.label, this.subtitle});

  final String value;
  final String label;
  final String? subtitle;

  factory PickItem.fromJson(Map<String, dynamic> j) => PickItem(
        value: j['value'],
        label: j['label'] ?? j['value'],
        subtitle: j['kota'],
      );
}

class FormOptions {
  FormOptions({
    required this.tipeKunjungan,
    required this.tujuan,
    required this.priority,
    required this.kota,
    required this.hotlist,
    required this.leadSource,
    required this.leadGroup,
    required this.leadChannel,
    required this.radiusM,
    required this.accuracySlackM,
    required this.pinMaxAccuracyM,
    required this.maxPhotos,
    required this.minPhotosCheckOut,
  });

  final List<String> tipeKunjungan;
  final List<String> tujuan;
  final List<String> priority;
  final List<String> kota;
  final List<String> hotlist;
  final List<String> leadSource;
  final List<String> leadGroup;
  final List<String> leadChannel;

  final double radiusM;
  final double accuracySlackM;
  final double pinMaxAccuracyM;

  final int maxPhotos;
  final int minPhotosCheckOut;

  factory FormOptions.fromJson(Map<String, dynamic> j) {
    List<String> list(String key) =>
        (j[key] as List? ?? []).map((e) => e.toString()).toList();

    final geo = Map<String, dynamic>.from(j['geofence'] as Map? ?? {});
    double numOr(String key, double fallback) =>
        (geo[key] as num?)?.toDouble() ?? fallback;

    final photos = Map<String, dynamic>.from(j['photos'] as Map? ?? {});

    return FormOptions(
      tipeKunjungan: list('tipe_kunjungan'),
      tujuan: list('tujuan_berkunjung'),
      priority: list('priority'),
      kota: list('kota'),
      hotlist: list('hotlist'),
      leadSource: list('lead_source'),
      leadGroup: list('lead_group'),
      leadChannel: list('lead_channel'),
      radiusM: numOr('radius_m', 100),
      accuracySlackM: numOr('accuracy_slack_m', 50),
      pinMaxAccuracyM: numOr('pin_max_accuracy_m', 50),
      maxPhotos: (photos['max'] as num?)?.toInt() ?? 4,
      minPhotosCheckOut: (photos['min_check_out'] as num?)?.toInt() ?? 2,
    );
  }
}