// AI-001 … AI-004 — the AI nutrition client calls the 12 Circle API.
//
// The Anthropic integration lives behind NestJS now, so what the client must
// get right is: the right URL for the build's environment, the user's Supabase
// bearer token, no AI credential of its own, and sane failure handling.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/core/config/app_env.dart';
import 'package:circle_fitness/features/ai_nutrition/data/ai_nutrition_service.dart';

/// Captures the outgoing request and replies with a canned response.
class _RecordingAdapter implements HttpClientAdapter {
  final int statusCode;
  final Object body;
  RequestOptions? lastRequest;

  _RecordingAdapter({
    this.statusCode = 200,
    this.body = const {'text': 'Here is your meal plan.'},
  });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _qaConfig = EnvConfig(
  environment: AppEnvironment.qa,
  supabaseUrl: 'https://qa-ref.supabase.co',
  supabaseAnonKey: 'qa-anon-key',
  stripePublishableKey: 'pk_test_qa',
);

/// Resolves an environment ignoring this build's `--dart-define` values, so the
/// assertions describe the baked-in defaults under any define file.
EnvConfig resolveDefaults(String appEnv) => resolveEnvConfig(
      appEnv: appEnv,
      supabaseUrl: '',
      supabaseAnonKey: '',
      stripePublishableKey: '',
    );

AiNutritionService serviceWith(
  _RecordingAdapter adapter, {
  EnvConfig env = _qaConfig,
  String? token = 'supabase-access-token',
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return AiNutritionService(dio: dio, env: env, accessToken: () => token);
}

void main() {
  _ai005();

  // AI-001
  //
  // PD-A17 = A, resolved as A2 (V5 §46). These used to assert
  // `{API_BASE_URL}/ai/nutrition/message` on a NestJS API that was never
  // deployed — `API_BASE_URL` was empty in every environment, so this feature
  // could not work in any build. They now assert the Edge Function URL. The
  // rest of this file is UNCHANGED and still passes: the auth header, the
  // payload shape, the `{ text }` response and every status mapping are the
  // same, which is the evidence the port preserved the contract.
  group('AI-001 requests go to the ai-nutrition Edge Function', () {
    test('posts to {SUPABASE_URL}/functions/v1/ai-nutrition', () async {
      final adapter = _RecordingAdapter();
      await serviceWith(adapter).sendMessage(message: 'hi', history: []);

      expect(adapter.lastRequest!.uri.toString(),
          'https://qa-ref.supabase.co/functions/v1/ai-nutrition');
      expect(adapter.lastRequest!.method, 'POST');
    });

    test('it follows the build\'s own Supabase project, not a fixed host',
        () async {
      final adapter = _RecordingAdapter();
      const other = EnvConfig(
        environment: AppEnvironment.dev,
        supabaseUrl: 'https://dev-ref.supabase.co/',
        supabaseAnonKey: 'dev-anon-key',
        stripePublishableKey: 'pk_test_dev',
        );
      await serviceWith(adapter, env: other)
          .sendMessage(message: 'hi', history: []);

      // Note the trailing slash on the configured URL: it must not double.
      expect(adapter.lastRequest!.uri.toString(),
          'https://dev-ref.supabase.co/functions/v1/ai-nutrition');
    });

    test('a build with no Supabase URL fails before sending anything',
        () async {
      final adapter = _RecordingAdapter();
      final unconfigured = resolveDefaults('qa');

      await expectLater(
        serviceWith(adapter, env: unconfigured)
            .sendMessage(message: 'hi', history: []),
        throwsA(isA<AiNutritionException>()),
      );
      expect(adapter.lastRequest, isNull);
    });

    test('the anon key rides alongside the user token, and it is only the '
        'publishable one', () async {
      final adapter = _RecordingAdapter();
      await serviceWith(adapter).sendMessage(message: 'hi', history: []);

      expect(adapter.lastRequest!.headers['apikey'], 'qa-anon-key');
      expect(adapter.lastRequest!.headers['Authorization'],
          'Bearer supabase-access-token');
    });
  });

  // AI-002
  group('AI-002 authorization', () {
    test('sends the Supabase access token as a bearer token', () async {
      final adapter = _RecordingAdapter();
      await serviceWith(adapter).sendMessage(message: 'hi', history: []);

      expect(adapter.lastRequest!.headers['Authorization'],
          'Bearer supabase-access-token');
    });

    test('never sends an Anthropic credential header', () async {
      final adapter = _RecordingAdapter();
      await serviceWith(adapter).sendMessage(message: 'hi', history: []);

      final headers = adapter.lastRequest!.headers.keys
          .map((k) => k.toLowerCase())
          .toList();
      expect(headers, isNot(contains('x-api-key')));
      expect(headers, isNot(contains('anthropic-version')));
    });

    test('refuses to send when the user has no session', () async {
      final adapter = _RecordingAdapter();

      await expectLater(
        serviceWith(adapter, token: null)
            .sendMessage(message: 'hi', history: []),
        throwsA(isA<AiNutritionException>()),
      );
      await expectLater(
        serviceWith(adapter, token: '').sendMessage(message: 'hi', history: []),
        throwsA(isA<AiNutritionException>()),
      );
      expect(adapter.lastRequest, isNull);
    });
  });

  // AI-003
  group('AI-003 payload preserves the existing feature', () {
    test('carries the message and conversation history', () async {
      final adapter = _RecordingAdapter();
      await serviceWith(adapter).sendMessage(
        message: 'What should I eat post-workout?',
        history: [
          {'role': 'user', 'content': 'Hi'},
          {'role': 'assistant', 'content': 'Hello!'},
        ],
      );

      final body = adapter.lastRequest!.data as Map<String, dynamic>;
      expect(body['message'], 'What should I eat post-workout?');
      expect(body['history'], hasLength(2));
      expect(body['history'][1]['role'], 'assistant');
      expect(body.containsKey('image'), isFalse);
    });

    test('meal plan and grocery list prompts still round-trip', () async {
      final adapter = _RecordingAdapter();
      final service = serviceWith(adapter);

      final plan = await service.generateMealPlan(
        calories: 1800,
        protein: 140,
        carbs: 160,
        fat: 60,
        dietaryRestrictions: ['dairy-free'],
        days: 3,
      );
      expect(plan, 'Here is your meal plan.');
      var body = adapter.lastRequest!.data as Map<String, dynamic>;
      expect(body['message'], contains('3-day meal plan'));
      expect(body['message'], contains('dairy-free'));

      await service.generateGroceryList(mealPlan: 'DAY 1: eggs');
      body = adapter.lastRequest!.data as Map<String, dynamic>;
      expect(body['message'], contains('grocery list'));
      expect(body['message'], contains('DAY 1: eggs'));
    });

    test('returns the text field from the API response', () async {
      final adapter = _RecordingAdapter(body: {'text': 'Eat more protein.'});
      final reply =
          await serviceWith(adapter).sendMessage(message: 'hi', history: []);
      expect(reply, 'Eat more protein.');
    });
  });

  // AI-004
  group('AI-004 failures surface as actionable messages', () {
    test('401 asks the user to sign in again', () async {
      final adapter = _RecordingAdapter(statusCode: 401, body: {});
      await expectLater(
        serviceWith(adapter).sendMessage(message: 'hi', history: []),
        throwsA(isA<AiNutritionException>().having(
            (e) => e.message, 'message', contains('sign in again'))),
      );
    });

    test('503 reports a temporary outage', () async {
      final adapter = _RecordingAdapter(statusCode: 503, body: {});
      await expectLater(
        serviceWith(adapter).sendMessage(message: 'hi', history: []),
        throwsA(isA<AiNutritionException>().having(
            (e) => e.message, 'message', contains('temporarily unavailable'))),
      );
    });

    test('an empty reply is treated as a failure, not an empty chat bubble',
        () async {
      final adapter = _RecordingAdapter(body: {'text': ''});
      await expectLater(
        serviceWith(adapter).sendMessage(message: 'hi', history: []),
        throwsA(isA<AiNutritionException>()),
      );
    });

    test('no failure message leaks a credential', () async {
      for (final status in [401, 403, 429, 500, 503]) {
        final adapter = _RecordingAdapter(statusCode: status, body: {});
        try {
          await serviceWith(adapter).sendMessage(message: 'hi', history: []);
          fail('expected a failure for status $status');
        } on AiNutritionException catch (e) {
          expect(e.message, isNot(contains('sk-ant')));
          expect(e.message.toLowerCase(), isNot(contains('api key')));
        }
      }
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
// AI-005 · the SERVER half of the contract.
//
// PD-A17 = A via A2 (V5 §46/§47). The tests above prove what the client SENDS;
// these prove the Edge Function still honours it. They are the repository-native
// mechanism for Edge coverage — there is no Deno harness, and the other nineteen
// functions are covered exactly this way, by parsing index.ts.
//
// They are tree-sensitive: delete or hollow out the function and they fail. That
// is deliberate. The live QA probe in §47.3 is VERIFIED LIVE evidence and cannot
// serve as the CI rung, because its verdict comes from the deployed function
// rather than the checked-out tree.
// ───────────────────────────────────────────────────────────────────────────

Directory _repoRootDir() {
  var dir = Directory.current;
  while (!Directory('${dir.path}/supabase/functions').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not locate supabase/functions');
    }
    dir = parent;
  }
  return dir;
}

String _edgeFn(String name) {
  final f = File('${_repoRootDir().path}/supabase/functions/$name/index.ts');
  if (!f.existsSync()) {
    throw StateError('supabase/functions/$name/index.ts should exist');
  }
  return f.readAsStringSync();
}

String _configToml() =>
    File('${_repoRootDir().path}/supabase/config.toml').readAsStringSync();

void _ai005() {
  group('AI-005 the ai-nutrition Edge Function honours the ported contract', () {
    test('it is JWT-verified in config.toml', () {
      expect(_configToml(), contains('[functions.ai-nutrition]'));
      final block = _configToml().split('[functions.ai-nutrition]')[1];
      expect(block.split('[functions.')[0], contains('verify_jwt = true'),
          reason: 'it spends a paid Anthropic credential; an unauthenticated '
              'caller must never be able to spend it');
    });

    test('the persona lives server-side, not in the client', () {
      expect(_edgeFn('ai-nutrition'),
          contains('You are an expert AI Nutrition Coach for 12 Circle Fitness'));
    });

    test('the validation limits still match what the client relies on', () {
      final fn = _edgeFn('ai-nutrition');
      expect(fn, contains('MAX_MESSAGE_LENGTH = 8_000'));
      expect(fn, contains('MAX_HISTORY_TURNS = 40'));
      expect(fn, contains('MAX_HISTORY_CONTENT_LENGTH = 16_000'));
      expect(fn, contains('MAX_IMAGE_BASE64_LENGTH = 7_000_000'));
      for (final t in ['image/jpeg', 'image/png', 'image/gif', 'image/webp']) {
        expect(fn, contains("'$t'"));
      }
    });

    test('an unknown property is REFUSED, not ignored', () {
      expect(_edgeFn('ai-nutrition'), contains('should not exist'),
          reason: "reproduces Nest's forbidNonWhitelisted: a client must not be "
              'able to smuggle a field a later version might start honouring');
    });

    test('validation runs BEFORE the configuration check', () {
      // The ordering defect a QA probe caught (§47.3): checking the key first
      // turned five 400s into 503s on an unconfigured environment.
      final fn = _edgeFn('ai-nutrition');
      final validateAt = fn.indexOf('const invalid = validate(body)');
      final configAt = fn.indexOf("if (!ANTHROPIC_API_KEY) return json");
      expect(validateAt, greaterThan(-1));
      expect(configAt, greaterThan(validateAt),
          reason: "Nest's order is guard -> ValidationPipe -> service, so a "
              'malformed body is a 400 whether or not a key is configured');
    });

    test('upstream retry parity with the Anthropic SDK default is kept', () {
      // ai-nutrition.service.ts overrode neither maxRetries nor timeout, so it
      // inherited the SDK default of 2. A bare fetch would silently drop it.
      expect(_edgeFn('ai-nutrition'), contains('ANTHROPIC_MAX_RETRIES = 2'));
    });

    test('no failure path returns the credential or the upstream body', () {
      final fn = _edgeFn('ai-nutrition');
      expect(fn, contains("json({ error: 'AI is temporarily unavailable' }, 503)"));
      // The key may only ever be read into a request header.
      final leaks = RegExp(r'json\([^)]*ANTHROPIC_API_KEY').hasMatch(fn);
      expect(leaks, isFalse,
          reason: 'the key must never reach a response body');
    });
  });
}
