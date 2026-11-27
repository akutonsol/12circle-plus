import 'dart:convert';

import 'package:http/http.dart' as http;

import 'two_member_postgrest.dart';

/// [TwoMemberPostgrest] plus the three reads behind Activity's streak and the
/// Upcoming panels (P0-FL-60b): `daily_scores` (per member, by RLS: the bearer
/// token's rows only), `classes` and `events` (the same for everybody).
class ActivityServer extends TwoMemberPostgrest {
  /// Consecutive days ending today, by member.
  final days = <String, int>{};
  final classes = <Map<String, Object?>>[];
  final events = <Map<String, Object?>>[];

  /// Tables whose request never reaches the server (http.ClientException).
  final offline = <String>{};

  @override
  void reset() {
    super.reset();
    days.clear();
    classes.clear();
    events.clear();
    offline.clear();
  }

  List<Map<String, Object?>> _scores(String uid) {
    final now = DateTime.now();
    return [
      for (var d = 0; d < (days[uid] ?? 0); d++)
        {
          'score_date': DateTime(now.year, now.month, now.day - d)
              .toIso8601String()
              .split('T')
              .first,
          'total_score': 10,
        }
    ];
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final table = request.url.path.split('/').last;
    if (!const {'daily_scores', 'classes', 'events'}.contains(table)) {
      return super.send(request);
    }
    final who = TwoMemberPostgrest.who(request);
    final key = '${request.method} $table:$who';
    calls.add(key);
    final asked =
        (request.url.queryParameters['user_id'] ?? 'eq.$who').substring(3);
    // The answer that was true when the request arrived.
    final rows = switch (table) {
      'classes' => [...classes],
      'events' => [...events],
      _ => asked == who ? _scores(who) : const <Map<String, Object?>>[],
    };
    final failed = fails.contains(key) || fails.contains(table);
    final off = offline.contains(table);
    final hold = holds[key];
    if (hold != null) await hold.future;
    if (off) throw http.ClientException('Connection refused', request.url);
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(failed
            ? {'message': 'refused SECRET_TABLE', 'code': 'XX000'}
            : rows))),
        failed ? 500 : 200,
        request: request,
        headers: {'content-type': 'application/json'});
  }
}
