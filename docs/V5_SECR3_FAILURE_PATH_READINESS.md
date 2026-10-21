# SEC-R3 / F-J-07 · failure-path remediation readiness

**No product change was made.** The fix is **not startable** under the governing sequence, and the
evidence for that is below. SEC-R3's registry status and evidence count are untouched; neither it
nor SEC-R2 is promoted.

---

## 1 · Authority and sequencing — the fix is NOT startable

| link | source, verbatim |
|---|---|
| Wave 3B is **strictly ordered** | `MASTER_REMEDIATION_WAVES.md`: *"**Strictly ordered — this is Workstream B's sequence and it is correct:**"* |
| the Dart service sweep is **3B-4** | *"**3B-4 · Service-layer sweep (rule L2).** `EC-11` (after 3A-5), `EC-13`, `EC-15`, `EC-16`, `EC-18`, `EC-19`, `EC-21`, `EC-25`, `F-J-16`"* |
| 3B-4 therefore follows **3B-1** | the order above; the only stated parallelism is *"**Parallel-safe within 3B:** the sites inside 3B-2 and 3B-4 touch disjoint service files"* — parallel **with each other**, not with 3B-1 |
| 3B-1 is **blocked** | *"**Depends on CON-03** (the serializer mismatch that triggers it today) **and on SEC-R2** (the trigger throw that is the second trigger)."* |
| SEC-R2 is unresolved | its registry row still reads `❌ **absent**` for `VERIFIED END-TO-END`, **4 of 5 present** |
| CON-03 is unresolved | ~~*"prod type unknown"*, and Gate 9B forbids reading production to establish it~~ **CORRECTED 2026-10-13 — see `V5_CON03_AUTHORITY_DETERMINATION.md`.** CON-03 is **not** production-blocked: `PD-A22`'s *Proceed?* column reads **"Yes — via (b)"**, authorizing a forward migration that converges from either type **without inspecting**. It is unwritten work, not a blocked decision. **SEC-R2 remains 3B-1's binding constraint.** |

**So the chain is: the SEC-R3 Dart fix ← 3B-4 ← 3B-1 ← {CON-03, SEC-R2}.** Two gates behind, and
neither gate is mine to open.

**A dependency worth stating plainly:** SEC-R3's *acceptance* needs this fix, and this fix needs
3B-1, which needs **SEC-R2**. So **SEC-R3 is strictly behind SEC-R2** — they cannot be accepted in
either order or in parallel. That was not visible in Milestone 11's matrices.

**Not inferred from convenience:** the change being local, small, and offline-testable does not
make it startable. The sequence is explicit and the blocking edges are live.

---

## 2 · Call-site failure map — verified against current code

`lib/features/coach/data/coach_program_service.dart` — **11 swallow sites**, enumerated by
enclosing method:

| line | method | swallow |
|---|---|---|
| `:13` | `planProgram` | `catch (_) { return null; }` |
| `:28` | `createEngineProgram` | `catch (_) { return null; }` |
| `:54` | `createWeeklyReview` | `catch (_) { return null; }` |
| `:65` | `generateCommunication` | `catch (_) { return null; }` |
| `:73` | `updateCommunication` | `catch (_) { return false; }` |
| `:80` | `sendCommunication` | `catch (_) { return false; }` |
| **`:92`** | **`predictClient`** | `catch (_) { return null; }` ← **SEC-R3** |
| `:102` | `recordPrediction` | `catch (_) { return null; }` |
| `:113` | `submitWeeklyFeedback` | `catch (_) { return false; }` |
| **`:122`** | **`evaluateWeek`** | `catch (_) { return null; }` ← **SEC-R3** |
| **`:134`** | **`regenerateProgram`** | `catch (_) { return null; }` ← **SEC-R3** |

`build_workout`'s caller is in a **different file** — `custom_exercise_service.dart:505` — and is
therefore a separate site, not covered by the file above.

**Authorization is intact and must stay so:** every call uses the **public wrapper name**
(`rpc('predict_client')`, `rpc('evaluate_week')`), never `*_engine`. 116 published those wrappers
with `can_act_for` / `can_act_on_program`, so authorization remains a traversed link.

