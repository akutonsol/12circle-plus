// QA-K — billing, subscription, payment and entitlement contract guards.
//
// Workstream K audited the whole money path: marketing tier -> checkout ->
// webhook -> subscription -> entitlement -> session credits -> cancellation ->
// renewal -> failure -> refund -> UI. Before this file there was NO automated
// coverage of any of it (see docs/QA_WORKSTREAM_K_BILLING_ENTITLEMENT_REPORT.md
// section 9).
//
// These are STATIC guards in the idiom of phase1_security_boundary_test.dart:
// they parse the committed Edge Function TypeScript, the committed SQL and the
// committed Dart, so a pricing/entitlement regression fails `flutter test`
// without any Stripe account, any network call and any QA credential. NOTHING
// here contacts Stripe or any Supabase project.
//
// Two kinds of test live here:
//
//   * ACTIVE guards  — invariants that hold in the tree TODAY. They exist so
//     remediation of the open findings cannot silently break the parts that
//     are already correct (tier ladder, capacity limits, commission split).
//
//   * OPEN SPECS     — `skip:`ped executable specifications of the findings
//     that are still open. Each names its finding ID. When the fix lands,
//     delete the `skip:` and the test becomes the regression guard. They are
//     skipped rather than failing so the suite stays green and honest: the
//     defect is recorded in the report, not hidden in a red build.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/payments/domain/entitlements.dart';

// ── Locating the tree ────────────────────────────────────────────────────────

Directory _mobileRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not locate the Flutter package root');
    }
    dir = parent;
  }
  return dir;
}

Directory _repoRoot() {
  var dir = _mobileRoot();
  while (!Directory('${dir.path}/supabase/migrations').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not locate supabase/migrations');
    }
    dir = parent;
  }
  return dir;
}

String _edgeFn(String name) =>
    File('${_repoRoot().path}/supabase/functions/$name/index.ts').readAsStringSync();

String _migration(int n) {
  final dir = Directory('${_repoRoot().path}/supabase/migrations');
  for (final f in dir.listSync().whereType<File>()) {
    final base = f.uri.pathSegments.last;
    if (base.endsWith('.sql') && int.tryParse(base.split('_').first) == n) {
      return f.readAsStringSync();
    }
  }
  throw StateError('migration $n not found');
}

String _mobileFile(String relative) =>
    File('${_mobileRoot().path}/$relative').readAsStringSync();

String _repoFile(String relative) =>
    File('${_repoRoot().path}/$relative').readAsStringSync();

// ── The Connect commission split, mirrored from create-checkout ──────────────
//
// Source of truth: supabase/functions/create-checkout/index.ts, the
// `coachingAmountCents > 0 && metadata.coach_id` branch:
//
//   const rate     = source === 'coach_invited' ? 0 : marketRate;
//   const feeCents = Math.round(coachingAmountCents * rate);
//   coach_payout   = coachingAmountCents - feeCents
//
// and, for the recurring (subscription) leg only:
//
//   application_fee_percent: Math.round(rate * 100)
//
// Replicated here so the arithmetic is provable without a Deno runtime, the
// same technique edge_function_logic_test.dart uses for the reminder job.
({num rate, int feeCents, int payoutCents}) commissionSplit({
  required int amountCents,
  required String clientSource,
  required num marketRate,
}) {
  final rate = clientSource == 'coach_invited' ? 0 : marketRate;
  final fee = (amountCents * rate).round();
  return (rate: rate, feeCents: fee, payoutCents: amountCents - fee);
}

