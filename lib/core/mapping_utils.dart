Map<String, String> setOptionalMapping(
  Map<String, String> source, {
  required String key,
  required String? value,
}) {
  final next = Map<String, String>.from(source);
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    next.remove(key);
  } else {
    next[key] = normalized;
  }
  return next;
}
