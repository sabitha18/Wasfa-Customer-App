/// Small helpers for defensively parsing backend JSON.
///
/// The Postman collection documents most endpoints' shapes only in prose
/// (e.g. "Returns { total, page, per_page, pages, items[] }"), not with full
/// example bodies. These helpers accept a list of *candidate* keys so a
/// model still parses correctly if the backend uses `name_en`/`nameEn` or
/// `product_id`/`id`, etc. Once you've hit the real endpoint and confirmed
/// exact field names (the same way the Rider app's shapes were confirmed
/// from live logcat output), trim each list down to the one true key.
library json_utils;

dynamic _firstPresent(Map<String, dynamic> json, List<String> keys) {
  for (final k in keys) {
    if (json.containsKey(k) && json[k] != null) return json[k];
  }
  return null;
}

String asString(Map<String, dynamic> json, List<String> keys, {String fallback = ''}) {
  final v = _firstPresent(json, keys);
  return v?.toString() ?? fallback;
}

String? asStringOrNull(Map<String, dynamic> json, List<String> keys) {
  final v = _firstPresent(json, keys);
  return v?.toString();
}

/// Like [asStringOrNull], but trimmed, with an empty value treated as absent.
/// Used for values that can legitimately arrive as a number OR text (a
/// banner's `link_ref`/`link_id` is a numeric id for categories/brands but a
/// SKU like "a16346" for products).
String? asNonEmptyStringOrNull(Map<String, dynamic> json, List<String> keys) {
  final s = asStringOrNull(json, keys)?.trim();
  return (s == null || s.isEmpty) ? null : s;
}

int asInt(Map<String, dynamic> json, List<String> keys, {int fallback = 0}) {
  final v = _firstPresent(json, keys);
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? fallback;
  return fallback;
}

int? asIntOrNull(Map<String, dynamic> json, List<String> keys) {
  final v = _firstPresent(json, keys);
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double asDouble(Map<String, dynamic> json, List<String> keys, {double fallback = 0}) {
  final v = _firstPresent(json, keys);
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

double? asDoubleOrNull(Map<String, dynamic> json, List<String> keys) {
  final v = _firstPresent(json, keys);
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

bool asBool(Map<String, dynamic> json, List<String> keys, {bool fallback = false}) {
  final v = _firstPresent(json, keys);
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return fallback;
}

List<dynamic> asList(Map<String, dynamic> json, List<String> keys) {
  final v = _firstPresent(json, keys);
  if (v is List) return v;
  return const [];
}
