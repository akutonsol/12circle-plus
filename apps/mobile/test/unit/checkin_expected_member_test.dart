import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/checkins/data/weekly_checkin_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/owned_writes_postgrest.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59c (W6) · the check-in save takes the member its answers belong to.
// The upsert replaces the signed-in member's whole week, so with anyone else
// signed in it writes nothing. On its own file because `expectedUid` does not
// exist at a82f993: there this does not compile, and the behaviour it names is
// shown failing by test/widget/checkins_keep_their_owner_test.dart.

void main() {
  const notes = 'A: my knee is worse';
  late OwnedWritesPostgrest server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = OwnedWritesPostgrest();
    await initTwoMemberSupabase(server);
  });
  setUp(() async {
    await signInAs(memberA);
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<bool> submit({String? as}) => WeeklyCheckinService()
      .submitWeeklyCheckin(
          mood: 4, energy: 4, stress: 2, sleepHoursAvg: 7, notes: notes,
          expectedUid: as);

  test('with someone else signed in: nothing is asked of the server',
      () async {
    await signInAs(memberB);
    expect(await submit(as: memberA), isFalse);
    expect(server.log, isEmpty);
    expect(origins(), ['WeeklyCheckinService.submitWeeklyCheckin']);
  });

  test('signed out: nothing is asked of the server', () async {
    await signOut();
    expect(await submit(as: memberA), isFalse);
    expect(server.log, isEmpty);
  });

  test('POSITIVE CONTROL: the expected member saves', () async {
    expect(await submit(as: memberA), isTrue);
    expect(server.sent('POST', 'weekly_checkins').single.who, memberA);
    expect(reported, isEmpty);
  });
}
