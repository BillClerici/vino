class LookupValue {
  final String id;
  final String code;
  final String label;
  final int sortOrder;

  const LookupValue({
    required this.id,
    required this.code,
    required this.label,
    this.sortOrder = 0,
  });

  factory LookupValue.fromJson(Map<String, dynamic> json) {
    return LookupValue(
      id: json['id'] as String,
      code: json['code'] as String,
      label: json['label'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}
