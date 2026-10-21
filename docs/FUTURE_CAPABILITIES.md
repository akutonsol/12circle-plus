# 12 Circle Fitness — Future Capabilities Register

**Read-only audit deliverable.** Baseline `fbee6d5`.

These are capabilities implied by code, dependencies, schema or approved roadmap documents
that the current system **cannot support**. They are deliberately kept **separate from the
missing-screen register**: a future capability is not a missing screen, and per the audit
instruction **none of these should be removed**. They are implementation candidates.

---

## 1 · Capabilities with code already on disk

| ID | Capability | What exists | What is missing |
|---|---|---|---|
| **FC-01** | **Wearable / health ingestion** | `/integrations` offers Apple Health, Google Fit, Garmin, Strava and Polar with OAuth URLs | Writes only a `connected` flag that nothing but a badge count reads. **No `health`/HealthKit package in `pubspec.yaml`**, no HealthKit usage string, no ingestion path, no metrics tables |
| **FC-02** | **Native social sign-in** | `google_sign_in`, `sign_in_with_apple`, `crypto` are all declared dependencies | **Zero imports.** Both providers actually run through Supabase `signInWithOAuth` web redirect — the form Apple review rejects on iOS. The three dependencies together are the fingerprint of a surface planned and never built |
| **FC-03** | **Real scannable QR tickets** | `mobile_scanner` installed; `qr_code` and `checked_in_at` columns exist | The ticket QR is a **hand-drawn visual** (`event_ticket_screen.dart:213`); the only scanner reads food barcodes |
| **FC-04** | **Localisation** | — | No `flutter_localizations`, no `intl`, no ARB files; all strings are literals. Settings shows a dead "Language" row |
| **FC-05** | **Theme switching** | — | App is hard-dark; palettes are per-file `const Color` constants. Settings shows Dark Mode as static `ACTIVE` text |
| **FC-06** | **Data export** | Promised in the privacy policy | No code path anywhere |
| **FC-07** | **Deep linking / push-open-to-screen** | — | No intent filters, no URL schemes, no notification→route dispatch — **and no path parameters on any of the 91 routes**, so no entity is addressable. This is the prerequisite for FC-08 |
| **FC-08** | **Communication types beyond `weekly_review`** | `096:18` declares `daily_brief \| monthly_report \| goal_review \| risk_alert \| celebration` | Only `create_weekly_review()` exists. Depends on MSR-02 (a client inbox) to be visible at all |
| **FC-09** | **Prediction-vs-reality & decision analytics** | `record_prediction` is called, so history accrues | `predictions` and `decision_traces` have **zero readers**; `decision_analytics` is never invoked |
| **FC-10** | **Unused animation dependencies** | `confetti`, `animations` declared | Zero imports. Note `confetti` is **actively contradicted** by spec text quoted in four source files ("No confetti.") — a candidate for removal rather than build |
| **FC-11** | **Unused storage/state dependencies** | `flutter_secure_storage`, `shared_preferences` declared | Zero imports. Settings toggles that fail to persist (MSR-11) suggest an intended consumer |

---

## 2 · Roadmap-only capabilities (approved, not authorised)

| ID | Capability | Source | Current reality |
|---|---|---|---|
| **FC-12** | **Wearable Intelligence** | `docs/ROADMAP_WEARABLE_INTELLIGENCE.md` — *"APPROVED — FUTURE BUILD / NOT AUTHORIZED YET"*, 10 waves | Nothing built. Superset of FC-01 |
| **FC-13** | **Specialist training agents** — Strength, Pilates, Yoga, Conditioning, Functional, Mobility/Recovery | `docs/ROADMAP_SPECIALIST_TRAINING_AGENTS.md`; also `AG-13` in `COWORK_AGENT_REGISTRY.md` | One `/ai-coach` screen and one `ai_profiles.coach_persona` column |
| **FC-14** | **AI cost ledger / usage wallet / model routing / cost dashboard** | `docs/ROADMAP_AI_MONETIZATION_UNIT_ECONOMICS.md` | **No cost or usage table in any of the 132 migrations.** 19 edge functions call models unmetered — this is an uncontrolled-spend exposure, not merely a missing feature |

---

## 3 · Declared-but-unreachable infrastructure

Recorded here because each names a surface that does not exist.

| Item | Evidence | Note |
|---|---|---|
| `notify-coach-email` edge function | `supabase/config.toml:115` states it "has no caller in the codebase" | Reads **no Authorization header**, so the anon key reaches it, and it interpolates caller-controlled input raw into an email sent to every coach. **Security exposure, not a feature gap** |
| `send-checkin-reminder` edge function | `config.toml:122`; its own header documents a `net.http_post` cron | **Never scheduled** — that cron exists in no migration. Also unauthenticated |
| `create-portal-session` return URL | Returns to `https://12circle.app/account` | **There is no `/account` route** |
| `create-checkout` fallback URLs | Omit the `/#/` prefix the Flutter web build requires | App-supplied URLs are correct; the function's defaults 404 |
| `send-invite-email` | Builds `/#/signup?invite=<token>` | **Nothing in `lib` reads an `invite` query parameter** (see MSR-29) |
| Two hand-written HTML pages | `web/stripe_checkout.html`, `web/checkout_complete.html` | Real surfaces users land on. No Dart, no route, no Scaffold — invisible to any code-based screen inventory |

---

## 4 · Dependency status summary

**9 of 25 declared dependencies have zero imports:** `google_sign_in`, `sign_in_with_apple`,
`crypto`, `flutter_secure_storage`, `shared_preferences`, `confetti`, `animations`,
`riverpod_annotation`, `cupertino_icons`.

`riverpod_annotation` and `cupertino_icons` are ordinary tooling/transitive entries. The
other seven each map to a capability above.

---

## 5 · Dependency order

Several of these cannot be built independently:

```
FC-07 (path params + deep links)
  └─> MSR-10 notification routing
  └─> MSR-29 invite acceptance
  └─> entity-addressable screens generally

FC-01 (health ingestion)
  └─> FC-12 wearable intelligence

MSR-02 (client inbox)
  └─> FC-08 communication types

FC-14 (cost ledger)
  └─> any further AI surface, on unit-economics grounds
```

**FC-07 is the structural prerequisite.** Until routes take parameters, four separate items
on this register and in the missing-screen register cannot be built at all.
