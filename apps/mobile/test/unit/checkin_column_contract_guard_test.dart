import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CHK-C · the check-in writer and its readers agree on column names.
///
/// ── THE DEFECT THIS CLOSES (I-CHK-02 / I-CHK-03, ruled by PD-B02) ──────────
/// `weekly_checkins` carries two column families. Migration 000 created
/// `energy` and `sleep_hours_avg`; migration 001 added `energy_level`,
/// `sleep_hours`, `stress_level`, `hunger_level`, `compliance_percent`,
/// `weight_kg` and `notes`. All of them are REAL columns, so no query ever
/// errored — the application simply disagreed with itself. The one writer sent
/// the baseline pair; `ai-coach`, `insights_provider` and the coach review
/// queue read the 001 pair. A check-in that saved fine reached the AI as
/// `Energy: undefined/5`, and the Insights panel showed nothing at all.
///
/// A column mismatch is invisible to the type system, to RLS, and to every
/// "does the table exist" guard, because the table does exist. The only thing
/// that catches it is comparing what is written with what is read. That is this
/// file, and the registry specified it: "writer-keys ⊆ reader-keys".
///
/// ── WHAT IS DELIBERATELY NOT ASSERTED ──────────────────────────────────────
/// This proves the NAMES agree. It says nothing about values, scales, or the
/// round trip — that needs an authenticated QA session (OD-51). It also does
/// not claim the readers are COMPLETE: `hunger_level` has no reader and is not
/// written, which PD-B02's title asks about and its recommendation does not
/// answer, so it is left alone rather than inferred.
///
/// ── WHY THE EXPECTED LISTS ARE NOT DERIVED FROM THE FILE UNDER TEST ────────
/// A list built from the writer would delete its own assertion the moment a key
/// was removed. The table's columns come from the MIGRATIONS and the readers
/// from a named set of files, so each side is checked against something the
/// other cannot edit away.
void main() {
  const writerPath = 'lib/features/checkins/data/weekly_checkin_service.dart';
  const helperPath = 'lib/features/checkins/domain/checkin_columns.dart';

  /// Every Dart file that reads a `weekly_checkins` row. The Edge Function is
  /// read separately — it is TypeScript.
  const dartReaders = <String>[
    'lib/features/insights/domain/insights_provider.dart',
    'lib/features/dashboard/presentation/client_detail_screen.dart',
    'lib/features/checkins/domain/coach_review_queue.dart',
    'lib/features/checkins/data/weekly_checkin_service.dart',
  ];
  const edgeReader = '../../supabase/functions/ai-coach/index.ts';

  /// Keys the writer sends that are bookkeeping, not data a reader must show.
  const bookkeeping = <String>{
    'user_id', 'week_number', 'week_start_date', 'status', 'submitted_at',
    'overall_score',
  };

  /// The legacy names. Only `checkin_columns.dart` may mention them as a
  /// fallback; no reader may index a row by them directly.
  final legacyIndex = RegExp(r'''\[\s*['"](energy|sleep_hours_avg)['"]\s*\]''');

  String strip(String src) => src.split('\n').map((l) {
        final i = l.indexOf('//');
        return i < 0 ? l : l.substring(0, i);
      }).join('\n');

  late String writer;
  late Set<String> writerKeys;
  late Set<String> tableColumns;

  setUpAll(() {
    writer = strip(File(writerPath).readAsStringSync());
    final start = writer.indexOf("from('weekly_checkins').upsert({");
    final end = start < 0 ? -1 : writer.indexOf('onConflict', start);
    writerKeys = (start < 0 || end < 0)
        ? <String>{}
        : RegExp(r'''['"]([a-z_]+)['"]\s*:''')
            .allMatches(writer.substring(start, end))
            .map((m) => m.group(1)!)
            .toSet();

    // Columns from the MIGRATIONS: the 000 CREATE TABLE block plus every
    // `ALTER TABLE … weekly_checkins ADD COLUMN`.
    tableColumns = <String>{};
    final dir = Directory('../../supabase/migrations');
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.sql')) continue;
      final sql = f.readAsStringSync();
      final create = RegExp(
        r'CREATE TABLE IF NOT EXISTS public\.weekly_checkins \(([\s\S]*?)\n\);',
      ).firstMatch(sql);
      if (create != null) {
        for (final m in RegExp(r'"([a-z_]+)"\s+"?[a-z]')
            .allMatches(create.group(1)!)) {
          tableColumns.add(m.group(1)!);
        }
      }
      for (final m in RegExp(
        r'ALTER TABLE\s+(?:public\.)?weekly_checkins\s+ADD COLUMN(?: IF NOT EXISTS)?\s+([a-z_]+)',
        caseSensitive: false,
      ).allMatches(sql)) {
        tableColumns.add(m.group(1)!);
      }
    }
  });

  group('CHK-C · the check-in writer and its readers agree', () {
    test('the detector can see the writer and the table', () {
      // Without this, every assertion below could pass by finding nothing.
      expect(writerKeys.length, greaterThanOrEqualTo(10),
          reason: 'only ${writerKeys.length} writer keys parsed — the upsert '
              'block is no longer found and every assertion below is inert');
      expect(tableColumns, containsAll(['user_id', 'week_start_date', 'mood']),
          reason: 'the migration scan found ${tableColumns.length} columns; '
              'it has stopped reading the 000 CREATE TABLE block');
      expect(tableColumns, containsAll(['energy_level', 'sleep_hours']),
          reason: 'the migration scan no longer sees 001\'s ADD COLUMNs');
    });

    test('every key the writer sends is a real column', () {
      final phantom = writerKeys.difference(tableColumns).toList()..sort();
      expect(phantom, isEmpty,
          reason: 'the writer sends keys that are not columns of '
              '`weekly_checkins`: ${phantom.join(', ')}. PostgREST rejects the '
              'whole upsert, so every check-in would be lost.');
    });

    test('the writer sends the CANONICAL energy and sleep columns (PD-B02)', () {
      expect(writerKeys, containsAll(['energy_level', 'sleep_hours']),
          reason: 'PD-B02 ruled the 001 family canonical; ai-coach, '
              'insights_provider and the review queue read these names');
      expect(writerKeys.contains('energy'), isFalse,
          reason: 'the writer is back on the baseline `energy` column, which '
              'the AI and Insights readers do not read');
      expect(writerKeys.contains('sleep_hours_avg'), isFalse,
          reason: 'the writer is back on the baseline `sleep_hours_avg` column');
    });

    test('the helper\'s canonical constants match what the writer sends', () {
      final helper = File(helperPath).readAsStringSync();
      expect(helper, contains("kEnergyColumn = 'energy_level'"));
      expect(helper, contains("kSleepColumn = 'sleep_hours'"));
      expect(writerKeys, containsAll(['energy_level', 'sleep_hours']),
          reason: 'the helper and the writer have drifted apart');
    });

    test('every data key the writer sends is read by something', () {
      final readerSrc = StringBuffer();
      for (final p in dartReaders) {
        readerSrc.writeln(strip(File(p).readAsStringSync()));
      }
      readerSrc.writeln(File(edgeReader).readAsStringSync());
      final haystack = readerSrc.toString();

      final unread = writerKeys
          .difference(bookkeeping)
          .where((k) => !haystack.contains("'$k'") && !haystack.contains('.$k'))
          .toList()
        ..sort();
      expect(unread, isEmpty,
          reason: 'the writer sends keys no reader reads: ${unread.join(', ')}. '
              'Data is being collected that nothing shows or uses.');
    });

    test('no reader indexes a row by a LEGACY column name directly', () {
      final offenders = <String>[];
      for (final p in dartReaders) {
        if (legacyIndex.hasMatch(strip(File(p).readAsStringSync()))) {
          offenders.add(p);
        }
      }
      expect(offenders, isEmpty,
          reason: 'these readers index a row by `energy` or `sleep_hours_avg`: '
              '${offenders.join(', ')}. A row written under PD-B02 carries '
              'energy_level / sleep_hours, so the value reads as null. Go '
              'through checkinEnergy() / checkinSleepHours() instead.');
    });

    test('the Edge Function reads the canonical columns', () {
      final edge = File(edgeReader).readAsStringSync();
      expect(edge, contains('energy_level'));
      expect(edge, contains('sleep_hours'));
      expect(edge.contains('sleep_hours_avg'), isFalse,
          reason: 'ai-coach reads the baseline sleep column the writer no '
              'longer sends');
    });
  });
}