/// The percentage Stripe is asked to take on the RECURRING leg.
int applicationFeePercent(num rate) => (rate * 100).round();

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // ACTIVE GUARD — the tier ladder is spelled the same way on every surface.
  // ══════════════════════════════════════════════════════════════════════════
  group('K/TIER — plan identifiers agree across checkout, webhook and resolver', () {
    test('create-checkout accepts exactly the six purchase kinds the product sells', () {
      final src = _edgeFn('create-checkout');
      for (final kind in [
        'coach',
        'coach_plan',
        'self_guided',
        'ai_guided',
        'event_ticket',
        'package',
      ]) {
        // A dispatch, not a mention (QA exhaustion Run 2): `contains("'$kind'")`
        // matched the TypeScript type union and a comment, so deleting the
        // branch that HANDLES coach_plan left this green (mutation-proven).
        final code = src
            .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
            .split('\n')
            .map((l) => l.contains('//') ? l.substring(0, l.indexOf('//')) : l)
            .join('\n');
        expect(RegExp("kind\\s*===\\s*'$kind'").hasMatch(code), isTrue,
            reason: 'create-checkout must still dispatch on kind=$kind');
      }
    });

    test('the webhook classifies every recurring kind create-checkout can emit', () {
      final hook = _edgeFn('stripe-webhook');
      // create-checkout emits `package_monthly` (not `package`) for the
      // recurring package leg; the webhook must classify it as a subscription
      // or a monthly coaching plan silently grants nothing.
      for (final kind in [
        'coach',
        'coach_plan',
        'self_guided',
        'ai_guided',
        'package_monthly',
      ]) {
        expect(hook, contains("kind === '$kind'"),
            reason: 'stripe-webhook must classify $kind as a subscription');
      }
      expect(_edgeFn('create-checkout'), contains("kind: 'package_monthly'"),
          reason: 'the recurring package leg must keep emitting package_monthly');
    });

    test('client_plan() resolves the same ladder the Dart ClientPlan enum ranks', () {
      final sql = _migration(24);
      // coach_guided is the top tier, then ai_guided outranks self_guided.
      final coachIdx = sql.indexOf("'coach_guided'");
      final aiIdx = sql.indexOf("WHEN 'ai_guided' THEN 0");
      expect(coachIdx, greaterThan(-1));
      expect(aiIdx, greaterThan(coachIdx),
          reason: 'coach_guided must be resolved before the membership tiers');

      expect(ClientPlan.coachGuided.rank, greaterThan(ClientPlan.aiGuided.rank));
      expect(ClientPlan.aiGuided.rank, greaterThan(ClientPlan.selfGuided.rank));
      expect(ClientPlan.selfGuided.rank, greaterThan(ClientPlan.free.rank));
    });

    test('clientPlanFromString maps exactly the strings client_plan() can return', () {
      expect(clientPlanFromString('coach_guided'), ClientPlan.coachGuided);
      expect(clientPlanFromString('ai_guided'), ClientPlan.aiGuided);
      expect(clientPlanFromString('self_guided'), ClientPlan.selfGuided);
      expect(clientPlanFromString('free'), ClientPlan.free);
      // Anything the resolver cannot produce must fail CLOSED, not open.
      expect(clientPlanFromString(null), ClientPlan.free);
      expect(clientPlanFromString('elite'), ClientPlan.free);
      expect(clientPlanFromString(''), ClientPlan.free);
    });

    test('the capability matrix keeps its tier boundaries', () {
      // Free
      expect(ClientPlan.free.isPaid, isFalse);
      expect(ClientPlan.free.canFullWorkouts, isFalse);
      expect(ClientPlan.free.canAiCoach, isFalse);
      expect(ClientPlan.free.canGenerateProgram, isFalse);
      expect(ClientPlan.free.canMessageCoach, isFalse);
      expect(ClientPlan.free.canAccessCommunity, isTrue);
      expect(ClientPlan.free.canRegisterEvents, isTrue);
      // Self-Guided
      expect(ClientPlan.selfGuided.canFullWorkouts, isTrue);
      expect(ClientPlan.selfGuided.canAiCoach, isFalse);
      expect(ClientPlan.selfGuided.canMessageCoach, isFalse);
      // AI-Guided
      expect(ClientPlan.aiGuided.canAiCoach, isTrue);
      expect(ClientPlan.aiGuided.canGenerateProgram, isTrue);
      expect(ClientPlan.aiGuided.canMessageCoach, isFalse);
      // Coach-Guided
      expect(ClientPlan.coachGuided.canMessageCoach, isTrue);
      expect(ClientPlan.coachGuided.canAiCoach, isTrue);
    });

    test('the two membership price IDs are named identically in both functions', () {
      for (final envVar in [
        'STRIPE_SELF_GUIDED_PRICE_ID',
        'STRIPE_AI_GUIDED_PRICE_ID',
      ]) {
        expect(_edgeFn('create-checkout'), contains(envVar));
        expect(_edgeFn('update-subscription'), contains(envVar),
            reason: 'a tier swap must resolve the same Stripe price as a fresh '
                'checkout, or an upgrade silently re-prices the customer');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ACTIVE GUARD — coach platform plan capacity.
  // ══════════════════════════════════════════════════════════════════════════
  group('K/CAPACITY — coach plan tiers promise what the webhook grants', () {
    test('the paywall copy and the webhook limits map agree', () {
      final ui = _mobileFile(
          'lib/features/payments/presentation/coach_plan_screen.dart');
      final hook = _edgeFn('stripe-webhook');

      expect(ui, contains('Up to 25 clients'));
      expect(ui, contains('Up to 100 clients'));
      expect(ui, contains('Unlimited clients'));

      expect(hook, contains('starter: 25'));
      expect(hook, contains('growth: 100'));
      expect(hook, contains('elite: 100000'),
          reason: 'Elite is sold as unlimited; the webhook models that as a '
              'sentinel 100000. Changing one without the other mis-sells the tier');
    });

    test('the three coach tiers are the same three everywhere', () {
      for (final tier in ['starter', 'growth', 'elite']) {
        expect(_edgeFn('create-checkout'), contains(tier));
        expect(_migration(23), contains(tier));
        expect(
            _mobileFile(
                'lib/features/payments/presentation/coach_plan_screen.dart'),
            contains("'$tier'"));
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ACTIVE GUARD — Stripe Connect commission arithmetic.
  // ══════════════════════════════════════════════════════════════════════════
  group('K/SPLIT — the coaching commission split never leaks or over-charges', () {
    test('a coach-invited client is charged 0% commission', () {
      final s = commissionSplit(
          amountCents: 12900, clientSource: 'coach_invited', marketRate: 0.10);
      expect(s.rate, 0);
      expect(s.feeCents, 0);
      expect(s.payoutCents, 12900);
    });

    test('a marketplace client is charged the configured rate', () {
      final s = commissionSplit(
          amountCents: 12900, clientSource: 'marketplace', marketRate: 0.10);
      expect(s.feeCents, 1290);
      expect(s.payoutCents, 11610);
    });

    test('fee + payout is always exactly the amount charged — no lost cents', () {
      for (final amount in [1, 99, 100, 333, 2999, 12900, 49999, 100000]) {
        for (final rate in [0, 0.05, 0.10, 0.125, 0.15, 0.30]) {
          final s = commissionSplit(
              amountCents: amount, clientSource: 'marketplace', marketRate: rate);
          expect(s.feeCents + s.payoutCents, amount,
              reason: 'split of $amount at $rate must reconcile to the charge');
          expect(s.feeCents, greaterThanOrEqualTo(0));
          expect(s.payoutCents, greaterThanOrEqualTo(0));
        }
      }
    });

    test('the platform fee never exceeds the charge', () {
      final s = commissionSplit(
          amountCents: 5000, clientSource: 'marketplace', marketRate: 1.0);
      expect(s.feeCents, lessThanOrEqualTo(5000));
      expect(s.payoutCents, 0);
    });

    test(
        'K-14 — recurring and one-time legs price a fractional rate differently',
        () {
      // Documented divergence, not an accident of this test: the one-time leg
      // uses application_fee_amount (exact cents) while the recurring leg uses
      // application_fee_percent, which create-checkout rounds to a whole
      // percent. A 12.5% rate is 12.5% on a package and 13% on a subscription.
      const rate = 0.125;
      final oneTime = commissionSplit(
          amountCents: 12900, clientSource: 'marketplace', marketRate: rate);
      expect(oneTime.feeCents, 1613); // 12.5% of $129.00
      expect(applicationFeePercent(rate), 13); // NOT 12.5
      final recurringEquivalent = (12900 * 0.13).round();
      expect(recurringEquivalent, isNot(oneTime.feeCents),
          reason: 'finding K-14: same configured rate, two different prices');
    });

    test('the default marketplace rate is 10% in both the column and the setting', () {
      expect(_migration(38), contains('marketplace_commission_rate numeric NOT NULL DEFAULT 0.10'));
      expect(_migration(39), contains("('marketplace_commission_rate', '0.10')"));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ACTIVE GUARD — webhook surface vs. the endpoint it is configured against.
  // ══════════════════════════════════════════════════════════════════════════
  group('K/WEBHOOK — handled events and the documented subscription agree', () {
    test('the handler switches on exactly three Stripe events', () {
      final hook = _edgeFn('stripe-webhook');
      final cases = RegExp(r"case '([a-z_.]+)':")
          .allMatches(hook)
          .map((m) => m.group(1)!)
          .toSet();
      expect(
          cases,
          {
            'checkout.session.completed',
            'customer.subscription.updated',
            'customer.subscription.deleted',
          },
          reason: 'this set is the whole billing lifecycle the backend can see. '
              'Widening it is a remediation; narrowing it silently drops money '
              'events. Findings K-02 / K-06 track what is missing');
    });

    test('the runbook subscribes the endpoint to the events the handler implements', () {
      final runbook = _repoFile('supabase/STRIPE_SETUP.md');
      for (final ev in [
        'checkout.session.completed',
        'customer.subscription.updated',
        'customer.subscription.deleted',
      ]) {
        expect(runbook, contains(ev),
            reason: 'an implemented event that is not subscribed never fires');
      }
    });

    test('the webhook verifies the Stripe signature before doing any work', () {
      final hook = _edgeFn('stripe-webhook');
      expect(hook, contains('STRIPE_WEBHOOK_SECRET'));
      expect(hook, contains('constructEventAsync'));
      final verifyAt = hook.indexOf('constructEventAsync');
      final firstWriteAt = hook.indexOf("db.from(");
      expect(verifyAt, lessThan(firstWriteAt),
          reason: 'signature verification must precede every database write');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ACTIVE GUARD — Stripe identity is server-owned.
  // ══════════════════════════════════════════════════════════════════════════
  group('K/IDENTITY — billing identity columns are not client-writable', () {
    test('migration 115 pins every Stripe column against client writes', () {
      final sql = _migration(115);
      for (final col in [
        'stripe_customer_id',
        'stripe_account_id',
        'stripe_charges_enabled',
        'stripe_payouts_enabled',
        'stripe_details_submitted',
        'marketplace_commission_rate',
        'membership_tier',
      ]) {
        expect(sql, contains(col),
            reason: '$col decides who gets charged what; it must stay in the '
                'privilege boundary trigger');
      }
    });

    test('client_source — which sets the commission rate — is immutable after insert', () {
      expect(_migration(113),
          contains('client_source is set by the server'));
    });

    test('the subscriptions table grants no client write path', () {
      final sql = _migration(22);
      expect(sql, contains('ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY'));
      expect(sql, contains('ON subscriptions FOR SELECT'));
      expect(sql, isNot(contains('ON subscriptions FOR INSERT')));
      expect(sql, isNot(contains('ON subscriptions FOR UPDATE')));
      expect(sql, isNot(contains('ON subscriptions FOR ALL')));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // OPEN SPECS — each is the regression guard for a finding that is still open.
  // Remove the `skip:` when the fix lands.
  // ══════════════════════════════════════════════════════════════════════════
  group('K/OPEN — executable specifications for the open findings', () {
    test('K-01 the webhook is idempotent against redelivery', () {
      final hook = _edgeFn('stripe-webhook');
      expect(hook, contains('event.id'),
          reason: 'Stripe delivers at least once; the handler must record and '
              'short-circuit an event id it has already applied');
      expect(hook, isNot(contains("from('client_session_credits').insert(")),
          reason: 'a bare insert re-grants the whole session pack on every '
              'redelivery of checkout.session.completed');
    }, skip: 'Open finding K-01 — no processed-event store; credits are granted with .insert()');

    test('K-02 the webhook reconciles renewals, failures and refunds', () {
      final hook = _edgeFn('stripe-webhook');
      for (final ev in [
        'invoice.paid',
        'invoice.payment_failed',
        'charge.refunded',
        'charge.dispute.created',
      ]) {
        expect(hook, contains(ev));
      }
    }, skip: 'Open finding K-02/K-06 — renewal, failure, refund and dispute events are unhandled');

    test('K-03 the paid AI functions enforce the membership server-side', () {
      for (final fn in ['ai-coach', 'ai-generate-workout', 'ai-coaching-engine']) {
        final src = _edgeFn(fn);
        expect(src, anyOf(contains('active_membership'), contains('client_plan')),
            reason: '$fn is sold inside AI-Guided; auth alone is not entitlement');
      }
    }, skip: 'Open finding K-03 — AI Edge Functions authenticate but never check the plan');

    // K-04 · CLOSED by migration 138 (owner Decision A pulled BIL-3 into V5 P1).
    //
    // This is the VERIFIED IN CI rung. QA_CLOSURE_STANDARD §2 defines that state
    // as "an automated check fails against the pre-fix tree and passes against
    // the post-fix tree, IN CI", proving "a standing guard that a future edit
    // cannot silently undo".
    //
    // The live suite d11 CANNOT serve that purpose, and the distinction matters:
    // d11's verdict is decided by QA's DATABASE state, not by the checked-out
    // tree, so it returns 9/9 even against a tree with 138 deleted. It is
    // VERIFIED LIVE evidence, not a standing guard. THIS test is tree-sensitive
    // — _migration(138) throws outright on a pre-138 tree — so deleting or
    // hollowing out the migration turns CI red, which is the property the rung
    // is actually asking for.
    //
    // The previous version of this test was skipped AND vacuous: it asserted a
    // policy string was absent from migration 001, which is not what the defect
    // was or what 138 fixed. Replaced rather than un-skipped.
    test('K-04 a paid event registration cannot be self-granted, and an '
        'attendee cannot be reassigned', () {
      final sql = _migration(138);

      // The trigger exists and is a BEFORE trigger on both write paths. A
      // WITH CHECK alone cannot express immutability — it sees only NEW.
      expect(sql, contains('enforce_registration_integrity'));
      expect(sql, contains('CREATE TRIGGER trg_registration_integrity'));
      expect(sql, contains('BEFORE INSERT OR UPDATE ON public.event_registrations'),
          reason: 'INSERT matters as much as UPDATE: the self-granted paid '
              'ticket K-04 records is created, not edited');

      // The billing half — K-04 as originally registered.
      expect(sql, contains('NEW.paid IS DISTINCT FROM OLD.paid'));
      expect(sql, contains('NEW.payment_id IS DISTINCT FROM OLD.payment_id'));
      expect(sql, contains(RegExp(r'NEW\.paid\s*:=\s*false')),
          reason: 'a client INSERT must be forced unpaid, not merely checked');

      // The authorization half — the PII path recorded in V5 §25. user_id is
      // the whole of hosts_event_for()'s trust, and therefore the whole of
      // event_attendee_profiles' authorization.
      expect(sql, contains('NEW.user_id IS DISTINCT FROM OLD.user_id'),
          reason: 'without this a vendor reassigns a registration to any victim '
              'and reads their name and email through event_attendee_profiles');
      expect(sql, contains('NEW.event_id IS DISTINCT FROM OLD.event_id'));
      expect(sql, contains('NEW.qr_code IS DISTINCT FROM OLD.qr_code'),
          reason: 'qr_code is a bearer credential, the invite_token class');

      // The missing WITH CHECK the registry names as the remediation.
      final policy = sql.substring(
          sql.indexOf('CREATE POLICY "vendors check in own event registrations"'));
      expect(policy, contains('WITH CHECK'),
          reason: 'FOR UPDATE with no WITH CHECK makes Postgres reuse USING, '
              'which constrains event_id -> vendor_id and never user_id');
    });

    test('K-05 booking a session draws down a purchased session credit', () {
      final booking = _mobileFile(
          'lib/features/booking/presentation/booking_screen.dart');
      expect(booking, contains('client_session_credits'),
          reason: 'a bought session pack must be spent when a session is booked');
    }, skip: 'Open finding K-05 — session credits are granted but never consumed or enforced');

    // UN-SKIPPED 2026-10-06 (V5 §153). K-07 is REMEDIATED. The block used to catch
    // the Stripe error, log "continuing to mark local", and fall through to the
    // local update — so a failed remote cancel still flipped the row to `canceled`,
    // ended the coaching relationship and notified the coach, while Stripe kept
    // billing. The customer paid for access they no longer had.
    //
    // These assertions are deliberately about the CONTROL FLOW, not the wording.
    // Checking only that a log string is absent would pass if someone deleted the
    // message and kept the fall-through, which is the defect.
    test('K-07 a failed Stripe cancel does not revoke local entitlement', () {
      final fn = _edgeFn('cancel-subscription');
      final exec = fn
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      expect(exec, isNot(contains('continuing to mark local')),
          reason: 'marking the row canceled after Stripe refused leaves the '
              'customer paying for access they no longer have');

      // The guard must RETURN, not merely log.
      expect(exec, contains('stripe_cancel_failed'),
          reason: 'a failed remote cancel must surface as an error, not a success');

      // And it must return BEFORE the local revoke. Position is the contract:
      // a guard placed after the update would satisfy every `contains` above.
      final guard = exec.indexOf('stripe_cancel_failed');
      final revoke = exec.indexOf("status: 'canceled'");
      expect(guard, greaterThan(-1));
      expect(revoke, greaterThan(-1));
      expect(guard, lessThan(revoke),
          reason: 'the failure guard must precede the local entitlement revoke — '
              'otherwise the row is already flipped by the time it fires');
    });

    test('K-07 cancelling twice is idempotent, not an error', () {
      final fn = _edgeFn('cancel-subscription');
      final exec = fn
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      // A retry after a successful first attempt must not 502. Stripe signals
      // "already gone" two ways and both must be treated as success, or the fix
      // for K-07 would make a second cancel permanently fail.
      expect(exec, contains('resource_missing'),
          reason: 'a subscription Stripe no longer holds is already in the desired state');
      expect(exec, contains("'canceled'"),
          reason: 'a subscription Stripe still holds but reports canceled is also already done');
      expect(exec, contains('alreadyGone'),
          reason: 'the idempotent path must be explicit, not incidental');
    });

    test('K-09 losing the coach plan restores the free client capacity', () {
      final hook = _edgeFn('stripe-webhook');
      final deletedBranch = hook.substring(hook.indexOf('customer.subscription.deleted'));
      expect(deletedBranch, contains('max_clients'),
          reason: 'a coach who stops paying keeps an Elite roster forever');
    }, skip: 'Open finding K-09 — max_clients is raised on purchase and never lowered');

    test('K-12 verify_jwt is declared for the webhook in config.toml', () {
      final cfg = _repoFile('supabase/config.toml');
      expect(cfg, contains('[functions.stripe-webhook]'));
      expect(cfg, contains('verify_jwt = false'),
          reason: 'a redeploy without --no-verify-jwt silently 401s every '
              'Stripe delivery and no entitlement is ever granted again');
      // UN-SKIPPED 2026-09-30 (V5 §66). The skip read "config.toml declares no
      // per-function verify_jwt"; config.toml now declares it for EVERY
      // function explicitly, and this assertion passes. Note what it does and
      // does NOT claim: config.toml's own header records that declaring
      // verify_jwt does not close EDGE-1/EDGE-2, and that the posture reaches
      // an environment only via `supabase functions deploy`. This guards the
      // COMMITTED declaration, which is exactly what it always asserted.
    });

    test('K-ENV-1 the entitlement QA harness cannot target production', () {
      final tool = _mobileFile('tool/qa_entitlements.dart');
      expect(tool, isNot(contains('nxdbooufqzkpslkcogxc')),
          reason: 'a script named qa_* must not seed subscriptions into the '
              'production project');
      // UN-SKIPPED 2026-09-30 (V5 §66). ENV-5 remediated this: the harness
      // takes its target from QA_URL/QA_ANON with no default and refuses by
      // ALLOWLIST via tool/qa_target.dart. The production ref survives only in
      // qa_target.dart, named so the refusal can say what it refused -- not in
      // qa_entitlements.dart, which is what this asserts. Leaving it skipped
      // left the guard against seeding PRODUCTION switched off.
    });
  });
}
