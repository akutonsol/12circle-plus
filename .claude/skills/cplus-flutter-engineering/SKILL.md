---
name: cplus-flutter-engineering
description: Project conventions and proven patterns for implementing and testing Flutter/Riverpod code in 12circle-plus (apps/mobile) against Supabase — providers, realtime refresh, error contract, units, timestamps, fake-PostgREST tests, analyzer baseline and guards. Use for any 12circle-plus Flutter implementation or test task.
---

# Flutter engineering in 12circle-plus

Work in `apps/mobile`. Package name `circle_fitness`. State: Riverpod (`FutureProvider`,
`StreamProvider`, family/autoDispose). Backend: `supabase_flutter`. Routing: `go_router`
(`lib/core/router/app_router.dart`), **hash URL strategy** on web.

## Rules the codebase already enforces (do not regress)

- **Error contract.** A failed read is never shown as data: no `catch (_) { return []; }`, no
  `valueOrNull ?? []` turning an error into "nothing". Show a failure state with retry
  (`EC-G1/G5/G6/G8` guards). New `.valueOrNull` reads count against the EC-G8 ratchet (134) —
  route a shared read through one provider instead of adding reads.
- **No false success.** A write is "saved" only when the server confirmed it; a 0-row update is a
  failure (RLS filters silently). Best-effort side effects (notifications) never turn a saved write
  into a reported failure.
- **Per-account state.** Providers that read the signed-in user `ref.watch(currentUserProvider)`.
- **Live data.** Screens that must follow other users' changes watch
  `tableTickerProvider('<table>')` (`lib/core/realtime/realtime.dart`); the table must be in the
  `supabase_realtime` publication. After a local write, invalidate what it changes (see
  `refreshAfterMealLogged` for the pattern).
- **Time.** Instants go to timestamptz as `DateTime.now().toUtc().toIso8601String()`; a calendar
  day is the member's **local** date. Never compare a zoneless local string to a timestamptz.
- **Ordering.** postgrest-dart `.order(col)` defaults to **descending** — pass `ascending: true`.
- **Units.** Loads are stored in kg; display through `formatLoad` / `memberPrefersMetricProvider`
  (`lib/features/workout/domain/load_format.dart`).
- **Entitlements.** `PaywallGate` + `clientPlanProvider` (`client_plan()`); after a relationship
  change, invalidate `clientPlanProvider`.
- **Edit rights.** Exercise editing follows `canEditExercise` (mirrors migration 199; arrives with PR #168).

## Testing patterns that work here

- **Prove the defect first.** Write the test, then run it against main's implementation:
  copy your changed lib files aside, `git checkout origin/main -- <lib files>`, run the test (it must
  fail for the stated reason), restore your files, run again (it must pass). Report both results.
- **Fake PostgREST.** Initialise `Supabase.initialize(httpClient: <http.BaseClient fake>)`; every
  `StreamedResponse` must set `request:` or postgrest throws. Signed-in tests seed a session via a
  `LocalStorage` returning a JWT for a fixed uid; set `detectSessionInUri: false`.
- **Providers watching the ticker:** override
  `tableTickerProvider.overrideWith((ref, t) => Stream.value(0))` **and** keep the provider
  listened (`container.listen`) before reading `.future`. Close a `StreamController` that nothing
  listened to with `unawaited(c.close())` or teardown hangs 30 s.
- **Widget tests:** `functions.invoke` needs `tester.runAsync`; a pending scaffold timer needs
  `pumpWidget(SizedBox())` then `pump(5s)`.
- Source-shape tests are a last resort (private widgets deep in large screens) and must say why.

## Validation before handing back

```
cd apps/mobile && flutter analyze          # baseline 291 issues — must not increase
flutter test                                # full suite; report the count
# static guards run from the REPO ROOT, not apps/ (wrong cwd gives false failures)
```
Report the analyzer count, the suite count, and the failing-on-main evidence. Do not touch
`supabase/migrations` or protected docs; ask the lead for a backend package instead.
