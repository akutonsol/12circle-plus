# Build-time environment configuration

Every backend value the Flutter client uses is chosen at **build time** via
`--dart-define`, so a QA binary can never reach production data. The resolver
lives in [`lib/core/config/app_env.dart`](../lib/core/config/app_env.dart).

```bash
flutter run   -d chrome --dart-define-from-file=dart_defines/dev.json
flutter build web       --dart-define-from-file=dart_defines/qa.json
flutter build web       --dart-define-from-file=dart_defines/prod.json
```

## Defines

| Define | Meaning | Client-safe? |
|---|---|---|
| `APP_ENV` | `dev` \| `qa` \| `prod`. Unknown values fail the build. **Absent resolves to `dev`; absent in a release build fails the build.** | n/a |
| `SUPABASE_URL` | Supabase project URL for the environment. | yes |
| `SUPABASE_ANON_KEY` | Supabase publishable/anon key (RLS-protected). | yes |
| `STRIPE_PK` | Stripe **publishable** key (`pk_test_…` / `pk_live_…`). Never the secret key. | yes |
| `API_BASE_URL` | Base URL of the 12 Circle NestJS API. Hosts the AI endpoints. | yes |

An empty value falls back to that environment's default. **No environment ships
a backend default** — every environment, production included, must be pointed at
its Supabase project explicitly by its define file. A build that was not told
where to point does not start: `main()` throws with the list of missing
settings rather than falling through to somebody's real data.

`prod` used to be the exception: the production URL, anon key and Stripe key
were compiled into `app_env.dart` as the fallback for an unset `APP_ENV`, so
every `flutter run`, `flutter test` and IDE launch that omitted
`--dart-define-from-file` connected to production (ENV-4, P0). Those three
constants now live in `prod.json` and nowhere else.

## What must never be here

Server secrets — the Anthropic API key above all. The AI nutrition feature
calls `POST {API_BASE_URL}/ai/nutrition/message` on the NestJS API, which holds
`ANTHROPIC_API_KEY` server-side. `test/unit/client_secret_hygiene_test.dart`
and `tool/check_web_build_secrets.sh` fail the build if a secret leaks into the
client.

## Filling these in

`dev.json` and `qa.json` are committed with the values their project needs;
`prod.json` carries the production project. Anything you would rather not
commit can be left empty and passed from a CI secret store instead:

```bash
flutter build web \
  --dart-define=APP_ENV=qa \
  --dart-define=SUPABASE_URL="$QA_SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$QA_SUPABASE_ANON_KEY" \
  --dart-define=STRIPE_PK="$QA_STRIPE_PK" \
  --dart-define=API_BASE_URL="$QA_API_BASE_URL"
```

## What is and isn't isolated

**Runtime configuration is fully isolated.** A `qa` build resolves only QA
values; it cannot reach the production Supabase project. `test/unit/env_config_test.dart`
covers this (`ENV-003 environment isolation`).

**The compiled bundle contains only the environment you built.** The
per-environment default table is now empty for all three environments, so the
only project strings in an artifact are the ones its own define file supplied.
A `qa` bundle contains no production URL or key; a bundle built with no defines
contains neither.

That was previously not true: the default table carried the production values
as constants, so dart2js kept them in every artifact regardless of target. It
was defensible on secrecy grounds — the production URL, anon key and Stripe
publishable key are public by design, and RLS is what protects the data — but
it was never defensible on *targeting* grounds, which is the half that mattered.
Either way `tool/check_web_build_secrets.sh` scans every build artifact for
credential material.
