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
    required this.tujuan,
    required this.priority,
    required this.kota,
    required this.hotlist,
    required this.leadGroup,
    required this.leadChannel,
  });

  final List<String> tujuan;
  final List<String> priority;
  final List<String> kota;
  final List<String> hotlist;
  final List<String> leadGroup;
  final List<String> leadChannel;

  factory FormOptions.fromJson(Map<String, dynamic> j) {
    List<String> list(String key) =>
        (j[key] as List? ?? []).map((e) => e.toString()).toList();
    return FormOptions(
      tujuan: list('tujuan_berkunjung'),
      priority: list('priority'),
      kota: list('kota'),
      hotlist: list('hotlist'),
      leadGroup: list('lead_group'),
      leadChannel: list('lead_channel'),
    );
  }
}