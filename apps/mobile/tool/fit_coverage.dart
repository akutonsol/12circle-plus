// FIT interaction coverage — the measurement, with comments stripped.
//
// ── WHY THIS EXISTS ─────────────────────────────────────────────────────────
// The original measurement matched a declared interaction's first three words
// against the raw text of the implementing file. That counts **comments**, and
// this programme's comments quote the design constantly — an anchor id, a row
// the board draws, a decision that was deliberately NOT made. Four anchors had
// already accumulated recorded artifacts:
//
//   FIT-028  "Connect"                      — a Dart doc comment naming the anchor
//   FIT-005  "Priya Hit 70 kg…"             — a comment quoting the sample row
//   FIT-023  "Week 13 Energy steady…"       — the same
//   FIT-004  "Low" / "Steady" / "Strong"    — a comment explaining why the
//                                             mapping was NOT built (OD-16)
//
// The last one is the clearest argument for fixing the tool rather than
// annotating each case: **writing down that something was deliberately not
// implemented made the metric report it as implemented.** A number that rises
// when nothing ships is not a measurement.
//
// So this strips `//` and `/* */` before matching. It does not strip string
// literals — a label inside a string is the thing being looked for.
//
// ── WHAT IT STILL CANNOT DO ─────────────────────────────────────────────────
// Unchanged from the original, and still recorded in the report it feeds:
//   * it is weak evidence of PRESENCE — a match may be a different control;
//   * it reads only the files given, so a screen composed from sibling widget
//     files under-reports unless they are listed;
//   * the design board's sample rows ("11 Sep Reformer, small group…") can only
//     be matched by fabricating that exact class, so they are a ceiling, not a
//     backlog.
//
// Usage:
//   dart tool/fit_coverage.dart <manifest.json> <FIT-ID> <file> [file...]

import 'dart:convert';
import 'dart:io';

/// Removes `//` line comments and `/* */` blocks, leaving string literals
/// intact — including a `//` that appears inside one.
String stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  String? quote;
  while (i < src.length) {
    final c = src[i];
    final next = i + 1 < src.length ? src[i + 1] : '';

    if (quote != null) {
      out.write(c);
      if (c == r'\') {
        if (i + 1 < src.length) out.write(next);
        i += 2;
        continue;
      }
      if (src.startsWith(quote, i)) {
        i += quote.length;
        // The closing delimiter was written one char at a time above for
        // single quotes; for triple quotes write the remainder.
        if (quote.length > 1) out.write(quote.substring(1));
        quote = null;
        continue;
      }
      i++;
      continue;
    }

    if (c == '/' && next == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      i += 2;
      while (i < src.length && !(src[i] == '*' && i + 1 < src.length && src[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    for (final q in const ["'''", '"""', "'", '"']) {
      if (src.startsWith(q, i)) {
        quote = q;
        out.write(q);
        i += q.length;
        break;
      }
    }
    if (quote != null) continue;

    out.write(c);
    i++;
  }
  return out.toString();
}

/// The manifest stores labels **HTML-escaped** — `Cycle &amp; wellbeing`,
/// `Smaller &lt; larger`. Matching the raw string against Dart source means an
/// implemented label containing `&` can never be found, which reported
/// FIT-029's "Cycle & wellbeing" as absent when it was on screen. Third defect
/// found in this measurement, after counting comments and resolving a route to
/// a redirect stub.
String unescapeHtml(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ');

Map<String, dynamic>? _find(Object? node, String id) {
  if (node is Map) {
    if (node['id'] == id) return node.cast<String, dynamic>();
    for (final v in node.values) {
      final hit = _find(v, id);
      if (hit != null) return hit;
    }
  } else if (node is List) {
    for (final v in node) {
      final hit = _find(v, id);
      if (hit != null) return hit;
    }
  }
  return null;
}

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln('usage: dart tool/fit_coverage.dart <manifest> <FIT-ID> <file>...');
    exit(2);
  }
  final manifest = jsonDecode(File(args[0]).readAsStringSync());
  final screen = _find(manifest, args[1]);
  if (screen == null) {
    stderr.writeln('${args[1]} not found in manifest');
    exit(2);
  }

  final buffer = StringBuffer();
  for (final path in args.skip(2)) {
    buffer.write(stripComments(File(path).readAsStringSync()).toLowerCase());
    buffer.write('\n');
  }
  final src = buffer.toString();

  var have = 0;
  final interactions = (screen['interactions'] as List).cast<Map>();
  for (final i in interactions) {
    final label = unescapeHtml(i['label'] as String).trim();
    final key = label.split(RegExp(r'\s+')).take(3).join(' ').toLowerCase();
    final present = src.contains(key);
    if (present) have++;
    final mark = present ? 'HAVE  ' : 'ABSENT';
    final shown = label.length <= 56 ? label : '${label.substring(0, 53)}...';
    stdout.writeln('$mark  $shown');
  }
  stdout.writeln('${args[1]}  ->  $have / ${interactions.length}');
}
