// The FIT interaction backlog, resolved against the files a route is ACTUALLY
// built from.
//
// ── WHY THIS EXISTS ─────────────────────────────────────────────────────────
// `docs/FIT_INTERACTION_COVERAGE.md` was generated ad hoc, one file per anchor.
// Screens are not one file. They are a screen, the widgets it composes, the
// domain rules those widgets call, and — for any frame with a bottom nav — the
// shell that draws it. Measuring one file under-reports, and it has now
// under-reported five separate times:
//
//   FIT-001  4/9  recorded → 7/9 actual   (Directory/Messages/Notifications
//                                          live in `app_top_nav.dart`)
//   FIT-005  4/12 → 6/12,  FIT-028 4/10 → 5/10,  FIT-014 5/12 → 6/12,
//   FIT-032  5/11 → 6/11
//
// Each was found by hand, one anchor at a time. This resolves it once.
//
// ── HOW A ROUTE IS RESOLVED ─────────────────────────────────────────────────
//   1. `app_router.dart` maps `path: '/x'` to a builder widget;
//   2. the import that provides that widget is the screen file;
//   3. the screen's own project-relative imports are followed ONE hop, which
//      picks up `widgets/…` and `domain/…` without dragging in the world;
//   4. a frame the manifest marks `hasBottomNav` also gets `app_shell.dart`,
//      because that is where its nav labels genuinely live;
//   5. every frame gets `app_top_nav.dart`, which carries Directory, Messages
//      and Notifications.
//
// ── WHAT IT STILL CANNOT DO ─────────────────────────────────────────────────
// It is the same text-presence heuristic, with the same limits, and the limits
// matter more than the number:
//
//   * strong evidence of ABSENCE, weak evidence of PRESENCE. A match may be a
//     different control — seven such false positives have been found so far;
//   * **one-word labels are matched as STRING LITERALS, not substrings.** Half
//     the manifest is one word (300 of 600) and `Back` alone appears 69 times,
//     so a bare substring rule drove half the metric: `Back` matched
//     `background`, `Done` matched `abandoned`. Tightening it dropped the
//     total from 352 to 280 and took FIT-018 from 4/4 to **0/4** — `Easy` and
//     `Hard` appear nowhere in `lib`, so all four were coincidences;
//   * comments are stripped, because writing down that something was
//     deliberately NOT built used to make the metric report it as built;
//   * the board's SAMPLE rows ("Priya Hit 70 kg…", "1 Back squat 4 × 6…") can
//     only be matched by fabricating that exact data, so they are a CEILING,
//     not a backlog.
//
// A number here is a worklist entry, never a closure claim.
//
// Usage:  dart tool/fit_backlog.dart [manifest.json] [--locked] [--gaps]
// Run from apps/mobile.

import 'dart:convert';
import 'dart:io';

