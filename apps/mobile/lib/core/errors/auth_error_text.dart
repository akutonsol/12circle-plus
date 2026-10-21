// The text a user should see when an auth call fails.
//
// ── WHY THIS EXISTS ─────────────────────────────────────────────────────────
// Every auth screen passed the caught object itself into a SnackBar, so a user
// who mistyped a password was shown a Dart object dump:
//
//     AuthApiException(message: Invalid login credentials, statusCode: 400,
//     code: invalid_credentials)
//
// That is `AuthException.toString()` verbatim (gotrue-2.21.0,
// lib/src/types/auth_exception.dart). Confirmed at runtime on Android —
// emulator-5554, API 35 — see docs/MOBILE_QA_SWEEP_2026-09-22.md §23.
//
// ── NO COPY IS INVENTED HERE ────────────────────────────────────────────────
// `AuthException` already carries a `message` field, which gotrue documents as
// *"Human readable error message associated with the error."* The defect was
// never a missing string; it was stringifying the wrapper instead of reading
// the field the provider supplies. So this returns `message` and nothing else,
// and the wording of every auth error stays exactly what the auth provider
// chose.
//
// The single string this file introduces is the fallback below, which applies
// only to errors that are not `AuthException` and therefore carry no
// human-readable message at all. Showing those raw is the same defect.
//
// Diagnostics are not lost: call sites pass the original object to
// `reportError` (lib/core/observability/app_failure.dart), which is where the
// status code and error code belong — an operator's console, not a SnackBar.

import 'package:supabase_flutter/supabase_flutter.dart';

/// User-facing text for an auth failure. Never returns an object dump.
String authErrorText(Object? error) {
  if (error is AuthException) return error.message;
  return 'Something went wrong. Please try again.';
}
