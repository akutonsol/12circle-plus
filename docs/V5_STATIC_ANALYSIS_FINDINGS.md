# V5 · STATIC-ANALYSIS FINDINGS — `use_build_context_synchronously`, recorded not fixed

**Status: recorded for authorization. Eight findings, none implemented.**

Found while sweeping `dart analyze` during the §210 work. Two of that sweep's findings *were*
fixed, because they were unambiguous and testable: the dead null check in `_swapExercise` (a real
behavioural defect) and a `duplicate_import`. `lib/` is now at **0 warnings**.

These eight are different: they are `info`-level, they sit in **user-facing payment and nutrition
flows**, they have **no widget coverage**, and the correct remediation is a product judgement
rather than a mechanical rewrite. They are written down rather than changed.

## Why not just fix them

Three reasons, and the third is the decisive one.

1. **The obvious fix changes behaviour.** Adding `if (!mounted) return;` before an unguarded use
   does not merely silence the analyzer — it skips work that previously ran.
2. **One of them is a payment flow.** `QA_CLOSURE_STANDARD.md` §2.1 puts
   **Billing / entitlement** on its own ladder, requiring VERIFIED LIVE against Stripe **test
   mode** and VERIFIED END-TO-END *"for anything that moves money"*. A blind edit there is not a
   hygiene change.
3. **They cannot be verified here.** `flutter test` fails outright at the asset-copy stage —
   *"The target device is full"*, `errno 28`, at ~132 MiB free. So a change would be committed
   unexecuted, in a user-facing flow, with no existing test to catch a regression. That is the
   combination worth refusing.

## Finding 1 — `upgrade_screen.dart:172` · a payment flow, no guard at all

```dart
if (onMembership) {
  final result = await paymentSvc.changeMembership(p.kind!);   // ← the gap
  …
  // 'needs_checkout' or 'error' → fall through to checkout.
}
final ok = await launchCheckout(context, ref, kind: p.kind!);  // ← context after the await
if (!mounted) return; // embedded checkout navigated away; success screen refreshes
```

**Distinct from the other seven:** the analyzer reports no guard here at all, where the others are
"guarded by an unrelated `mounted` check". The context reaches `launchCheckout` after
`changeMembership` has been awaited, with nothing between.

**And the existing comment is why this is not a one-line fix.** *"embedded checkout navigated
away"* says `launchCheckout` **itself** unmounts the widget — which is precisely why the guard is
placed *after* it. So the question a `if (!mounted) return;` at line 172 would silently answer is:
**if the client navigated away during the membership change, should checkout still launch?**

| option | consequence |
|---|---|
| `1` guard before line 172 | a client who left mid-change gets no checkout. Correct if the intent is "no UI, no purchase" |
| `2` leave it, and record the gap | current behaviour: checkout launches, then the post-await guard returns |
| `3` restructure so checkout does not need a `BuildContext` | removes the class entirely; the largest change |

**This is a billing decision, not a lint.** Recommendation withheld.

## Findings 2–8 — context used *after* `Navigator.pop`

`meals_dashboard_screen.dart:832,833,869,870` · `nutrition_screen.dart:299,301` ·
`coach_dashboard_screen.dart:864`

Six of the seven share one shape:

```dart
if (!mounted) return;              // the guard IS present
setState(() => _saving = false);
widget.onLogged();
final ctx = context;               // captured deliberately
Navigator.pop(ctx);                // this route is removed
FoodAddedDialog.show(ctx, …);      // ← ctx used after its route is gone
```

**The hazard is not the missing guard — it is using a context after popping its route.** Once
popped, the element owning `ctx` is being deactivated, and `showDialog` against it can raise
*"Looking up a deactivated widget's ancestor"*. It frequently appears to work, because the
ancestor lookup resolves before the pop animation finishes, which is exactly what makes it a
latent fault rather than a visible one.

**The `final ctx = context` capture looks deliberate**, so this was written knowingly. That is a
reason to ask rather than to overwrite.

**Smallest safe remediation:** resolve the navigator and the surviving context *before* the pop —

```dart
final nav = Navigator.of(context);
final host = nav.context;   // outlives the popped route
nav.pop();
FoodAddedDialog.show(host, …);
```

**The caveat that makes this a decision:** `host` is a **different** ancestor from `ctx`, so the
dialog mounts under a different subtree. Inherited widgets — theme, media query, any
`Provider`/`Consumer` scope between them — resolve differently. Whether that is acceptable is a
UI question, and there is no widget test on either screen to detect a change.

## What is requested

1. **Finding 1** — a billing decision: option `1`, `2` or `3`.
2. **Findings 2–8** — authorization to apply the navigator-capture rewrite, **together with**
   widget coverage for the two nutrition log paths, so the change is verifiable rather than
   plausible.
3. Or a ruling that `use_build_context_synchronously` is accepted at `info` for these flows, in
   which case they should be suppressed **at the line** with a reason, so the sweep does not
   rediscover them.

**Nothing in this document was implemented.** The two unambiguous findings from the same sweep
were fixed and are recorded at §210; `lib/` carries **0 warnings** and **66 `info`**, of which
these eight are the only correctness class — the remaining 58 are style
(`curly_braces_in_flow_control_structures`, string interpolation, naming, `use_super_parameters`,
doc-comment form).