import 'orphan_route_sweep.dart'
    show registeredRoutes, navigatedRoutes, externallyEntered;

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
      while (i < src.length &&
          !(src[i] == '*' && i + 1 < src.length && src[i + 1] == '/')) {
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

String unescapeHtml(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ');

/// Wrappers that are not the screen. A route whose builder returns one of
/// these resolves to the widget INSIDE it.
///
/// This matters more than it looks. `/meals-dashboard`'s builder returns
/// `PaywallGate(... child: MealsDashboardScreen())`, so taking the first
/// widget after `=>` resolves the route to the GATE — which is the
/// "route resolved to a redirect stub" defect already recorded against the old
/// measurement, reproduced here on the first run of its replacement.
const _wrappers = {'PaywallGate', 'SafeArea', 'Scaffold', 'AppScaffold'};

/// Every `path: '/x'` → the widget identifiers its builder constructs, in
/// order, with wrappers dropped.
Map<String, List<String>> routeBuilders(String router) {
  final out = <String, List<String>>{};
  final re = RegExp(
      r"path:\s*'([^']+)'([\s\S]{0,600}?)builder:\s*\([^)]*\)\s*=>\s*([\s\S]{0,300}?)\)\),");
  for (final m in re.allMatches(router)) {
    final body = m.group(3)!;
    final widgets = RegExp(r'\b([A-Z]\w+)\s*\(')
        .allMatches(body)
        .map((w) => w.group(1)!)
        .where((w) => !_wrappers.contains(w))
        .toList();
    if (widgets.isNotEmpty) out.putIfAbsent(m.group(1)!, () => widgets);
  }
  return out;
}

/// Anchors whose implementation is a SUB-SURFACE of a route rather than the
/// route's own screen — a sheet, an embedded view, a cross-cutting wrapper.
/// A route resolver cannot find these, and guessing would be worse than
/// naming them.
const _subSurfaces = <String, List<String>>{
  // FIT-019 "Log a meal" is `_AddMealSheet`, opened from the dashboard.
  'FIT-019': ['lib/features/nutrition/presentation/meals_dashboard_screen.dart'],
  // FIT-020 "AI meal scan" is a view inside that sheet.
  'FIT-020': ['lib/features/nutrition/presentation/widgets/ai_scan_view.dart'],
  // FIT-021 is the gate itself, wrapping twelve routes.
  'FIT-021': ['lib/features/payments/presentation/paywall_gate.dart'],
  // FIT-022 is a cross-cutting failure pattern, not a screen.
  'FIT-022': ['lib/features/nutrition/presentation/widgets/nutrition_load_failed.dart'],
};

/// The project-relative imports of a file, resolved to real paths.
List<String> importsOf(String path) {
  final f = File(path);
  if (!f.existsSync()) return const [];
  final dir = f.parent.path;
  final out = <String>[];
  for (final m
      in RegExp(r"import\s+'([^']+\.dart)'").allMatches(f.readAsStringSync())) {
    final spec = m.group(1)!;
    if (spec.startsWith('package:') || spec.startsWith('dart:')) continue;
    final resolved = File(Uri.file('$dir/$spec').normalizePath().toFilePath());
    if (resolved.existsSync()) out.add(resolved.path);
  }
  return out;
}

void main(List<String> args) {
  final manifestPath = args.firstWhere((a) => !a.startsWith('--'),
      orElse: () => 'design/manifest.json');
  final lockedOnly = args.contains('--locked');
  final gapsOnly = args.contains('--gaps');
  // Emit the ledger itself. Re-parsing this tool's own aligned output dropped
  // 13 of 110 anchors and produced an empty cell, which is exactly the kind of
  // second-order measurement error the tool exists to stop.
  final markdown = args.contains('--markdown');
  // --absent FIT-0xx : list the labels still missing for one anchor, against
  // the SAME resolved file set the totals use.
  final absentFor = args
      .where((a) => a.startsWith('--absent='))
      .map((a) => a.substring(9))
      .firstOrNull;

  if (!File(manifestPath).existsSync()) {
    stderr.writeln('manifest not found: $manifestPath\n'
        'Usage: dart tool/fit_backlog.dart <manifest.json> [--locked] [--gaps]');
    exit(2);
  }

  final routerPath = 'lib/core/router/app_router.dart';
  final routerSrc = File(routerPath).readAsStringSync();
  final builders = routeBuilders(routerSrc);
  final routerImports = importsOf(routerPath);

  // A screen nobody can open is not implemented, whatever its labels say.
  // FIT-006 "Welcome" measured 2/2 while `/onboarding` had NO caller at all —
  // the router's own comment says the splash hands off to it, and the splash
  // goes to `/signup`. Presence is not reachability.
  final registered = registeredRoutes(routerSrc).toSet();
  final navigated = navigatedRoutes(Directory('lib'));
  bool unreachable(String? route) =>
      route != null &&
      registered.contains(route) &&
      !navigated.contains(route) &&
      !externallyEntered.containsKey(route) &&
      !navigated.any((n) => n.startsWith('$route/'));

  final anchors = <Map<String, dynamic>>[];
  void walk(Object? n) {
    if (n is Map) {
      if (n['id'] is String &&
          (n['id'] as String).startsWith('FIT-') &&
          n['interactions'] is List) {
        anchors.add(n.cast<String, dynamic>());
      }
      for (final v in n.values) {
        walk(v);
      }
    } else if (n is List) {
      for (final v in n) {
        walk(v);
      }
    }
  }

  walk(jsonDecode(File(manifestPath).readAsStringSync()));

  const topNav = 'lib/core/widgets/app_top_nav.dart';
  const shell = 'lib/core/router/app_shell.dart';

  var have = 0, total = 0, resolved = 0;
  final rows = <List<Object>>[];

  for (final a in anchors) {
    final route = a['route'] as String?;
    final widgets = route == null ? null : builders[route];

    // The screen file: the router import that defines the builder's widget.
    String? screen;
    for (final w in widgets ?? const <String>[]) {
      for (final imp in routerImports) {
        if (File(imp).readAsStringSync().contains('class $w ')) {
          screen = imp;
          break;
        }
      }
      if (screen != null) break;
    }
    final override = _subSurfaces[a['id'] as String];
    if (override != null && File(override.first).existsSync()) {
      screen = override.first;
    }

    // TWO hops, not one. A composing screen reaches its rules through a
    // widget — `classes_screen` → `whats_on_view` → `whats_on.dart`, where
    // `const whatsOnSegments = ['All', 'Classes', 'Events', 'Challenges']`
    // actually lives. One hop reported FIT-027 as 1/10 against a screen that
    // renders four of them.
    //
    // The second hop is scoped to `lib/features` and `lib/core`, so it picks
    // up widgets and domain rules without walking into the whole app.
    final direct = screen == null ? <String>[] : importsOf(screen);
    final second = <String>[
      for (final d in direct)
        if (d.contains('lib/features/') || d.contains('lib/core/'))
          ...importsOf(d),
    ];

    final files = <String>{
      if (screen != null) screen,
      ...direct,
      ...second,
      if (a['hasBottomNav'] == true) shell,
      topNav,
    }.where((f) => File(f).existsSync()).toList();

    if (screen != null) resolved++;

    final buf = StringBuffer();
    for (final f in files) {
      buf.write(stripComments(File(f).readAsStringSync()).toLowerCase());
      buf.write('\n');
    }
    final src = buf.toString();

    final interactions = (a['interactions'] as List).cast<Map>();
    var h = 0;
    for (final i in interactions) {
      final label = unescapeHtml(i['label'] as String).trim();
      final key = label.split(RegExp(r'\s+')).take(3).join(' ').toLowerCase();
      // A ONE-WORD label cannot be found by substring: `Back` appears 69 times
      // in the manifest and matches `background`, `Backup`, `callback`. Half
      // the declared interactions (300 of 600) are one word, so that single
      // rule drives half the metric. A rendered label is a STRING LITERAL in
      // Dart, so short labels must match as one.
      final present = label.split(RegExp(r'\s+')).length > 1
          ? src.contains(key)
          : (src.contains("'$key'") || src.contains('"$key"'));
      if (present) h++;
      if (absentFor == a['id']) {
        stdout.writeln('  ${present ? "HAVE  " : "ABSENT"}  $label');
      }
    }

    have += h;
    total += interactions.length;
    rows.add([
      a['id'] as String,
      a['locked'] == true,
      h,
      interactions.length,
      (a['name'] as String?) ?? '',
      route ?? '—',
      screen == null ? 'UNRESOLVED' : '${files.length} files',
      unreachable(route),
    ]);
  }

  rows.sort((x, y) =>
      ((y[3] as int) - (y[2] as int)).compareTo((x[3] as int) - (x[2] as int)));

  var lh = 0, lt = 0;
  for (final r in rows) {
    if (r[1] == true) {
      lh += r[2] as int;
      lt += r[3] as int;
    }
  }

  final lockedAnchors = rows.where((r) => r[1] == true).length;
  final lockedDone = rows
      .where((r) => r[1] == true && r[2] == r[3] && r[7] != true)
      .length;
  final unreachableAnchors = rows.where((r) => r[7] == true).toList();

  if (markdown) {
    stdout.writeln('## Headline\n');
    stdout.writeln('| Measure | Value |');
    stdout.writeln('|---|---|');
    stdout.writeln('| FIT screens | ${rows.length} |');
    stdout.writeln('| Route resolved to a screen file | $resolved |');
    stdout.writeln('| All declared interactions | **$have / $total** |');
    stdout.writeln('| **Locked-anchor interactions** | **$lh / $lt** |');
    stdout.writeln('| Locked anchors complete **and reachable** | '
        '**$lockedDone** of $lockedAnchors |');
    if (unreachableAnchors.isNotEmpty) {
      stdout.writeln('| Anchors whose route has **no way in** | '
          '**${unreachableAnchors.length}** — '
          '${unreachableAnchors.map((r) => r[0]).join(', ')} |');
    }
    stdout.writeln('\n## Every anchor, by remaining gap\n');
    stdout.writeln('| Anchor | Locked | Covered | Gap | Name | Route |');
    stdout.writeln('|---|---|---|---|---|---|');
    for (final r in rows) {
      final gap = (r[3] as int) - (r[2] as int);
      if (lockedOnly && r[1] != true) continue;
      if (gapsOnly && gap == 0) continue;
      stdout.writeln('| **${r[0]}**${gap == 0 ? ' ✅' : ''} '
          '| ${r[1] == true ? '🔒' : '—'} '
          '| ${r[2]}/${r[3]} | $gap | ${r[4]}'
          '${r[7] == true ? ' — **UNREACHABLE**' : ''} | `${r[5]}` |');
    }
    return;
  }

  stdout.writeln('ANCHOR    LOCK  COVER  GAP  NAME / ROUTE');
  for (final r in rows) {
    final gap = (r[3] as int) - (r[2] as int);
    if (lockedOnly && r[1] != true) continue;
    if (gapsOnly && gap == 0) continue;
    stdout.writeln('${(r[0] as String).padRight(9)} '
        '${r[1] == true ? ' 🔒 ' : '    '} '
        '${'${r[2]}/${r[3]}'.padLeft(6)} '
        '${gap.toString().padLeft(4)}  '
        '${(r[4] as String).padRight(30)} ${r[5]}  [${r[6]}]'
        '${r[7] == true ? '  <-- NO WAY IN' : ''}');
  }

  stdout.writeln('\n${'─' * 64}');
  stdout.writeln('anchors            ${rows.length}   '
      '(route resolved to a screen file: $resolved)');
  stdout.writeln('ALL interactions   $have / $total');
  stdout.writeln('LOCKED             $lh / $lt   '
      '($lockedAnchors anchors, $lockedDone complete AND reachable)');
  if (unreachableAnchors.isNotEmpty) {
    stdout.writeln('UNREACHABLE        ${unreachableAnchors.length}   '
        '${unreachableAnchors.map((r) => r[0]).join(', ')}');
  }
}
