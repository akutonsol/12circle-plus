# QA environments & AI secret handling

How to stand up an isolated automated-QA run of 12 Circle, and where each
credential is allowed to live.

## The two halves

| | Flutter client (`apps/mobile`) | NestJS API (`apps/api`) |
|---|---|---|
| Configured by | `--dart-define` at **build** time | environment variables at **run** time |
| Environments | `dev`, `qa`, `prod` (`APP_ENV`) | `dev`, `qa`, `prod` (`APP_ENV`) |
| Resolver | [`lib/core/config/app_env.dart`](../apps/mobile/lib/core/config/app_env.dart) | [`src/config/api-config.ts`](../apps/api/src/config/api-config.ts) |
| Reference | [`dart_defines/README.md`](../apps/mobile/dart_defines/README.md) | [`.env.example`](../apps/api/.env.example) |

An unknown environment name is a hard error on both sides — a typo fails the
build or the boot instead of silently selecting production.

## Standing up a QA run

1. **API** — copy `apps/api/.env.example` to `apps/api/.env`, set `APP_ENV=qa`,
   the QA `SUPABASE_JWT_SECRET`, and `ANTHROPIC_API_KEY`. Start with
   `npm run api`. Boot logs a redacted config summary and warns about anything
   required that is missing.

2. **Client** — build against the QA backend:

   ```bash
   flutter build web \
     --dart-define=APP_ENV=qa \
     --dart-define=SUPABASE_URL="$QA_SUPABASE_URL" \
     --dart-define=SUPABASE_ANON_KEY="$QA_SUPABASE_ANON_KEY" \
     --dart-define=STRIPE_PK="$QA_STRIPE_PK" \
     --dart-define=API_BASE_URL="$QA_API_BASE_URL"
   ```

   **No environment ships a backend default** (ENV-4). Every build — production
   included — must be given its project explicitly, and one that isn't fails at
   startup instead of falling through to production. An absent `APP_ENV`
   resolves to `dev`, which can reach nothing; an absent `APP_ENV` in a release
   build is a hard error. The production values live in
   `dart_defines/prod.json`, not in the binary.

3. **Verify the artifact** — `npm run check:web-secrets` scans every file the
   build emitted for credential material.

## Where credentials live

| Credential | Where | Client-safe |
|---|---|---|
| Supabase URL + publishable/anon key | client build define | yes — RLS-protected |
| Stripe **publishable** key | client build define | yes |
| Supabase JWT signing secret | API env (`SUPABASE_JWT_SECRET`) | **no** |
| Anthropic API key | API env (`ANTHROPIC_API_KEY`) | **no** |

The AI Nutrition Coach used to call `api.anthropic.com` directly from the
Flutter client with the key compiled in. It now posts to
`POST {API_BASE_URL}/ai/nutrition/message`; the API verifies the caller's
Supabase session and calls Claude with the server-held key. The key is never
returned in a response and never logged.

## Guards

| Guard | What it proves |
|---|---|
| `apps/mobile/test/unit/env_config_test.dart` | Every environment resolves; QA can't reach prod; no secret in client config |
| `apps/mobile/test/unit/client_secret_hygiene_test.dart` | No Anthropic key, host or key header anywhere in `lib/` |
| `apps/mobile/test/unit/ai_nutrition_client_test.dart` | The client calls the API with a Supabase bearer token and no AI credential |
| `apps/api/src/config/api-config.spec.ts` | API env resolution, required-setting reporting, log redaction |
| `apps/api/src/ai/ai.controller.spec.ts` | The AI endpoint rejects missing / forged / expired / anon / service-role tokens |
| `apps/api/src/ai/ai-nutrition.service.spec.ts` | The key comes from server config only and never leaks through a response or log |
| `apps/api/test/ai.e2e-spec.ts` | The route is closed end-to-end through the real application graph |
| `apps/mobile/tool/check_web_build_secrets.sh` | A compiled web bundle contains no credential material |

Run everything with `npm test` from the repository root.

## Deploying Edge Function configuration — never `config push` (W1B-N5)

`supabase/config.toml` now declares `verify_jwt` per function (E-09). That block
reaches an environment **only** through the deploy path the release architecture
already uses:

```bash
supabase functions deploy <function-name>   # reads that function's verify_jwt
```

**Never run `supabase config push`.** It writes the *entire* `config.toml` to the
linked project, and this file deliberately declares almost no `[auth]`/`[db]`
settings — a push would silently reset QA's live auth configuration (site URL,
redirect allowlist, JWT expiry, providers, email templates) to CLI defaults.
This prohibition stands until `config.toml` has been reconciled with QA's live
configuration and the reconciliation is recorded; it is a **Wave 5.0 entry
precondition** (`MASTER_REMEDIATION_REGISTRY.md` §7.7, W1B-N5). Function
deployment itself remains gated to Wave 5 regardless.
