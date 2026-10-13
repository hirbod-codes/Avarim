int? asInt(Object? v) => (v as num?)?.toInt();

double? asDouble(Object? v) => (v as num?)?.toDouble();

List<String> asStrList(Object? v) => (v as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [];
