import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/data/package_service.dart';
import 'package:circle_fitness/features/coach/domain/package_provider.dart';
import 'package:circle_fitness/features/payments/data/payment_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/packages_server.dart';

// P0-FL-56b (a) and (f) · package writes that were not confirmed, and the
// cancel-subscription failure nobody recorded.
//
// At f191d48:
//  * savePackage / deletePackage / saveSessionTiers / saveSchedule checked no
//    row: an RLS-filtered update or delete returned normally, i.e. "saved".
//  * signed out, all of them returned normally without writing anything.
//  * deletePackage took ANY failure of the delete for "a client schedule
//    references it" and deactivated the package instead, unrecorded.
//  * saveSessionTiers: an error after some tiers were written said only
//    "couldn't save this package".
//  * PaymentService.cancelSubscription lost the cause of every failure.
//
// No new type is named here, so the file compiles on the base and fails there
// for behaviour: `git checkout f191d48 -- lib/features/coach/data/
// package_service.dart lib/features/coach/domain/package_provider.dart
// lib/features/payments/data/payment_service.dart`.

({String name, double price, String description}) _tier(double price) =>
    (name: 'Pack', price: price, description: '');

void main() {
  final server = PackagesServer();
  final reported = <AppFailure>[];
  late PackageService svc;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPackagesSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    await Supabase.instance.client.auth.recoverSession(sessionFor(userA));
    svc = PackageService();
    server.packages.addAll([
      {'id': 'p1', 'coach_id': userA, 'type': 'monthly', 'name': 'Monthly', 'price': 99, 'sessions': 0, 'active': true},
    ]);
  });
  tearDown(resetFailureSink);

  Future<void> save({String? id = 'p1'}) => svc.savePackage(
      id: id, type: 'monthly', name: 'Renamed', sessions: 0, price: 120);
  Future<void> schedule() => svc.saveSchedule(
      coachId: 'coach-1', packageId: 'p1', days: ['monday'], sessionTime: '07:00');
  Map<String, Object?>? row(String id) =>
      server.packages.where((p) => p['id'] == id).firstOrNull;

  Future<Object?> errorOf(Future<void> Function() f) async {
    try {
      await f();
      return null;
    } catch (e) {
      return e;
    }
  }

  group('savePackage', () {
    test('an edit that changes no row is a failure', () async {
      server.writeMode = (_) => Answer.zeroRows;
      expect(await errorOf(save), isNotNull,
          reason: 'THE defect: a 0-row update read as saved');
    });
    test('signed out is a failure, and nothing is written', () async {
      await Supabase.instance.client.auth.signOut();
      expect(await errorOf(save), isNotNull);
      expect(server.writes, isEmpty);
    });
    test('positive control: an edit, and a new package', () async {
      await save();
      expect(row('p1')!['name'], 'Renamed');
      await save(id: null);
      expect(server.packages, hasLength(2));
    });
  });

  group('deletePackage', () {
    test('a delete that removes no row is a failure', () async {
      server.writeMode = (_) => Answer.zeroRows;
      expect(await errorOf(() => svc.deletePackage('p1')), isNotNull,
          reason: 'THE defect: a 0-row delete read as deleted');
      expect(row('p1'), isNotNull);
    });

    for (final a in [Answer.fails, Answer.network]) {
      test('a delete that fails (${a.name}) is a failure, not a deactivation',
          () async {
        server.writeMode = (l) => l.startsWith('DELETE') ? a : Answer.ok;
        expect(await errorOf(() => svc.deletePackage('p1')), isNotNull,
            reason: 'THE defect: any failure became a silent deactivation');
        expect(row('p1')!['active'], isTrue, reason: 'still offered to clients');
        expect(server.writes, hasLength(1));
      });
    }

    test('negative control: a package a schedule references is deactivated — an '
        'answer, not a failure', () async {
      server.writeMode =
          (l) => l.startsWith('DELETE') ? Answer.foreignKey : Answer.ok;
      expect(await errorOf(() => svc.deletePackage('p1')), isNull);
      expect(row('p1')!['active'], isFalse);
    });

    test('a deactivation that changes no row is a failure', () async {
      server.writeMode =
          (l) => l.startsWith('DELETE') ? Answer.foreignKey : Answer.zeroRows;
      expect(await errorOf(() => svc.deletePackage('p1')), isNotNull);
      expect(row('p1')!['active'], isTrue);
    });

    test('positive control: the package is deleted', () async {
      await svc.deletePackage('p1');
      expect(row('p1'), isNull);
    });
  });

  group('saveSessionTiers', () {
    setUp(() {
      server.packages.addAll([
        for (final t in [4, 8])
          {'id': 'b$t', 'coach_id': userA, 'type': 'bulk', 'name': 'Old $t', 'price': 10, 'sessions': t, 'active': true},
      ]);
    });
    final all = {for (final t in [4, 8, 12, 16]) t: _tier(t * 10)};
    Map<int, Object?> prices() => {
          for (final p in server.packages)
            if (p['type'] == 'bulk') p['sessions'] as int: p['price'],
        };

    test('a failure after some tiers were written says which are saved and '
        'which are not', () async {
      server.writeMode = (l) => l.contains('"sessions":12') ? Answer.fails : Answer.ok;
      final e = await errorOf(() => svc.saveSessionTiers(all));
      expect(prices(), {4: 40, 8: 80}, reason: 'premise: a half state is left');
      expect((e as dynamic).saved, [4, 8],
          reason: 'THE defect: the partial save was a plain failure');
      expect((e as dynamic).notSaved, [12, 16]);
      expect((e as dynamic).cause, isA<PostgrestException>());
    });

    test('a 0-row update is a failure: the tiers before it are saved', () async {
      server.writeMode =
          (l) => l.startsWith('PATCH') && l.contains('b8') ? Answer.zeroRows : Answer.ok;
      final e = await errorOf(() => svc.saveSessionTiers(all));
      expect(e, isNotNull, reason: 'THE defect: read as saved');
      expect((e as dynamic).saved, [4]);
      expect((e as dynamic).notSaved, [8, 12, 16]);
    });

    test('a failed removal is not saved; tiers with nothing to do are in '
        'neither list', () async {
      server.writeMode = (l) => l.startsWith('DELETE') ? Answer.fails : Answer.ok;
      final e = await errorOf(() => svc.saveSessionTiers({4: _tier(44)}));
      expect((e as dynamic).saved, [4]);
      expect((e as dynamic).notSaved, [8], reason: '12 and 16 were never offered');
      expect(prices(), {4: 44, 8: 10}, reason: 'still there, still offered');
    });

    test('nothing written yet: the failure itself, not "partly saved"', () async {
      server.writeMode = (_) => Answer.fails;
      expect(await errorOf(() => svc.saveSessionTiers(all)),
          isA<PostgrestException>());
      expect(server.writes, hasLength(1), reason: 'stops at the first failure');
    });

    test('a failed read of the existing tiers writes nothing', () async {
      server.readMode['coach_packages'] = Answer.fails;
      expect(await errorOf(() => svc.saveSessionTiers(all)), isNotNull);
      expect(server.writes, isEmpty);
    });

    test('signed out is a failure, and nothing is written', () async {
      await Supabase.instance.client.auth.signOut();
      expect(await errorOf(() => svc.saveSessionTiers(all)), isNotNull);
      expect(server.writes, isEmpty);
    });

    test('saving again after a partial save completes it, no duplicates', () async {
      server.writeMode = (l) => l.contains('"sessions":12') ? Answer.fails : Answer.ok;
      await errorOf(() => svc.saveSessionTiers(all));
      server.writeMode = null;
      await svc.saveSessionTiers(all);
      expect(prices(), {4: 40, 8: 80, 12: 120, 16: 160});
      expect(server.packages.where((p) => p['type'] == 'bulk'), hasLength(4));
    });

    test('positive control: all four; a blank tier is removed', () async {
      await svc.saveSessionTiers({4: _tier(40), 12: _tier(120)});
      expect(prices(), {4: 40, 12: 120});
    });

    test('negative control: no tiers and none before is nothing to save', () async {
      server.packages.clear();
      expect(await errorOf(() => svc.saveSessionTiers({})), isNull);
      expect(server.writes, isEmpty);
    });
  });

  group('saveSchedule', () {
    test('no row back is a failure', () async {
      server.writeMode = (_) => Answer.zeroRows;
      expect(await errorOf(schedule), isNotNull,
          reason: 'THE defect: read as saved');
    });
    test('signed out is a failure, and nothing is written', () async {
      await Supabase.instance.client.auth.signOut();
      expect(await errorOf(schedule), isNotNull);
      expect(server.writes, isEmpty);
    });
    test('positive control: the schedule is saved', () async {
      await schedule();
      expect(server.schedules[userA]!['package_id'], 'p1');
    });
  });

  group('the package reads are recorded', () {
    final reads = <String, (String, ProviderListenable<AsyncValue<Object?>>)>{
      'myPackagesProvider': ('coach_packages', myPackagesProvider),
      'coachPackagesProvider': ('coach_packages', coachPackagesProvider('coach-1')),
      'myScheduleProvider': ('client_schedules', myScheduleProvider),
      'clientScheduleProvider': ('client_schedules', clientScheduleProvider('client-1')),
    };
    for (final MapEntry(key: origin, value: (table, provider)) in reads.entries) {
      Future<AsyncValue<Object?>> settle(ProviderContainer c) async {
        c.listen(provider, (_, __) {});
        for (var i = 0; i < 50 && c.read(provider).isLoading; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return c.read(provider);
      }

      test('$origin: a failed read is an error, recorded once', () async {
        server.readMode[table] = Answer.fails;
        final c = ProviderContainer();
        addTearDown(c.dispose);
        expect((await settle(c)).hasError, isTrue);
        expect(reported.map((f) => f.origin), [origin], reason: 'THE defect');
      });
      test('$origin: a genuine absence is an answer', () async {
        server.packages.clear();
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final v = await settle(c);
        expect(v.hasError, isFalse);
        expect(v.value, anyOf(isNull, isEmpty));
        expect(reported, isEmpty);
      });
    }
  });

  group('PaymentService.cancelSubscription', () {
    test('a failure is recorded and still answers false', () async {
      server.cancelStatus = 500;
      expect(await PaymentService().cancelSubscription('sub-1'), isFalse);
      expect(reported.map((f) => f.origin), ['PaymentService.cancelSubscription'],
          reason: 'THE defect: the cause was lost');
    });
    test('positive control: {"ok": true} is true, nothing recorded', () async {
      expect(await PaymentService().cancelSubscription('sub-1'), isTrue);
      expect(reported, isEmpty);
    });
    test('negative control: a 200 that is not ok:true is false — an answer, '
        'not an exception', () async {
      server.cancelReply = {'ok': false};
      expect(await PaymentService().cancelSubscription('sub-1'), isFalse);
      expect(reported, isEmpty);
    });
  });
}