**Are failures surfaced?** No. At each site a thrown error becomes `null` or `false` —
**indistinguishable from a legitimate empty result**. There is no typed error, no result wrapper,
and no reporting call.

---

## 3 · The intended error contract already exists, and is unused

`lib/core/observability/app_failure.dart` supplies **`AppFailure`** and **`reportFailure()`** —
Wave **3B-0**, which is complete as specified. Its own header defines the rule it serves:

> *"§4 rule **O** — no swallow is sanctioned unless it records. A swallow that records is an
> engineering decision; a swallow that does not is an outage nobody will ever see."*

**`reportFailure` has zero call sites outside its own file.** That is not an oversight: the same
header says *"classifying and wiring the remaining ~234 swallow sites is **Phase B4** … and is
deliberately NOT done here."*

**So the contract to adopt is already chosen and in-tree.** The 3B-4 change is to make these sites
*record* and *distinguish* — not to invent a framework. Nothing new should be designed.

A distinction the eventual fix must preserve: `predictClient` returning `null` for *"this subject
has no prediction"* is **legitimate absence**; returning `null` because the RPC threw is **not**.
Only the second must change. Turning every `null` into an exception would be wrong.

---

## 4 · There is no safe offline test seam — and the smallest one, proposed

```dart
class CoachProgramService {
  final _db = Supabase.instance.client;   // field initializer
```

Constructing the service in a test runs `Supabase.instance.client`, which **throws** unless Supabase
is initialized. So the real implementation **cannot be exercised offline today**, and no test was
written against it. *(The same shape as `PaymentService`, which required `implements` + a fake for
the checkout tests.)*

**Smallest proposed seam** — optional injection, no behaviour change, no new dependency:

```dart
CoachProgramService([SupabaseClient? db]) : _db = db ?? Supabase.instance.client;
final SupabaseClient _db;
```

**Not implemented.** It touches the gated product file, and Section 3 asks that an absent seam be
*reported and proposed*, which is what this is.

---

## 5 · The failure-first tests, designed but not written

Each would be written **only after** the seam and the 3B-4 fix are authorized:

| # | assertion | why it cannot be vacuous |
|---|---|---|
| 1 | a successful wrapper response still returns the valid result | asserts the **specific labels** (`RECOVERY_PROTECTION`, `RECOVERY_REDUCTION`) are present, not merely that a map returned |
| 2 | a wrapper **failure** is distinguishable from legitimate absence | two separate cases — injected throw vs. an empty-but-successful response — must produce **different** caller-visible outcomes. A single-case test cannot pass |
| 3 | a failed safety input cannot become a benign default | asserts the caller receives an explicit failure, and that no recommendation renders |
| 4 | the failure branch was actually reached | asserts **both** the injected error identity **and** the observed result, so a test cannot pass by skipping the injection |
| 5 | authorization stays on the wrapper names | asserts the fake records `predict_client` / `evaluate_week`, and **never** a `*_engine` name |
| 6 | callers handle the failure state | asserts an explicit handled state, not an unhandled crash and not fabricated success |

The engine-level contract suite (`fj07-rule-accumulator-contract.sql`) is **retained unchanged**.
Its documented purpose is engine coverage — *"calls the ENGINES … authorization … deliberately not
re-tested here"* — so wrapper and service behaviour is covered **separately**, never by editing it.

---

## 6 · Minimum owner decision to unblock

**In order, because the order is forced:**

1. **CON-03** — **no owner decision needed.** Write the forward migration under the already-authorized
   route (b): converge from either type without inspecting production. *(Corrected 2026-10-13.)*
2. **SEC-R2** — authorize a live QA probe, then the per-row C1 acceptance ruling.
3. **3B-1** — becomes startable once 1 and 2 land.
4. **3B-4** — then startable; the seam and this fix land here.
5. **SEC-R3** — probe, then its own per-row C1 ruling.

**The shortest real unblock is CON-03**, because it is the only one of the five that needs neither a
probe nor a prior row.
