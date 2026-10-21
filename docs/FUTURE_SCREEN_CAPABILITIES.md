# 12 Circle Fitness — Future Screen Capabilities

**Category H.** Functionality appearing in the designs, the schema or the dependency set that
the current codebase **cannot support**. Baseline `0aa844a`.

Per the directive these capabilities are **PRESERVED, not designed downward**. A design may
legitimately reveal future product capability. We are separating **screen-design completion**
from **feature/backend implementation**; nothing here blocks the design phase.

---

## 0 · Resolved since the previous pass

| Was | Now |
|---|---|
| **OD-38** reference images missing — blocked all design acceptance | **RESOLVED** — 110/110 regenerated from the board; they are derived artifacts |
| **OD-36** disk 98% full blocked all runtime verification | **CLEARED** — 5.6 GB free, 76% used |

## 1 · Capabilities attached to a screen that must still be designed

| ID | Capability | Screen | Design evidence | Missing capability | Domain model | Data source | Persistence | Security | Stub for QA? | Post-QA requirement |
|---|---|---|---|---|---|---|---|---|---|---|
| **H-01** | Scannable entry pass | D-04 class check-in pass | `class_detail_screen.dart:272-279` promises *"Show QR code at check-in"* | encoded, single-use QR | `ClassPass{bookingId, code, issuedAt, usedAt}` | new RPC `issue_class_pass` / `redeem_class_pass` | **`class_bookings.qr_code` does not exist** | a pass is a bearer token — single-use, coach-side redemption authority | ✅ static placeholder, clearly marked | real encoded redeemable pass |
| **H-02** | Pass scanning | attendee check-in | `020_vendor_portal.sql:13` has `qr_code` + `checked_in_at`; `mobile_scanner` installed but only reads **food barcodes** | camera scan → redeem | reuse H-01 | `redeem_class_pass` | exists | redemption restricted to that class's coach/vendor | ✅ manual toggle already stands in | depends on H-01 |
| **H-03** | Client-readable communications | D-02 inbox | `096_communication_engine.sql:13-29` | client SELECT + read receipts | `Communication{…, readAt}` | select on `communications` | **no `read_at` column** | **needs a client read policy** — today coach-written only | ✅ seed against existing QA identities | read receipts |
| **H-04** | Moderation pipeline | D-01 report/moderate | `post_card.dart:113` no-op | report intake, block, hide, remove | `Report{…}`, `Block{…}` | new RPCs | **new tables** | blocks must filter reads; reporter identity must not leak | ⚠ intake only — **enforcement must not be faked** | full pipeline. **App-store gate** |
| **H-05** | Account erasure & export | D-05 | `privacy_policy_screen.dart:87` | cascading erase + export bundle | — | new edge function | cascade across ~40 user-keyed tables | **highest risk here** — irreversible; must not orphan coach/billing rows; export must not leak another user's data | ❌ **must not be stubbed** — a fake delete is worse than none | real erase + export. **Store gate 5.1.1(v)** |
| **H-06** | Periodic AI briefs | DC-10, DC-11 | FIT-103 *"today"* 0/5, FIT-104 *"the week"* 0/5 | scheduled brief generation | reuse `communications` types | `096:18` declares `daily_brief \| monthly_report \| goal_review \| risk_alert \| celebration` | exists | per-user scoping | ✅ seed sample briefs | only `create_weekly_review()` exists today |

## 2 · Capabilities with no screen attached

| ID | Capability | Status |
|---|---|---|
| **H-07** | **Path parameters + deep links** | **The structural prerequisite.** No route takes a parameter, so no entity is addressable. Blocks notification→screen routing, invite acceptance, and routing the 9 push-only screens |
| **H-08** | Health / wearable ingestion | `/integrations` ships 5 providers writing only a `connected` flag; **no `health` package in `pubspec.yaml`**. Roadmap: `ROADMAP_WEARABLE_INTELLIGENCE.md` — *"APPROVED — FUTURE BUILD / NOT AUTHORIZED YET"* |
| **H-09** | Native social sign-in | `google_sign_in`, `sign_in_with_apple`, `crypto` declared with **zero imports** — both providers run through Supabase's web redirect, the form Apple review rejects on iOS |
| **H-10** | Localisation | No `flutter_localizations`, no `intl`, no ARB files. The Settings "Language" row has **no `onTap`** |
| **H-11** | Theming | App is hard-dark; palettes are per-file `const Color`. "Dark Mode" is static `ACTIVE` text |
| **H-12** | Specialist training agents | `ROADMAP_SPECIALIST_TRAINING_AGENTS.md`; today one `/ai-coach` and one `ai_profiles.coach_persona` column |
| **H-13** | AI cost ledger / usage wallet | **No cost or usage table in any of the 132 migrations** while 19 edge functions call models unmetered — an uncontrolled-spend exposure |
| **H-14** | Prediction-vs-reality analytics | `record_prediction` is called so history accrues; `predictions` and `decision_traces` have **zero readers** |
| **H-15** | Data export | Promised in the privacy policy; no code path (see H-05) |

## 3 · Design elements preserved and deliberately not built

| Element | Declared in | Why unsupported |
|---|---|---|
| Sample social rows (*"Priya Hit 70 kg…"*, *"Tues Lifters Sam…"*) | FIT-005 | **Sample data, a ceiling not a backlog** — the repo's own tool says matching them requires fabricating exact rows |
| *"You're 3rd of 24 in your pod"* | FIT-005 | pod standings have no provider; `/pods` is unreachable |
| *"4 places left"* live capacity | FIT-005, FIT-027 | capacity exists; live remaining-places is not computed |
| AI meal scan | FIT-020 | embedded in `/log-meal`, an orphaned stub |
| **Loading & failure pattern** | **FIT-022** | **the largest preserved gap** — no shared state widget exists, zero offline handling, 25 screens with no error state |

## 4 · Dependency order

```
H-07 path params  ─┬─> notification routing
                   ├─> invite acceptance
                   └─> routing the 9 push-only screens
H-01 pass ─> H-02 scanning
H-03 client read ─> D-02 inbox ─> H-06 periodic briefs
H-04 moderation ─> D-01 report, and gates D-03 coach reviews (UGC)
H-08 health ingestion ─> wearable intelligence
H-13 cost ledger ─> any further AI surface, on unit-economics grounds
```

**H-07 is the structural prerequisite.** None of these blocks the design phase — all can be
designed now and implemented later.
