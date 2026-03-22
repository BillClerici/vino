class ApiResponse<T> {
  final bool success;
  final T? data;
  final Map<String, dynamic> meta;
  final List<dynamic> errors;

  ApiResponse({
    required this.success,
    this.data,
    this.meta = const {},
    this.errors = const [],
  });

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) fromData,
  ) {
    return ApiResponse(
      success: json['success'] as bool? ?? false,
      data: json['data'] != null ? fromData(json['data']) : null,
      meta: json['meta'] as Map<String, dynamic>? ?? {},
      errors: json['errors'] as List<dynamic>? ?? [],
    );
  }
}

class PaginatedResponse<T> {
  final List<T> items;
  final int page;
  final int pageSize;
  final int total;

  PaginatedResponse({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  bool get hasMore => page * pageSize < total;

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromItem,
  ) {
    final meta = json['meta'] as Map<String, dynamic>? ?? {};
    final data = json['data'] as List<dynamic>? ?? [];
    return PaginatedResponse(
      items: data.map((e) => fromItem(e as Map<String, dynamic>)).toList(),
      page: meta['page'] as int? ?? 1,
      pageSize: meta['page_size'] as int? ?? 25,
      total: meta['total'] as int? ?? 0,
    );
  }
}
