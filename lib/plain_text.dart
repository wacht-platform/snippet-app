/// Inline Markdown reduced to plain text, for surfaces that cannot render it
/// (the notch, one-line banners).
String plainInline(String text) {
  var t = text;
  t = t.replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '');
  t = t.replaceAllMapped(RegExp(r'`+([^`]*)`+'), (m) => m[1] ?? '');
  t = t.replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m[2] ?? '');
  t = t.replaceAllMapped(
      RegExp(r'(?<![\w*])\*([^*\n]+)\*(?![\w*])'), (m) => m[1] ?? '');
  t = t.replaceAllMapped(
      RegExp(r'(?<![\w_])_([^_\n]+)_(?![\w_])'), (m) => m[1] ?? '');
  t = t.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '');
  t = t.replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ');
  return t.replaceAll('**', '').trim();
}
