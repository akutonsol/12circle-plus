import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'widgets/intake_back_button.dart';
import 'widgets/intake_complete_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../scoring/data/score_engine.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/intake_data.dart';
import '../../coach/domain/coach_provider.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _bg      = Color(0xFF0A0A0B);
const _primary = Color(0xFFDDB7FF);
const _priCont = Color(0xFFB76DFF);
const _terCont = Color(0xFFD164E2);
const _tertiary = Color(0xFFF8ACFF);
const _surfC   = Color(0xFF171F33);
const _surfCH  = Color(0xFF222A3D);
const _surfCHH = Color(0xFF2D3449);
const _onSurf  = Color(0xFFDAE2FD);
const _onSurfV = Color(0xFFCFC2D6);
const _outline = Color(0xFF988D9F);
const _outlineV = Color(0xFF4D4354);
const _btnPurple = Color(0xFF7C3AED);
// ignore_for_file: unused_element, unused_element_parameter

// ── Main flow controller ──────────────────────────────────────────────────────
class IntakeFlowScreen extends StatefulWidget {
  const IntakeFlowScreen({super.key});

  @override
  State<IntakeFlowScreen> createState() => _IntakeFlowScreenState();
}

class _IntakeFlowScreenState extends State<IntakeFlowScreen>
    with WidgetsBindingObserver {
  late PageController _pageController;
  final _data = IntakeData();
  int _step = 0; // 0 = welcome, 1–11 = steps

  // Step 7 multi-select
  final Set<String> _challenges = {};

  bool _saving = false;
  bool _loading = true;

  static const int _totalSteps = 26;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    _loadProgress();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Persist whatever has been entered when the app is backgrounded / closed
    // (web fires this on tab hide), so nothing entered is lost on resume.
    if (!_loading &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive ||
            state == AppLifecycleState.hidden)) {
      _saveProgress();
    }
  }

  Future<void> _loadProgress() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    // Entering the flow means onboarding isn't done — flag it so re-login always
    // routes back here (covers closing before advancing past the first step).
    Supabase.instance.client
        .from('user_profiles')
        .update({'onboarding_complete': false})
        .eq('id', uid)
        .then((_) {}, onError: (_) {});
    try {
      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select(
            'onboarding_step, first_name, last_name, gender, date_of_birth, '
            'fitness_goal, activities, activity_level, '
            'training_days_per_week, training_location, nutrition_goal, '
            'protein_confidence, biggest_challenges, height_cm, '
            'weight_kg, weight_goal_kg, coaching_mode, '
            'parq_answers, medical_conditions, has_injuries, '
            'injury_locations, injury_description, experience_level, '
            'worked_with_coach_before, sleep_hours, stress_level, '
            'occupation, dietary_restrictions, food_allergies, '
            'target_timeline, consent_agreed',
          )
          .eq('id', uid)
          .maybeSingle();
      if (profile != null && mounted) {
        final savedStep = (profile['onboarding_step'] as num?)?.toInt() ?? 0;
        final saved = IntakeData.fromSupabase(profile);
        _pageController.dispose();
        _pageController = PageController(initialPage: savedStep);
        setState(() {
          // Identity — already captured at signup; prefill so the Profile step
          // doesn't ask for name/gender/DOB again.
          _data.firstName               = saved.firstName;
          _data.lastName                = saved.lastName;
          _data.gender                  = saved.gender;
          _data.dateOfBirth             = saved.dateOfBirth;
          _data.primaryGoal             = saved.primaryGoal;
          _data.activities              = saved.activities;
          _data.heightCm                = saved.heightCm;
          _data.weightKg                = saved.weightKg;
          _data.weightGoalKg            = saved.weightGoalKg;
          _data.activityLevel           = saved.activityLevel;
          _data.trainingDays            = saved.trainingDays;
          _data.trainingLocation        = saved.trainingLocation;
          _data.nutritionGoal           = saved.nutritionGoal;
          _data.proteinConfidence       = saved.proteinConfidence;
          _data.coachingMode            = saved.coachingMode;
          _data.parqAnswers             = saved.parqAnswers;
          _data.medicalConditions       = saved.medicalConditions;
          _data.hasInjuries             = saved.hasInjuries;
          _data.injuryLocations         = saved.injuryLocations;
          _data.injuryDescription       = saved.injuryDescription;
          _data.experienceLevel         = saved.experienceLevel;
          _data.workedWithCoachBefore   = saved.workedWithCoachBefore;
          _data.sleepHours              = saved.sleepHours;
          _data.stressLevel             = saved.stressLevel;
          _data.occupation              = saved.occupation;
          _data.dietaryRestrictions     = saved.dietaryRestrictions;
          _data.foodAllergies           = saved.foodAllergies;
          _data.targetTimeline          = saved.targetTimeline;
          _data.consentAgreed           = saved.consentAgreed;
          _challenges.addAll(saved.biggestChallenges);
          _step = savedStep;
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProgress() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final db = Supabase.instance.client;

    // Phase 1: ALWAYS persist the step + incomplete flag on their own. These two
    // columns can't fail on data-type drift, so resume works even if a data
    // field below is rejected by the (hand-built) schema.
    try {
      await db.from('user_profiles').update({
        'onboarding_step': _step,
        'onboarding_complete': false,
      }).eq('id', uid);
    } catch (_) {}

    // Phase 2: best-effort persist the collected intake data.
    try {
      _data.biggestChallenges = _challenges.toList();
      await db
          .from('user_profiles')
          .update(_data.toSupabasePartial(_step))
          .eq('id', uid);
    } catch (_) {}
  }

  void _next() {
    if (_step < _totalSteps) {
      setState(() => _step++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
      _saveProgress();
    } else {
      _finish();
    }
  }

  // Jump directly to a specific page — used to skip coach selection for
  // Self Guided and AI Guided modes.
  void _jumpToPage(int page) {
    setState(() => _step = page);
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
    );
    _saveProgress();
  }

  void _back() {
    if (_step > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
      setState(() => _step--);
    }
  }

  /// FIT-009 · "Intake complete". The flow used to `context.go('/home')` the
  /// instant the last answer saved, so the state the anchor draws never
  /// existed — the client's work ended in a screen transition.
  bool _done = false;

  /// EC-03 · set when the final save failed. While it is non-null the flow does NOT
  /// present itself as complete, and the person keeps a Retry affordance.
  String? _saveError;

  /// EC-03 · ONBOARDING NO LONGER MARKS ITSELF COMPLETE AFTER THE SAVE FAILS.
  ///
  /// This handler used to catch the upsert and then explicitly write
  /// `{'onboarding_complete': true, 'onboarding_step': 0}` — "so the user isn't looped
  /// back here on next login". The cost of not being looped back was everything the
  /// flow collected: PAR-Q answers, medical conditions, injuries, allergies, dietary
  /// restrictions, goal, experience **and consent** were discarded, while the person
  /// was recorded as fully onboarded and could never return to supply them.
  ///
  /// The registry names this the parent of CON-04, E-NUT-05, ERR-2 and DAT-2, and
  /// "the reason `risk_*` is frequently null" — the same NULL that EC-04 then rendered
  /// to the coach as a green LOW RISK badge (V5 §170).
  ///
  /// Being looped back is the CORRECT outcome of an unsaved intake: the data is
  /// genuinely missing and the flow is where it gets supplied. `_saveProgress`'s
  /// Phase 1 has already persisted `onboarding_step` with `onboarding_complete: false`
  /// (see above), so the person resumes where they were rather than starting over.
  ///
  /// TWO SIDE EFFECTS ALSO MOVED BEHIND THE SUCCESS PATH. `assessmentComplete()`
  /// awarded a score for an assessment that was not stored, and `generate_client_plan`
  /// built a program from answers the database never received. Neither should run over
  /// a failed save.
  Future<void> _finish() async {
    setState(() { _saving = true; _saveError = null; });
    final uid = Supabase.instance.client.auth.currentUser?.id;
    // EC-03 · THE ARM THE ORIGINAL FIX LEFT OPEN. The guard above used to be
    // `if (uid != null) { …save… }` with the completion state set unconditionally after
    // it — so a NULL uid skipped the save entirely and the flow still rendered
    // IntakeCompletePage. "Not saved because it failed" was fixed; "not saved because it
    // was never attempted" was not, and it is the same false success state over a weaker
    // premise: nothing was even tried.
    //
    // IT IS REACHABLE WITHOUT A SESSION EXPIRY. `/intake` is listed in the router's
    // `isAuthRoute` set (app_router.dart:203), so `!isAuthenticated && !isAuthRoute` does
    // NOT send an unauthenticated caller to /login — the route is deliberately open, and
    // `_loadProgress` already treats a null uid as "nothing to restore" and carries on.
    // A person can therefore answer all 26 steps, tap Finish, and be told they are done
    // while PAR-Q answers, injuries, allergies, dietary restrictions, goal, experience and
    // CONSENT are discarded. That is the registry's description of EC-03's parent defect,
    // which it names the parent of CON-04, E-NUT-05, ERR-2 and DAT-2.
    //
    // The message differs from the catch below because the cause differs and Retry alone
    // cannot fix it: a save needs a session. Retry is still offered, because a token
    // refresh between taps makes it work and withholding it would leave no way forward.
    if (uid == null) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = 'We could not save your answers because you are not signed in. '
              'Nothing was lost on this device — sign in on another tab or app and tap '
              'Retry.';
        });
      }
      return;
    }
    {
      _data.biggestChallenges = _challenges.toList();
      try {
        await Supabase.instance.client
            .from('user_profiles')
            .upsert({'id': uid, ..._data.toSupabase()});
      } catch (e) {
        // NOT marked complete. The intake is not finished, because it was not saved.
        if (mounted) {
          setState(() {
            _saving = false;
            _saveError = 'We could not save your answers. Nothing was lost on this '
                'device — tap Retry to try again.';
          });
        }
        return;
      }
      ScoreEngine().assessmentComplete(); // +25 (once)
      // Self/AI-Guided clients have no coach, so the system generates their plan
      // (workout program + nutrition targets + water goal + habits) from the
      // onboarding answers just saved. Coach-Guided clients get a coach-assigned
      // plan instead, so we skip generation for them.
      if (_data.coachingMode == 'self_guided' || _data.coachingMode == 'ai_guided') {
        try {
          await Supabase.instance.client.rpc('generate_client_plan');
        } catch (_) {/* generation must never block finishing onboarding */}
      }
    }
    // FIT-009 is a state, not a redirect. The board's note is explicit:
    // "Success is quiet: a mark, a sentence, what happens next. No confetti,
    // no celebration animation."
    if (mounted) setState(() { _saving = false; _done = true; });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: CircularProgressIndicator(color: _priCont),
        ),
      );
    }

    if (_done) return IntakeCompletePage(onGoHome: () => context.go('/home'));

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Atmospheric glows
          Positioned(top: -80, left: -80,
            child: _Glow(color: _priCont.withValues(alpha: 0.12), size: 360)),
          Positioned(bottom: -80, right: -80,
            child: _Glow(color: _terCont.withValues(alpha: 0.10), size: 420)),

          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // 0 — Welcome
              _WelcomePage(onStart: _next),
              // 1 — Profile Info (name, gender, dob)
              ProfileInfoPage(
                firstName: _data.firstName,
                lastName: _data.lastName,
                gender: _data.gender,
                dateOfBirth: _data.dateOfBirth,
                onChanged: (fn, ln, g, dob) { setState(() {
                  _data.firstName   = fn;
                  _data.lastName    = ln;
                  _data.gender      = g;
                  _data.dateOfBirth = dob;
                }); },
                onContinue: _next,
                onBack: _back,
              ),
              // 2 — PAR-Q Health Screening
              _PARQPage(
                answers: _data.parqAnswers,
                onChanged: (v) { setState(() => _data.parqAnswers = v); },
                onContinue: _next,
                onBack: _back,
              ),
              // 3 — Medical History
              _MedicalHistoryPage(
                selected: _data.medicalConditions,
                onChanged: (v) { setState(() => _data.medicalConditions = v); },
                onContinue: _next,
                onBack: _back,
              ),
              // 4 — Injuries & Limitations
              _InjuriesPage(
                hasInjuries: _data.hasInjuries,
                locations: _data.injuryLocations,
                description: _data.injuryDescription,
                onChanged: (hasI, locs, desc) { setState(() {
                  _data.hasInjuries       = hasI;
                  _data.injuryLocations   = locs;
                  _data.injuryDescription = desc;
                }); },
                onContinue: _next,
                onBack: _back,
              ),
              // 5 — Primary Goal
              _Step1Page(
                selected: _data.primaryGoal,
                onSelect: (v) { setState(() => _data.primaryGoal = v); },
                onContinue: _next,
                onBack: _back,
              ),
              // 6 — Activities (multi-select)
              _ActivitiesPage(
                selected: _data.activities,
                onToggle: (v) => setState(() {
                  final next = _data.activities.toList();
                  next.contains(v) ? next.remove(v) : next.add(v);
                  _data.activities = next;
                }),
                onContinue: _next,
                onBack: _back,
              ),
              // 7 — Target Timeline
              _TargetTimelinePage(
                selected: _data.targetTimeline,
                onSelect: (v) { setState(() => _data.targetTimeline = v); },
                onContinue: _next,
                onBack: _back,
              ),
              // 7 — Experience Level
              _ExperiencePage(
                experienceLevel: _data.experienceLevel,
                workedWithCoach: _data.workedWithCoachBefore,
                onChanged: (lvl, worked) { setState(() {
                  _data.experienceLevel       = lvl;
                  _data.workedWithCoachBefore = worked;
                }); },
                onContinue: _next,
                onBack: _back,
              ),
              // 8 — Height
              _HeightPage(
                heightCm: _data.heightCm,
                onHeightChanged: (v) { setState(() => _data.heightCm = v); },
                onContinue: _next,
                onSkip: _next,
                onBack: _back,
              ),
              // 9 — Weight
              _WeightPage(
                weightKg: _data.weightKg,
                heightCm: _data.heightCm,
                onWeightChanged: (v) { setState(() => _data.weightKg = v); },
                onContinue: _next,
                onSkip: _next,
                onBack: _back,
              ),
              // 10 — Target Weight
              _TargetWeightPage(
                currentWeightKg: _data.weightKg,
                goalWeightKg: _data.weightGoalKg,
                primaryGoal: _data.primaryGoal,
                onGoalChanged: (v) { setState(() => _data.weightGoalKg = v); },
                onContinue: _next,
                onSkip: _next,
                onBack: _back,
              ),
              // 11 — Weight Goal Summary
              _WeightGoalPage(
                weightKg: _data.weightKg,
                weightGoalKg: _data.weightGoalKg,
                primaryGoal: _data.primaryGoal,
                onContinue: _next,
                onBack: _back,
              ),
              // 12 — Activity Level
              _Step2Page(
                selected: _data.activityLevel,
                onSelect: (v) { setState(() => _data.activityLevel = v); },
                onContinue: _next,
                onBack: _back,
              ),
              // 13 — Training Frequency
              _Step3Page(
                selected: _data.trainingDays,
                onSelect: (v) => setState(() => _data.trainingDays = v),
                onContinue: _next,
                onBack: _back,
              ),
              // 14 — Training Location
              _Step4Page(
                selected: _data.trainingLocation,
                onSelect: (v) { setState(() => _data.trainingLocation = v); },
                onContinue: _next,
                onBack: _back,
              ),
              // 15 — Lifestyle
              _LifestylePage(
                sleepHours: _data.sleepHours,
                stressLevel: _data.stressLevel,
                occupation: _data.occupation,
                onChanged: (sleep, stress, occ) { setState(() {
                  _data.sleepHours  = sleep;
                  _data.stressLevel = stress;
                  _data.occupation  = occ;
                }); },
                onContinue: _next,
                onBack: _back,
              ),
              // 16 — Nutrition Goal
              _Step5Page(
                selected: _data.nutritionGoal,
                onSelect: (v) { setState(() => _data.nutritionGoal = v); },
                onContinue: _next,
                onBack: _back,
              ),
              // 17 — Dietary Restrictions & Allergies
              _DietaryRestrictionsPage(
                selected: _data.dietaryRestrictions,
                allergies: _data.foodAllergies,
                onChanged: (restr, allerg) { setState(() {
                  _data.dietaryRestrictions = restr;
                  _data.foodAllergies       = allerg;
                }); },
                onContinue: _next,
                onSkip: _next,
                onBack: _back,
              ),
              // 18 — Protein Confidence
              _Step6Page(
                selected: _data.proteinConfidence,
                onSelect: (v) { setState(() => _data.proteinConfidence = v); },
                onContinue: _next,
                onBack: _back,
              ),
              // 19 — Biggest Challenges
              _Step7Page(
                selected: _challenges,
                onToggle: (v) => setState(() {
                  _challenges.contains(v) ? _challenges.remove(v) : _challenges.add(v);
                }),
                onContinue: _next,
                onBack: _back,
              ),
              // 20 — Progress Photos
              _Step8Page(onContinue: _next, onSkip: _next, onBack: _back),
              // 21 — Coaching Mode
              _CoachingModePage(
                selected: _data.coachingMode,
                onSelect: (v) => setState(() => _data.coachingMode = v),
                onContinue: _next,
                onSkipCoach: () => _jumpToPage(24),
                onBack: _back,
              ),
              // 22 — Choose Coach
              _Step9Page(onContinue: _next, onBack: _back),
              // 23 — Generating Plan
              _Step10Page(onContinue: _next, onBack: _back),
              // 24 — Consent
              _ConsentPage(
                onContinue: () {
                  setState(() => _data.consentAgreed = true);
                  _next();
                },
                onBack: _back,
              ),
              // 25 — Final
              _Step11Page(data: _data, saving: _saving, onEnter: _finish),
            ],
          ),

          // EC-03 · the failed-save state, which this flow previously did not have.
          // It is a persistent banner rather than a SnackBar, because a transient
          // message for "none of your answers were saved" is a message that can be
          // missed — and the old behaviour's whole problem was that nobody was told.
          if (_saveError != null)
            Positioned(
              left: 16, right: 16, bottom: 24,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A1416),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE8556D)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_saveError!,
                          style: const TextStyle(
                              color: Color(0xFFF07A8C), fontSize: 13, height: 1.4)),
                      const SizedBox(height: 12),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        TextButton(
                          onPressed: _saving ? null : _finish,
                          child: Text(_saving ? 'Saving…' : 'Retry',
                              style: const TextStyle(
                                  color: Color(0xFFF07A8C),
                                  fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Shared components ─────────────────────────────────────────────────────────

class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, Colors.transparent]),
    ),
  );
}

class _AppBar extends StatelessWidget {
  final VoidCallback? onBack;
  const _AppBar({this.onBack});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (onBack != null)
              IntakeBackButton(
                onTap: onBack,
                size: 40,
                chip: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: const Icon(Icons.arrow_back, color: _primary, size: 20),
                ),
              )
            else
              const SizedBox(width: 44),
            const Expanded(
              child: Center(
                child: Text('12 Circle',
                  style: TextStyle(color: _primary, fontSize: 22,
                    fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}

class _LinearProgress extends StatelessWidget {
  final int step;
  final String? sectionLabel;
  const _LinearProgress({required this.step, this.sectionLabel});

  @override
  Widget build(BuildContext context) {
    final pct = (step / 11 * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('STEP ${step.toString().padLeft(2, '0')} OF 11',
                style: const TextStyle(color: _primary, fontSize: 11,
                  fontWeight: FontWeight.w600, letterSpacing: 1.5)),
              Text(sectionLabel ?? '$pct% Complete',
                style: TextStyle(color: sectionLabel != null
                    ? _onSurfV.withValues(alpha: 0.6)
                    : _primary,
                  fontSize: 11, fontWeight: FontWeight.w500,
                  fontStyle: sectionLabel != null ? FontStyle.italic : FontStyle.normal,
                  letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: step / 11,
              backgroundColor: _surfCH,
              valueColor: const AlwaysStoppedAnimation<Color>(_priCont),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final BorderRadius? radius;
  const _GlassCard({
    required this.child,
    this.selected = false,
    this.onTap,
    this.padding,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? _priCont.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.05),
          borderRadius: radius ?? BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _priCont.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.1),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected ? [
            BoxShadow(color: _priCont.withValues(alpha: 0.2), blurRadius: 20)
          ] : [],
        ),
        child: child,
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final IconData? icon;
  final double height;
  const _GradientButton({
    required this.label,
    this.onTap,
    this.enabled = true,
    this.icon,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    // The child `Text` supplies the name, so no label is set here — adding one
    // would double the announcement, which is a mistake this repository has
    // already made once (see `auth_design.dart`). What is added is the ROLE and
    // the ENABLED state: the button is disabled until the page's fields are
    // filled, and a screen reader had no way to know that.
    return Semantics(
      button: true,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      child: GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: height,
        decoration: BoxDecoration(
          color: enabled ? _btnPurple : _surfCH,
          borderRadius: BorderRadius.circular(999),
          boxShadow: enabled ? [
            BoxShadow(color: _btnPurple.withValues(alpha: 0.45), blurRadius: 20, offset: const Offset(0, 6))
          ] : [],
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
              style: TextStyle(
                color: enabled ? Colors.white : _onSurfV.withValues(alpha: 0.5),
                fontSize: 16, fontWeight: FontWeight.w700,
              )),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(icon, color: enabled ? Colors.white : _onSurfV.withValues(alpha: 0.5), size: 20),
            ],
          ],
        ),
      ),
    ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool selected;
  const _RadioDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 22, height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? _priCont : _outlineV,
          width: 2,
        ),
        color: selected ? _priCont.withValues(alpha: 0.1) : Colors.transparent,
      ),
      child: selected
          ? Center(child: Container(
              width: 10, height: 10,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: _priCont),
            ))
          : null,
    );
  }
}

// ── Step top bar (progress pills + step count) ───────────────────────────────
class _IntakeStepBar extends StatelessWidget {
  final int step;  // 1-indexed current step
  final int total;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;
  const _IntakeStepBar({
    required this.step, required this.total, this.onBack, this.onSkip});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, top + 12, 16, 16),
      child: Row(
        children: [
          IntakeBackButton(
            onTap: onBack,
            chip: Container(
              decoration: BoxDecoration(
                color: _surfCH,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.chevron_left, color: _onSurf, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: List.generate(total, (i) {
                final done = i < step;
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: done ? _priCont : _surfCHH,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 12),
          if (onSkip != null)
            GestureDetector(
              onTap: onSkip,
              child: const Text('Skip',
                style: TextStyle(
                  color: _onSurfV, fontSize: 13, fontWeight: FontWeight.w600)),
            )
          else
            Text(
              '${step.toString().padLeft(2, '0')} / ${total.toString().padLeft(2, '0')}',
              style: const TextStyle(
                color: _onSurfV, fontSize: 12, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

// ── Reusable selection card (icon square + title/subtitle + checkmark) ────────
class _SelectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _SelectionCard({
    required this.icon, required this.title, required this.subtitle,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? _priCont.withValues(alpha: 0.08) : _surfC,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _priCont : _outlineV,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: _priCont.withValues(alpha: 0.25), blurRadius: 14, spreadRadius: 0)]
              : null,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48, height: 48,
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(colors: [_priCont, _btnPurple],
                        begin: Alignment.topLeft, end: Alignment.bottomRight)
                    : null,
                color: selected ? null : _surfCHH,
                borderRadius: BorderRadius.circular(14),
                boxShadow: selected
                    ? [BoxShadow(color: _priCont.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4))]
                    : null,
              ),
              child: Icon(icon,
                color: selected ? Colors.white : _onSurfV, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                    style: TextStyle(
                      color: selected ? Colors.white : _onSurf,
                      fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                    style: const TextStyle(
                      color: _onSurfV, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 26, height: 26,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: selected ? _priCont : Colors.transparent,
                border: Border.all(
                  color: selected ? _priCont : _outlineV,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Welcome page ──────────────────────────────────────────────────────────────
class _WelcomePage extends StatelessWidget {
  final VoidCallback onStart;
  const _WelcomePage({required this.onStart});

  static const _grayscale = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, -20,
    0.2126, 0.7152, 0.0722, 0, -20,
    0.2126, 0.7152, 0.0722, 0, -20,
    0,      0,      0,      1,   0,
  ]);

  @override
  Widget build(BuildContext context) {
    final top    = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;
    final size   = MediaQuery.of(context).size;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Grayscale athlete background
        ColorFiltered(
          colorFilter: _grayscale,
          child: Image.asset('assets/images/workout-bg.jpg',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Image.asset(
              'assets/images/background.png', fit: BoxFit.cover)),
        ),

        // Top fade
        Positioned(
          top: 0, left: 0, right: 0,
          height: size.height * 0.45,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xCC0B1326), Colors.transparent],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),

        // Bottom fade
        Positioned(
          bottom: 0, left: 0, right: 0,
          height: size.height * 0.40,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Color(0xEE0B1326)],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),

        // Skewed headlines (top-left)
        Positioned(
          top: top + 48,
          left: 24, right: 24,
          child: const _WelcomeHeadlines(),
        ),

        // Get Started button
        Positioned(
          bottom: bottom + 40,
          left: 20, right: 20,
          // F-9: this page produced ONE merged accessibility node covering the
          // whole screen — headline and button together — so "Get Started" was
          // not separately focusable and a screen reader read the page as one
          // run-on string. There is no MergeSemantics here; it is Flutter's
          // default. With only one actionable node on the page, the
          // surrounding Text has no boundary and is absorbed into it, which
          // also expands its rect to the full screen. The next page produces 11
          // discrete nodes because its form fields create those boundaries.
          //
          // Declaring an explicit bounded button gives the control its own node
          // and stops it swallowing the headline. `excludeSemantics` keeps the
          // label from being announced twice.
          child: Semantics(
            button: true,
            label: 'Get Started',
            excludeSemantics: true,
            child: GestureDetector(
            onTap: onStart,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: _priCont,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: _priCont.withValues(alpha: 0.45),
                    blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              alignment: Alignment.center,
              child: const Text('Get Started',
                style: TextStyle(
                  color: Colors.white, fontSize: 18,
                  fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            ),
          ),
          ),
        ),
      ],
    );
  }
}

class _WelcomeHeadlines extends StatelessWidget {
  const _WelcomeHeadlines();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _WelcomeHeadlineLine(plain: 'MOVE',  highlight: 'BETTER',    color: _priCont),
      SizedBox(height: 8),
      _WelcomeHeadlineLine(plain: 'FEEL',  highlight: 'STRONGER',  color: Color(0xFF9CA3AF)),
      SizedBox(height: 8),
      _WelcomeHeadlineLine(plain: 'LIVE',  highlight: 'HEALTHIER', color: _priCont),
    ],
  );
}

class _WelcomeHeadlineLine extends StatelessWidget {
  final String plain, highlight;
  final Color color;
  const _WelcomeHeadlineLine({
    required this.plain, required this.highlight, required this.color});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Colors.white, fontSize: 52,
      fontWeight: FontWeight.w900, height: 1.05, letterSpacing: -1.5,
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      children: [
        Text(plain, style: style),
        Transform(
          transform: Matrix4.identity()..setEntry(0, 1, -0.09),
          child: Container(
            color: color,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Transform(
              transform: Matrix4.identity()..setEntry(0, 1, 0.09),
              child: Text(highlight, style: style),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Height Page ───────────────────────────────────────────────────────────────
class _HeightPage extends StatefulWidget {
  final int heightCm;
  final ValueChanged<int> onHeightChanged;
  final VoidCallback onContinue;
  final VoidCallback onSkip;
  final VoidCallback onBack;
  const _HeightPage({
    required this.heightCm, required this.onHeightChanged,
    required this.onContinue, required this.onSkip, required this.onBack,
  });

  @override
  State<_HeightPage> createState() => _HeightPageState();
}

class _HeightPageState extends State<_HeightPage> {
  static const int _minCm = 140;
  static const int _maxCm = 220;
  static const double _tickH = 12.0;

  late final ScrollController _sc;
  bool _useCm = true;
  late int _cm;
  double _rulerH = 260;

  @override
  void initState() {
    super.initState();
    _cm = widget.heightCm > 0 ? widget.heightCm : 174;
    _sc = ScrollController();
    _sc.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpTo(_cm);
      _nudge();
    });
  }

  void _jumpTo(int cm) {
    // Index 0 = MAX, so offset for value `cm` = (MAX - cm) * tickH
    final offset = (_maxCm - cm) * _tickH;
    if (_sc.hasClients) {
      final max = _sc.position.maxScrollExtent;
      _sc.jumpTo(offset.clamp(0.0, max));
    }
  }

  Future<void> _nudge() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted || !_sc.hasClients) return;
    final origin = _sc.offset;
    await _sc.animateTo(origin + 24,
        duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
    if (!mounted || !_sc.hasClients) return;
    await _sc.animateTo(origin,
        duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
  }

  void _onScroll() {
    final idx = (_sc.offset / _tickH).round();
    final v = (_maxCm - idx).clamp(_minCm, _maxCm);
    if (v != _cm) {
      setState(() => _cm = v);
      widget.onHeightChanged(v);
    }
  }

  @override
  void dispose() {
    _sc.removeListener(_onScroll);
    _sc.dispose();
    super.dispose();
  }

  String get _display {
    if (_useCm) return '$_cm';
    final totalIn = (_cm / 2.54).round();
    return "${totalIn ~/ 12}' ${totalIn % 12}\"";
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IntakeStepBar(
          step: 7, total: 24,
          onBack: widget.onBack, onSkip: widget.onSkip,
        ),

        // Headline + info card + unit toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("What's your Height?",
                style: TextStyle(
                  color: _onSurf, fontSize: 34,
                  fontWeight: FontWeight.w800, height: 1.1)),
              const SizedBox(height: 8),
              const Text('Helps improve accuracy of your fitness insights.',
                style: TextStyle(color: _onSurfV, fontSize: 15, height: 1.4)),
              const SizedBox(height: 22),
              // Unit toggle (cm / ft)
              Center(
                child: _HeightUnitToggle(
                  useCm: _useCm,
                  onChanged: (v) => setState(() => _useCm = v),
                ),
              ),
            ],
          ),
        ),

        // Ruler + large number display
        Expanded(
          child: LayoutBuilder(builder: (ctx, box) {
            _rulerH = box.maxHeight;
            return Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Large number (left 60%)
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: RichText(
                            text: TextSpan(children: [
                              TextSpan(text: _display,
                                style: const TextStyle(
                                  color: _priCont,
                                  fontSize: 88,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -3,
                                  height: 1,
                                )),
                              TextSpan(text: '  ${_useCm ? 'cm' : 'ft'}',
                                style: TextStyle(
                                  color: _priCont.withValues(alpha: 0.7),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                )),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    // Ruler (right 90px)
                    SizedBox(
                      width: 90,
                      child: ListView.builder(
                        controller: _sc,
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.symmetric(vertical: _rulerH / 2),
                        itemCount: _maxCm - _minCm + 1,
                        itemExtent: _tickH,
                        itemBuilder: (_, i) {
                          // i=0 → MAX_CM, i=80 → MIN_CM (inverted)
                          final v = _maxCm - i;
                          final isMajor = v % 10 == 0;
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (isMajor)
                                Text('$v',
                                  style: const TextStyle(
                                    color: Color(0x4DFFFFFF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  )),
                              const SizedBox(width: 4),
                              Container(
                                height: 1,
                                width: isMajor ? 28.0 : 16.0,
                                color: Color(
                                  isMajor ? 0x66FFFFFF : 0x26FFFFFF),
                              ),
                              const SizedBox(width: 6),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
                // Purple indicator line spanning full width
                Positioned.fill(
                  child: Center(
                    child: Container(height: 2, color: _priCont),
                  ),
                ),
              ],
            );
          }),
        ),

        // Next button
        Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 24),
          child: SizedBox(
            width: double.infinity,
            child: _GradientButton(
              label: 'Continue', onTap: widget.onContinue),
          ),
        ),
      ],
    );
  }
}

class _HeightUnitToggle extends StatelessWidget {
  final bool useCm;
  final ValueChanged<bool> onChanged;
  const _HeightUnitToggle({required this.useCm, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surfC,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _opt('cm', useCm, () => onChanged(true)),
          _opt('ft', !useCm, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _opt(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 56, height: 34,
        decoration: BoxDecoration(
          color: active ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: active
              ? [const BoxShadow(color: Colors.black26, blurRadius: 4)]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(label,
          style: TextStyle(
            color: active ? Colors.white : _onSurfV,
            fontSize: 14, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ── Step 1: Primary Goal ──────────────────────────────────────────────────────
class _Step1Page extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _Step1Page({
    required this.selected, required this.onSelect,
    required this.onContinue, required this.onBack,
  });

  static const _goals = [
    ('lose_fat',        Icons.local_fire_department_outlined, 'Lose Fat',             'Shed body fat while maintaining lean mass'),
    ('build_muscle',    Icons.fitness_center_outlined,        'Build Muscle',          'Hypertrophy training for size and strength'),
    ('body_recomp',     Icons.bar_chart_outlined,             'Body Recomposition',    'Simultaneously lose fat and gain muscle'),
    ('improve_health',  Icons.favorite_outline,               'Improve Health',        'Longevity, flexibility, and vital markers'),
    ('increase_energy', Icons.bolt_outlined,                  'Increase Energy',       'Boost metabolic rate and daily vitality'),
    ('performance',     Icons.sports_score_outlined,          'Athletic Performance',  'Speed, power, and sport-specific goals'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final hasSelection = selected.isNotEmpty;

    return Column(
      children: [
        _IntakeStepBar(step: 4, total: 24, onBack: onBack),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              const Text("What's your goal?",
                style: TextStyle(
                  color: _onSurf, fontSize: 34,
                  fontWeight: FontWeight.w800, height: 1.1)),
              const SizedBox(height: 8),
              const Text("We'll personalize your plan based on this.",
                style: TextStyle(color: _onSurfV, fontSize: 15, height: 1.4)),
              const SizedBox(height: 24),
              ..._goals.map((g) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SelectionCard(
                  icon: g.$2,
                  title: g.$3,
                  subtitle: g.$4,
                  selected: selected == g.$1,
                  onTap: () => onSelect(g.$1),
                ),
              )),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 24),
          child: SizedBox(
            width: double.infinity,
            child: _GradientButton(
              label: 'Continue',
              enabled: hasSelection,
              onTap: hasSelection ? onContinue : null,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Activities (multi-select) ─────────────────────────────────────────────────
class _ActivitiesPage extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _ActivitiesPage({
    required this.selected, required this.onToggle,
    required this.onContinue, required this.onBack,
  });

  static const _activities = [
    ('running',  Icons.directions_run,   'Running',  'Track pace, distance, calories'),
    ('cycling',  Icons.directions_bike,  'Cycling',  'Measure speed, endurance'),
    ('swimming', Icons.pool_outlined,    'Swimming', 'Laps, time, and calories'),
    ('yoga',     Icons.self_improvement, 'Yoga',     'Improve flexibility and focus'),
    ('hiking',   Icons.terrain_outlined, 'Hiking',   'Elevation, trails, distance'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final hasSelection = selected.isNotEmpty;

    return Column(
      children: [
        _IntakeStepBar(step: 5, total: 24, onBack: onBack),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              const Text('Pick your Activities',
                style: TextStyle(
                  color: _onSurf, fontSize: 34,
                  fontWeight: FontWeight.w800, height: 1.1)),
              const SizedBox(height: 8),
              const Text('Choose as many as you like.',
                style: TextStyle(color: _onSurfV, fontSize: 15, height: 1.4)),
              const SizedBox(height: 24),
              ..._activities.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SelectionCard(
                  icon: a.$2,
                  title: a.$3,
                  subtitle: a.$4,
                  selected: selected.contains(a.$1),
                  onTap: () => onToggle(a.$1),
                ),
              )),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 24),
          child: SizedBox(
            width: double.infinity,
            child: _GradientButton(
              label: 'Continue',
              enabled: hasSelection,
              onTap: hasSelection ? onContinue : null,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Step 3: Weight ────────────────────────────────────────────────────────────
class _WeightPage extends StatefulWidget {
  final double weightKg;
  final int heightCm;
  final ValueChanged<double> onWeightChanged;
  final VoidCallback onContinue;
  final VoidCallback onSkip;
  final VoidCallback onBack;
  const _WeightPage({
    required this.weightKg, required this.heightCm,
    required this.onWeightChanged, required this.onContinue,
    required this.onSkip, required this.onBack,
  });
  @override
  State<_WeightPage> createState() => _WeightPageState();
}

class _WeightPageState extends State<_WeightPage> {
  static const double _minKg = 40.0;
  static const double _maxKg = 150.0;
  static const double _tickW = 10.0;

  late final ScrollController _sc;
  bool _useKg = true;
  late double _weightKg;

  double get _bmi {
    if (widget.heightCm <= 0 || _weightKg <= 0) return 0;
    final hm = widget.heightCm / 100.0;
    return _weightKg / (hm * hm);
  }

  String get _bmiCategory {
    final b = _bmi;
    if (b <= 0) return '';
    if (b < 18.5) return 'Underweight';
    if (b < 25.0) return 'Healthy Weight';
    if (b < 30.0) return 'Overweight';
    return 'Obese';
  }

  String get _bmiMessage {
    final b = _bmi;
    if (b <= 0) return '';
    if (b < 18.5) return 'Great foundation to build on. Your plan will prioritise progressive overload and a strategic calorie surplus to stack lean muscle efficiently.';
    if (b < 25.0) return "You're already in the optimal zone. We'll dial in strength, performance, and body composition to take you to the next level.";
    if (b < 30.0) return 'This is where transformation begins. A smart blend of resistance training and cardio will accelerate fat loss while preserving your muscle.';
    return 'Every elite athlete started somewhere. We\'ll build your foundation with movement you can sustain, then progressively ramp intensity as your body adapts.';
  }

  @override
  void initState() {
    super.initState();
    _weightKg = widget.weightKg > 0 ? widget.weightKg : 68.5;
    _sc = ScrollController();
    _sc.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpTo(_weightKg);
      _nudge();
    });
  }

  Future<void> _nudge() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted || !_sc.hasClients) return;
    final origin = _sc.offset;
    await _sc.animateTo(origin + 28,
        duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
    if (!mounted || !_sc.hasClients) return;
    await _sc.animateTo(origin,
        duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
  }

  void _jumpTo(double kg) {
    final idx = ((kg - _minKg) / 0.1).round();
    final offset = idx * _tickW;
    if (_sc.hasClients) {
      _sc.jumpTo(offset.clamp(0.0, _sc.position.maxScrollExtent));
    }
  }

  void _onScroll() {
    final idx = (_sc.offset / _tickW).round();
    final raw = _minKg + idx * 0.1;
    final v = ((raw * 10).round() / 10.0).clamp(_minKg, _maxKg);
    if (v != _weightKg) {
      setState(() => _weightKg = v);
      widget.onWeightChanged(v);
    }
  }

  @override
  void dispose() {
    _sc.removeListener(_onScroll);
    _sc.dispose();
    super.dispose();
  }

  String get _displayValue => _useKg
      ? _weightKg.toStringAsFixed(1)
      : (_weightKg * 2.20462).toStringAsFixed(1);

  String get _unit => _useKg ? 'kg' : 'lb';

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final totalItems = ((_maxKg - _minKg) / 0.1).round() + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IntakeStepBar(step: 9, total: 24, onBack: widget.onBack, onSkip: widget.onSkip),

        // Headline + subtitle + unit toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("What's your Weight?",
                style: TextStyle(
                  color: _onSurf, fontSize: 34,
                  fontWeight: FontWeight.w800, height: 1.1)),
              const SizedBox(height: 8),
              const Text('Helps us tailor calories and your fitness insights.',
                style: TextStyle(color: _onSurfV, fontSize: 15, height: 1.4)),
              const SizedBox(height: 22),
              Center(
                child: _WeightUnitToggle(
                  useKg: _useKg,
                  onChanged: (v) { setState(() => _useKg = v); },
                ),
              ),
            ],
          ),
        ),

        // Big value + vertical ruler
        Expanded(
          child: LayoutBuilder(builder: (ctx, box) {
            final rulerH = box.maxHeight;
            return Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Large value (left)
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: RichText(
                            text: TextSpan(children: [
                              TextSpan(text: _displayValue,
                                style: const TextStyle(
                                  color: _priCont, fontSize: 80,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -3, height: 1)),
                              TextSpan(text: '  $_unit',
                                style: TextStyle(
                                  color: _priCont.withValues(alpha: 0.7),
                                  fontSize: 22, fontWeight: FontWeight.w800)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    // Vertical ruler (right 90px) — top = min, increasing downward
                    SizedBox(
                      width: 90,
                      child: ListView.builder(
                        controller: _sc,
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.symmetric(vertical: rulerH / 2),
                        itemCount: totalItems,
                        itemExtent: _tickW,
                        itemBuilder: (_, i) {
                          final kg = _minKg + i * 0.1;
                          final isMajor = i % 50 == 0;   // every 5 kg
                          final isMid   = i % 10 == 0 && !isMajor; // every 1 kg
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (isMajor)
                                Text(
                                  _useKg ? '${kg.round()}' : '${(kg * 2.20462).round()}',
                                  style: const TextStyle(
                                    color: Color(0x4DFFFFFF),
                                    fontSize: 11, fontWeight: FontWeight.w800)),
                              const SizedBox(width: 4),
                              Container(
                                height: 1,
                                width: isMajor ? 28.0 : isMid ? 18.0 : 12.0,
                                color: Color(isMajor ? 0x66FFFFFF : 0x26FFFFFF),
                              ),
                              const SizedBox(width: 6),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
                // Purple indicator line spanning full width
                Positioned.fill(
                  child: Center(
                    child: Container(height: 2, color: _priCont),
                  ),
                ),
              ],
            );
          }),
        ),

        // Next button
        Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 24),
          child: SizedBox(
            width: double.infinity,
            child: _GradientButton(label: 'Continue', onTap: widget.onContinue),
          ),
        ),
      ],
    );
  }
}

class _WeightUnitToggle extends StatelessWidget {
  final bool useKg;
  final ValueChanged<bool> onChanged;
  const _WeightUnitToggle({required this.useKg, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surfCH.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _outlineV.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _opt(context, 'kg', useKg, () => onChanged(true)),
          _opt(context, 'lb', !useKg, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _opt(BuildContext context, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 9),
        decoration: BoxDecoration(
          color: active ? _priCont : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
          style: TextStyle(
            color: active ? Colors.white : _onSurfV,
            fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _BmiCard extends StatelessWidget {
  final double bmi;
  final String category;
  final String message;
  const _BmiCard({required this.bmi, required this.category, required this.message});

  @override
  Widget build(BuildContext context) {
    final String suggested = bmi < 18.5
        ? 'Strength Training'
        : bmi < 25.0
            ? 'Strength + Cardio'
            : 'Cardio + Strength';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfC,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _outlineV.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _priCont.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.monitor_weight_outlined,
                  color: _priCont, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your BMI  ·  ${bmi.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: _onSurf, fontSize: 15,
                        fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(message,
                      style: const TextStyle(
                        color: _onSurfV, fontSize: 13, height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
          Divider(height: 28, color: _outlineV.withValues(alpha: 0.3)),
          _bmiRow('BMI Score', bmi.toStringAsFixed(1)),
          const SizedBox(height: 10),
          _bmiRow('Category', category),
          const SizedBox(height: 10),
          _bmiRow('Healthy Range', '18.5 – 24.9'),
          const SizedBox(height: 10),
          _bmiRow('Suggested Workouts', suggested),
        ],
      ),
    );
  }

  Widget _bmiRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: _onSurfV, fontSize: 13)),
        Text(value, style: const TextStyle(
          color: _onSurf, fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ── Step 4: Goal Weight ───────────────────────────────────────────────────────
class _TargetWeightPage extends StatefulWidget {
  final double currentWeightKg;
  final double goalWeightKg;
  final String primaryGoal;
  final ValueChanged<double> onGoalChanged;
  final VoidCallback onContinue;
  final VoidCallback onSkip;
  final VoidCallback onBack;

  const _TargetWeightPage({
    required this.currentWeightKg, required this.goalWeightKg,
    required this.primaryGoal, required this.onGoalChanged,
    required this.onContinue, required this.onSkip, required this.onBack,
  });

  @override
  State<_TargetWeightPage> createState() => _TargetWeightPageState();
}

class _TargetWeightPageState extends State<_TargetWeightPage> {
  static const double _tickW = 10.0;

  late final ScrollController _sc;
  bool _useKg = true;
  late double _goalKg;
  double _rulerW = 300;

  double get _cur => widget.currentWeightKg > 0 ? widget.currentWeightKg : 70.0;

  double get _minKg {
    switch (widget.primaryGoal) {
      case 'build_muscle': return _cur + 0.5;
      default: return math.max(30, _cur - 60);
    }
  }

  double get _maxKg {
    switch (widget.primaryGoal) {
      case 'lose_fat':    return _cur - 0.5;
      case 'body_recomp': return _cur - 0.5;
      default: return _cur + 60;
    }
  }

  double get _defaultGoal {
    switch (widget.primaryGoal) {
      case 'lose_fat':
        return (_cur - _cur * 0.12).clamp(_minKg, _maxKg).roundToDouble();
      case 'build_muscle':
        return (_cur + _cur * 0.10).clamp(_minKg, _maxKg).roundToDouble();
      case 'body_recomp':
        return (_cur - _cur * 0.04).clamp(_minKg, _maxKg).roundToDouble();
      default: return _cur;
    }
  }

  double get _diff => (_goalKg - _cur).abs();

  int get _estWeeks {
    if (_diff < 0.5) return 0;
    final rate = widget.primaryGoal == 'lose_fat' ? 0.5
        : widget.primaryGoal == 'build_muscle' ? 0.25 : 0.3;
    final minWeeks = widget.primaryGoal == 'build_muscle' ? 12 : 8;
    // Accurate timeframe: weight change ÷ safe weekly rate. Floored at a sane
    // minimum program length; NOT capped at a year (a large goal legitimately
    // takes longer than 52 weeks).
    return math.max(minWeeks, (_diff / rate).round());
  }

  int get _calAdjust {
    final rate = widget.primaryGoal == 'lose_fat' ? 0.5
        : widget.primaryGoal == 'build_muscle' ? 0.25 : 0.3;
    return (rate * 7700 / 7).round();
  }

  @override
  void initState() {
    super.initState();
    _goalKg = widget.goalWeightKg > 0
        ? widget.goalWeightKg.clamp(_minKg, _maxKg)
        : _defaultGoal;
    _sc = ScrollController();
    _sc.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpTo(_goalKg);
      _nudge();
    });
  }

  Future<void> _nudge() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted || !_sc.hasClients) return;
    final origin = _sc.offset;
    await _sc.animateTo(origin + 28,
        duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
    if (!mounted || !_sc.hasClients) return;
    await _sc.animateTo(origin,
        duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
  }

  void _jumpTo(double kg) {
    final clamped = kg.clamp(_minKg, _maxKg);
    final idx = ((clamped - _minKg) / 0.1).round();
    if (_sc.hasClients) {
      _sc.jumpTo((idx * _tickW).clamp(0.0, _sc.position.maxScrollExtent));
    }
  }

  void _onScroll() {
    final idx = (_sc.offset / _tickW).round();
    final v = ((_minKg + idx * 0.1) * 10).round() / 10.0;
    final clamped = v.clamp(_minKg, _maxKg);
    if (clamped != _goalKg) {
      setState(() => _goalKg = clamped);
      widget.onGoalChanged(clamped);
    }
  }

  @override
  void dispose() {
    _sc.removeListener(_onScroll);
    _sc.dispose();
    super.dispose();
  }

  String get _display => _useKg
      ? _goalKg.toStringAsFixed(1)
      : (_goalKg * 2.20462).toStringAsFixed(1);

  String get _unit => _useKg ? 'kg' : 'lb';

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final totalItems = ((_maxKg - _minKg) / 0.1).round() + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _IntakeStepBar(step: 9, total: 24,
          onBack: widget.onBack, onSkip: widget.onSkip),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 8, 20, bottom + 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text("What's your\ngoal weight?",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _onSurf, fontSize: 32,
                    fontWeight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 24),
                _WeightUnitToggle(
                  useKg: _useKg,
                  onChanged: (v) { setState(() => _useKg = v); }),
                const SizedBox(height: 20),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(children: [
                    TextSpan(text: _display,
                      style: const TextStyle(color: _priCont, fontSize: 76,
                        fontWeight: FontWeight.w900, height: 1, letterSpacing: -3)),
                    TextSpan(text: ' $_unit',
                      style: TextStyle(color: _priCont.withValues(alpha: 0.65),
                        fontSize: 28, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(height: 20),
                LayoutBuilder(builder: (ctx, box) {
                  _rulerW = box.maxWidth;
                  return ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Colors.transparent, Colors.white,
                        Colors.white, Colors.transparent],
                      stops: [0.0, 0.18, 0.82, 1.0],
                    ).createShader(bounds),
                    blendMode: BlendMode.dstIn,
                    child: SizedBox(
                      height: 74,
                      child: Stack(
                        children: [
                          ListView.builder(
                            controller: _sc,
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.symmetric(horizontal: _rulerW / 2),
                            itemCount: totalItems,
                            itemExtent: _tickW,
                            itemBuilder: (_, i) {
                              final isMajor = i % 10 == 0;
                              final isMid   = i % 5 == 0 && !isMajor;
                              final kg      = _minKg + i * 0.1;
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  SizedBox(
                                    height: 54,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Container(
                                          width: 1.5,
                                          height: isMajor ? 40.0 : isMid ? 24.0 : 14.0,
                                          decoration: BoxDecoration(
                                            color: isMajor
                                              ? Colors.white.withValues(alpha: 0.6)
                                              : isMid
                                                ? Colors.white.withValues(alpha: 0.4)
                                                : Colors.white.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(1)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    height: 20,
                                    child: isMajor
                                      ? Center(child: Text(
                                          _useKg ? '${kg.toInt()}'
                                            : '${(kg * 2.20462).round()}',
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.35),
                                            fontSize: 10, fontWeight: FontWeight.w700)))
                                      : const SizedBox.shrink(),
                                  ),
                                ],
                              );
                            },
                          ),
                          Positioned(
                            top: 0, height: 54, left: 0, right: 0,
                            child: Center(
                              child: Container(width: 2, height: 54, color: _priCont)),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 28),
                _GoalTransformCard(
                  isLosing: _goalKg < _cur,
                  isGaining: _goalKg > _cur,
                  diffKg: _diff,
                  estWeeks: _estWeeks,
                  calAdjust: _calAdjust,
                  primaryGoal: widget.primaryGoal,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, bottom + 24),
          child: _GradientButton(label: 'Continue', onTap: widget.onContinue),
        ),
      ],
    );
  }
}

// Friendly duration label: weeks for short spans, months up to a year, then
// years + months. Keeps the projection readable once it exceeds ~12 weeks.
String _formatTimeframe(int weeks) {
  if (weeks < 9) return '~$weeks weeks';
  if (weeks < 52) return '~${(weeks / 4.345).round()} months';
  final years = weeks ~/ 52;
  final months = ((weeks % 52) / 4.345).round();
  final y = '~$years year${years > 1 ? 's' : ''}';
  return months == 0 ? y : '$y ${months}mo';
}

class _GoalTransformCard extends StatelessWidget {
  final bool isLosing;
  final bool isGaining;
  final double diffKg;
  final int estWeeks;
  final int calAdjust;
  final String primaryGoal;

  const _GoalTransformCard({
    required this.isLosing, required this.isGaining,
    required this.diffKg, required this.estWeeks,
    required this.calAdjust, required this.primaryGoal,
  });

  @override
  Widget build(BuildContext context) {
    final icon = isLosing ? Icons.trending_down_rounded
        : isGaining ? Icons.trending_up_rounded
        : Icons.swap_horiz_rounded;

    final direction = isLosing
        ? 'Lose ${diffKg.toStringAsFixed(1)} kg'
        : isGaining
            ? 'Gain ${diffKg.toStringAsFixed(1)} kg'
            : 'Maintain current weight';

    final sub = estWeeks > 0
        ? 'Projected in ${_formatTimeframe(estWeeks)}'
        : 'Ongoing — stay at your best';

    final rate = primaryGoal == 'lose_fat' ? '0.5 kg/wk'
        : primaryGoal == 'build_muscle' ? '0.25 kg/wk'
        : primaryGoal == 'body_recomp' ? '0.3 kg/wk'
        : 'Stable';

    final cal = isLosing ? '−$calAdjust cal/day'
        : isGaining ? '+$calAdjust cal/day'
        : 'Maintenance';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfC,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _outlineV.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _priCont.withValues(alpha: 0.15)),
                child: Icon(icon, color: _priCont, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(direction, style: const TextStyle(color: _onSurf,
                    fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(sub, style: const TextStyle(
                    color: _onSurfV, fontSize: 13)),
                ],
              )),
            ],
          ),
          Divider(height: 28, color: _outlineV.withValues(alpha: 0.3)),
          Row(
            children: [
              Expanded(child: _sCol('Est. Time',
                estWeeks > 0 ? '~$estWeeks wks' : 'Ongoing')),
              Container(width: 1, height: 36,
                color: _outlineV.withValues(alpha: 0.3)),
              Expanded(child: _sCol('Weekly Rate', rate)),
              Container(width: 1, height: 36,
                color: _outlineV.withValues(alpha: 0.3)),
              Expanded(child: _sCol('Nutrition', cal)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sCol(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(children: [
      Text(label, textAlign: TextAlign.center,
        style: const TextStyle(color: _onSurfV, fontSize: 11,
          fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(value, textAlign: TextAlign.center,
        style: const TextStyle(color: _onSurf, fontSize: 12,
          fontWeight: FontWeight.w700)),
    ]),
  );
}

// ── Step 5: Weight Goal Summary (animated) ────────────────────────────────────
class _WeightGoalPage extends StatefulWidget {
  final double weightKg;
  final double weightGoalKg;
  final String primaryGoal;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  const _WeightGoalPage({
    required this.weightKg, required this.weightGoalKg,
    required this.primaryGoal,
    required this.onContinue, required this.onBack,
  });

  @override
  State<_WeightGoalPage> createState() => _WeightGoalPageState();
}

class _WeightGoalPageState extends State<_WeightGoalPage>
    with TickerProviderStateMixin {
  late final AnimationController _drawCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _drawAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _drawCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));
    _drawAnim = CurvedAnimation(parent: _drawCtrl, curve: Curves.easeInOut);
    _fadeAnim = CurvedAnimation(
      parent: _drawCtrl,
      curve: const Interval(0.75, 1.0, curve: Curves.easeOut));
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _drawCtrl.forward().then((_) {
      if (mounted) _pulseCtrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _drawCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  double get _target => widget.weightGoalKg > 0
      ? widget.weightGoalKg
      : _computed;

  double get _computed {
    final w = widget.weightKg > 0 ? widget.weightKg : 70.0;
    switch (widget.primaryGoal) {
      case 'lose_fat':    return (w - w * 0.12).clamp(w - 20, w - 4).roundToDouble();
      case 'build_muscle':return (w + w * 0.10).clamp(w + 3, w + 20).roundToDouble();
      case 'body_recomp': return (w - w * 0.04).clamp(w - 8, w - 1).roundToDouble();
      default: return w;
    }
  }

  DateTime get _targetDate {
    final diff = (widget.weightKg - _target).abs();
    if (diff < 0.5) return DateTime.now().add(const Duration(days: 84));
    final rate = widget.primaryGoal == 'lose_fat' ? 0.5
        : widget.primaryGoal == 'build_muscle' ? 0.25 : 0.3;
    final minWeeks = widget.primaryGoal == 'build_muscle' ? 12 : 8;
    // Accurate target date — no 52-week ceiling.
    final weeks = math.max(minWeeks, (diff / rate).round());
    return DateTime.now().add(Duration(days: weeks * 7));
  }

  String get _feedbackTitle {
    switch (widget.primaryGoal) {
      case 'lose_fat':     return 'Great Start!';
      case 'build_muscle': return "Let's Build!";
      case 'body_recomp':  return 'Smart Move!';
      default:             return "You're Ready!";
    }
  }

  String get _feedbackBody {
    switch (widget.primaryGoal) {
      case 'lose_fat':
        return "We'll adjust your plan weekly as you progress. Consistency is the only thing standing between you and that target.";
      case 'build_muscle':
        return "Progressive overload and smart nutrition will stack lean mass efficiently. Your plan is engineered for maximum growth.";
      case 'body_recomp':
        return "Simultaneous fat loss and muscle gain requires precision. Your program is calibrated to make it happen.";
      default:
        return "Maintaining peak performance takes the same discipline as building it. Your plan keeps you sharp and consistent.";
    }
  }

  String _fmtDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}';
  }

  String _fmtYear(DateTime d) => '${d.year}';

  String _fmtW(double w) {
    final r = (w * 2).round() / 2.0;
    return r % 1 == 0 ? '${r.toInt()}' : r.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_drawAnim, _pulseAnim]),
      builder: (ctx, _) => _body(ctx, _drawAnim.value, _fadeAnim.value, _pulseAnim.value),
    );
  }

  Widget _body(BuildContext context, double draw, double fade, double pulse) {
    final current    = widget.weightKg > 0 ? widget.weightKg : 70.0;
    final target     = _target;
    final targetDate = _targetDate;
    final dateStr    = _fmtDate(targetDate);
    final yearStr    = _fmtYear(targetDate);
    final bottom     = MediaQuery.of(context).padding.bottom;
    final wp1     = current - (current - target) * 0.33;
    final wp2     = current - (current - target) * 0.67;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _IntakeStepBar(step: 10, total: 24, onBack: widget.onBack),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 8, 24, bottom + 100),
            child: Column(
              children: [
                Text('WEIGHT GOAL SUMMARY',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _onSurfV.withValues(alpha: 0.6), fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 2.5)),
                const SizedBox(height: 14),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 40, fontWeight: FontWeight.w900, height: 1.15),
                    children: [
                      const TextSpan(
                        text: 'Reach ',
                        style: TextStyle(color: Colors.white)),
                      TextSpan(
                        text: '${target.toStringAsFixed(1)} kg',
                        style: const TextStyle(color: _priCont)),
                      const TextSpan(
                        text: '\nby ',
                        style: TextStyle(color: Colors.white)),
                      TextSpan(
                        text: '$dateStr, $yearStr!',
                        style: const TextStyle(color: _priCont)),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                // Chart with positioned labels
                LayoutBuilder(builder: (ctx, box) {
                  final w = box.maxWidth;
                  const h = 240.0;
                  const maxPad = 4.0;
                  final maxWt = math.max(current, target) + maxPad;
                  final minWt = math.min(current, target) - maxPad;
                  final range = maxWt - minWt;
                  const topPad = h * 0.12;
                  const botPad = h * 0.18;
                  const chartH = h - topPad - botPad;

                  double yFor(double wt) =>
                      topPad + (maxWt - wt) / range * chartH;

                  final p0  = Offset(0, yFor(current));
                  final p3  = Offset(w, yFor(target));
                  final cp1 = Offset(
                    p0.dx + (p3.dx - p0.dx) * 0.4,
                    p0.dy + (p3.dy - p0.dy) * 0.2);
                  final cp2 = Offset(
                    p0.dx + (p3.dx - p0.dx) * 0.6,
                    p0.dy + (p3.dy - p0.dy) * 0.8);

                  Offset bezierAt(double t) {
                    final mt = 1 - t;
                    return Offset(
                      mt*mt*mt*p0.dx + 3*mt*mt*t*cp1.dx + 3*mt*t*t*cp2.dx + t*t*t*p3.dx,
                      mt*mt*mt*p0.dy + 3*mt*mt*t*cp1.dy + 3*mt*t*t*cp2.dy + t*t*t*p3.dy,
                    );
                  }

                  final d1 = bezierAt(0.33);
                  final d2 = bezierAt(0.67);

                  return SizedBox(
                    height: h,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _WeightChartPainter(
                              startWeight: current, endWeight: target,
                              drawProgress: draw, pulseValue: pulse),
                          ),
                        ),
                        // Today label — always visible
                        Positioned(
                          top: (p0.dy - 44).clamp(0.0, h - 44), left: 0,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Today', style: TextStyle(
                                color: _onSurfV.withValues(alpha: 0.7), fontSize: 12)),
                              Text('${_fmtW(current)} kg',
                                style: const TextStyle(color: Colors.white,
                                  fontSize: 14, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                        // Waypoint 1 — fades in as line reaches it
                        if (draw >= 0.35)
                          Positioned(
                            top: (d1.dy - 24).clamp(0.0, h - 24),
                            left: (d1.dx - 30).clamp(0.0, w - 70),
                            child: Opacity(
                              opacity: ((draw - 0.35) / 0.2).clamp(0.0, 1.0),
                              child: Text('${_fmtW(wp1)} kg',
                                style: const TextStyle(color: Colors.white,
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        // Waypoint 2 — fades in as line reaches it
                        if (draw >= 0.68)
                          Positioned(
                            top: (d2.dy - 24).clamp(0.0, h - 24),
                            left: (d2.dx - 30).clamp(0.0, w - 70),
                            child: Opacity(
                              opacity: ((draw - 0.68) / 0.2).clamp(0.0, 1.0),
                              child: Text('${_fmtW(wp2)} kg',
                                style: const TextStyle(color: Colors.white,
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        // Target label — fades in at end
                        Positioned(
                          top: (p3.dy + 12).clamp(0.0, h - 56), right: 0,
                          child: Opacity(
                            opacity: fade,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(dateStr, style: TextStyle(
                                  color: _onSurfV.withValues(alpha: 0.7), fontSize: 12)),
                                Text(yearStr, style: TextStyle(
                                  color: _onSurfV.withValues(alpha: 0.55), fontSize: 11)),
                                Text('${target.toStringAsFixed(1)} kg',
                                  style: const TextStyle(color: Colors.white,
                                    fontSize: 14, fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                // Feedback fades in with the chart end
                Opacity(
                  opacity: fade,
                  child: Column(children: [
                    const SizedBox(height: 36),
                    Text(_feedbackTitle, textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white,
                        fontSize: 30, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),
                    Text(_feedbackBody, textAlign: TextAlign.center,
                      style: const TextStyle(color: _onSurfV,
                        fontSize: 16, height: 1.65)),
                  ]),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, bottom + 24),
          child: _GradientButton(label: 'Continue', onTap: widget.onContinue),
        ),
      ],
    );
  }
}

class _WeightChartPainter extends CustomPainter {
  final double startWeight;
  final double endWeight;
  final double drawProgress;
  final double pulseValue;

  const _WeightChartPainter({
    required this.startWeight, required this.endWeight,
    this.drawProgress = 1.0, this.pulseValue = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double maxWt  = math.max(startWeight, endWeight) + 4;
    final double minWt  = math.min(startWeight, endWeight) - 4;
    final double range  = maxWt - minWt;
    final double topPad = size.height * 0.12;
    final double botPad = size.height * 0.18;
    final double chartH = size.height - topPad - botPad;

    double yFor(double w) => topPad + (maxWt - w) / range * chartH;

    final p0  = Offset(0, yFor(startWeight));
    final p3  = Offset(size.width, yFor(endWeight));
    final cp1 = Offset(
      p0.dx + (p3.dx - p0.dx) * 0.4, p0.dy + (p3.dy - p0.dy) * 0.2);
    final cp2 = Offset(
      p0.dx + (p3.dx - p0.dx) * 0.6, p0.dy + (p3.dy - p0.dy) * 0.8);

    Offset bezierAt(double t) {
      final mt = 1 - t;
      return Offset(
        mt*mt*mt*p0.dx + 3*mt*mt*t*cp1.dx + 3*mt*t*t*cp2.dx + t*t*t*p3.dx,
        mt*mt*mt*p0.dy + 3*mt*mt*t*cp1.dy + 3*mt*t*t*cp2.dy + t*t*t*p3.dy,
      );
    }

    // Gradient fill — fades in with drawProgress
    final fullCurve = Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p3.dx, p3.dy);

    final fillPath = Path()
      ..addPath(fullCurve, Offset.zero)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fillPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _priCont.withValues(alpha: 0.45 * drawProgress),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    // Animated curve line via PathMetrics
    final curvePaint = Paint()
      ..color = _priCont
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final metric in fullCurve.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * drawProgress), curvePaint);
    }

    // Start dot
    if (drawProgress > 0) {
      canvas.drawCircle(p0, 5.5, Paint()..color = _priCont);
    }
    // Intermediate dots appear as line passes them
    if (drawProgress >= 0.36) {
      canvas.drawCircle(bezierAt(0.33), 4.5,
        Paint()..color = _priCont.withValues(alpha: 0.85));
    }
    if (drawProgress >= 0.70) {
      canvas.drawCircle(bezierAt(0.67), 4.5,
        Paint()..color = _priCont.withValues(alpha: 0.85));
    }

    // End dot — appears at completion with pulsing glow
    if (drawProgress >= 0.99) {
      final glowR = 12.0 + pulseValue * 9.0;
      canvas.drawCircle(p3, glowR,
        Paint()
          ..color = _priCont.withValues(alpha: (0.30 - pulseValue * 0.12).clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(
              BlurStyle.normal, 6 + pulseValue * 5));
      canvas.drawCircle(p3, 7, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_WeightChartPainter old) =>
      old.startWeight != startWeight || old.endWeight != endWeight ||
      old.drawProgress != drawProgress || old.pulseValue != pulseValue;
}

// ── Step 2: Activity Level ────────────────────────────────────────────────────
class _Step2Page extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _Step2Page({required this.selected, required this.onSelect,
    required this.onContinue, required this.onBack});

  static const _levels = [
    ('beginner',       Icons.sentiment_satisfied_alt_outlined, 'Beginner',        'New to working out or coming back after a long break.'),
    ('some_experience',Icons.directions_walk_outlined,         'Some Experience',  'Comfortable with basic exercises and active 1–2 days/week.'),
    ('intermediate',   Icons.fitness_center_outlined,          'Intermediate',     'Consistent training routine (3–4 days/week) for 6+ months.'),
    ('advanced',       Icons.bolt_outlined,                    'Advanced',         'Competitive athlete or consistent high-intensity trainer.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _IntakeStepBar(step: 11, total: 24, onBack: onBack),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            children: [
              const Text("What's your current activity level?",
                style: TextStyle(color: _onSurf, fontSize: 26,
                  fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 6),
              const Text('Choose the profile that best describes your fitness experience.',
                style: TextStyle(color: _onSurfV, fontSize: 15, height: 1.5)),
              const SizedBox(height: 20),
              ..._levels.map((l) {
                final isSelected = selected == l.$1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _GlassCard(
                    selected: isSelected,
                    onTap: () => onSelect(l.$1),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _surfCHH,
                          ),
                          child: Icon(l.$2, color: _primary, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.$3, style: const TextStyle(
                                color: _onSurf, fontSize: 18, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text(l.$4, style: const TextStyle(
                                color: _onSurfV, fontSize: 13, height: 1.4)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _RadioDot(selected: isSelected),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        _BottomBar(
          child: SizedBox(
            width: double.infinity,
            child: _GradientButton(
              label: 'Continue',
              enabled: selected.isNotEmpty,
              onTap: onContinue,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Step 3: Training Frequency ────────────────────────────────────────────────
class _Step3Page extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _Step3Page({required this.selected, required this.onSelect,
    required this.onContinue, required this.onBack});

  static const _days = [2, 3, 4, 5, 6];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _IntakeStepBar(step: 12, total: 24, onBack: onBack),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            child: Column(
              children: [
                const Text('How many days per week can you train?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _onSurf, fontSize: 26,
                    fontWeight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 8),
                const Text('This directly influences program assignment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _onSurfV, fontSize: 15)),
                const SizedBox(height: 28),
                // 5-column number picker
                Row(
                  children: _days.map((d) {
                    final isSelected = selected == d;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => onSelect(d),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 90,
                          decoration: BoxDecoration(
                            gradient: isSelected ? const LinearGradient(
                              colors: [_priCont, _terCont],
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                            ) : null,
                            color: isSelected ? null : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                            boxShadow: isSelected ? [
                              BoxShadow(color: _priCont.withValues(alpha: 0.4), blurRadius: 16)
                            ] : [],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(d == 6 ? '6+' : '$d',
                                style: TextStyle(
                                  color: isSelected ? Colors.white : _onSurf,
                                  fontSize: 28, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text('DAYS',
                                style: TextStyle(
                                  color: isSelected ? Colors.white.withValues(alpha: 0.8) : _onSurfV,
                                  fontSize: 9, fontWeight: FontWeight.w600,
                                  letterSpacing: 1)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                // Info card
                _GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _priCont.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.analytics_outlined, color: _primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Intensity Optimization',
                              style: TextStyle(color: _onSurf, fontSize: 16,
                                fontWeight: FontWeight.w700)),
                            SizedBox(height: 4),
                            Text(
                              'Higher frequency allows for more targeted muscle isolation, '
                              'while 2–3 days focuses on high-impact compound movements.',
                              style: TextStyle(color: _onSurfV, fontSize: 13, height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _BottomBar(
          child: SizedBox(
            width: double.infinity,
            child: _GradientButton(
              label: 'Continue',
              enabled: selected > 0,
              onTap: onContinue,
            ),
          ),
        ),
      ],
    );
  }
}

class _ConicProgress extends StatelessWidget {
  final int step;
  final String label;
  const _ConicProgress({required this.step, required this.label});

  @override
  Widget build(BuildContext context) {
    final pct = step / 11;
    return Column(
      children: [
        SizedBox(
          width: 64, height: 64,
          child: CustomPaint(
            painter: _ConicPainter(progress: pct),
            child: Center(
              child: Text('$step/11',
                style: const TextStyle(color: _primary, fontSize: 13,
                  fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(
          color: _onSurfV, fontSize: 11, letterSpacing: 2,
          fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ConicPainter extends CustomPainter {
  final double progress;
  const _ConicPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final strokeW = 4.0;

    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW;
    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..shader = const LinearGradient(colors: [_priCont, _terCont])
          .createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_ConicPainter old) => old.progress != progress;
}

// ── Step 4: Training Location ─────────────────────────────────────────────────
class _Step4Page extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _Step4Page({required this.selected, required this.onSelect,
    required this.onContinue, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _IntakeStepBar(step: 13, total: 24, onBack: onBack),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Where do you train?',
                  style: TextStyle(color: _onSurf, fontSize: 26,
                    fontWeight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 8),
                const Text("We'll tailor your workout plans and equipment lists based on your preferred environment.",
                  style: TextStyle(color: _onSurfV, fontSize: 15, height: 1.5)),
                const SizedBox(height: 20),
                _LocationCard(
                  value: 'home',
                  label: 'Home',
                  subtitle: 'No commute, just focus. Bodyweight and minimalist gear.',
                  icon: Icons.home_outlined,
                  gradientColors: [const Color(0xFF1A1035), const Color(0xFF0D0820)],
                  accentColor: const Color(0xFF7C3AED),
                  selected: selected == 'home',
                  onTap: () => onSelect('home'),
                ),
                const SizedBox(height: 12),
                _LocationCard(
                  value: 'gym',
                  label: 'Gym',
                  subtitle: 'Full access to racks, machines, and heavy iron.',
                  icon: Icons.fitness_center_outlined,
                  gradientColors: [const Color(0xFF0F1A2E), const Color(0xFF060E1E)],
                  accentColor: const Color(0xFFB76DFF),
                  selected: selected == 'gym',
                  onTap: () => onSelect('gym'),
                ),
                const SizedBox(height: 12),
                _LocationCard(
                  value: 'both',
                  label: 'Both',
                  subtitle: 'The ultimate hybrid. Plans for home and commercial setups.',
                  icon: Icons.swap_horiz_outlined,
                  gradientColors: [const Color(0xFF1A0D2E), const Color(0xFF0A0A0B)],
                  accentColor: const Color(0xFFD164E2),
                  selected: selected == 'both',
                  onTap: () => onSelect('both'),
                ),
              ],
            ),
          ),
        ),
        _BottomBar(
          child: SizedBox(
            width: double.infinity,
            child: _GradientButton(
              label: 'Continue',
              enabled: selected.isNotEmpty,
              onTap: onContinue,
            ),
          ),
        ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  final String value;
  final String label;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final Color accentColor;
  final bool selected;
  final VoidCallback onTap;
  const _LocationCard({
    required this.value, required this.label, required this.subtitle,
    required this.icon, required this.gradientColors, required this.accentColor,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: selected ? accentColor.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.08),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected ? [
            BoxShadow(color: accentColor.withValues(alpha: 0.3), blurRadius: 20)
          ] : [],
        ),
        child: Stack(
          children: [
            // Background icon watermark
            Positioned(
              right: -10, top: -10,
              child: Icon(icon, size: 120,
                color: accentColor.withValues(alpha: 0.08)),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor.withValues(alpha: 0.15),
                      border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                    ),
                    child: Icon(icon, color: accentColor, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Text(label, style: const TextStyle(
                              color: _onSurf, fontSize: 20, fontWeight: FontWeight.w700)),
                            const Spacer(),
                            if (selected)
                              const Icon(Icons.check_circle_rounded,
                                color: _primary, size: 20),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(subtitle, style: TextStyle(
                          color: _onSurfV.withValues(alpha: 0.7), fontSize: 13, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 5: Nutrition Goal ────────────────────────────────────────────────────
class _Step5Page extends StatefulWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _Step5Page({required this.selected, required this.onSelect,
    required this.onContinue, required this.onBack});

  @override
  State<_Step5Page> createState() => _Step5PageState();
}

class _Step5PageState extends State<_Step5Page> {
  static const _options = [
    ('fat_loss',     Icons.local_fire_department_outlined, 'Fat Loss',    'Prioritize calorie deficit and metabolic efficiency.'),
    ('muscle_gain',  Icons.fitness_center_outlined,        'Muscle Gain', 'Focus on protein synthesis and surplus fueling.'),
    ('maintenance',  Icons.balance_outlined,               'Maintenance', 'Balance energy intake for long-term body composition.'),
    ('not_sure',     Icons.help_outline_rounded,           'Not Sure',    "I'm looking for professional guidance."),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _IntakeStepBar(step: 15, total: 24, onBack: widget.onBack),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            children: [
              const Text('Nutrition Goal',
                style: TextStyle(color: _onSurf, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Select the primary focus for your nutrition plan to help us calibrate your macro-targets.',
                style: TextStyle(color: _onSurfV, fontSize: 15, height: 1.5)),
              const SizedBox(height: 20),
              ..._options.map((o) {
                final isSelected = widget.selected == o.$1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _GlassCard(
                    selected: isSelected,
                    onTap: () => widget.onSelect(o.$1),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _priCont.withValues(alpha: 0.1),
                            border: Border.all(color: _priCont.withValues(alpha: 0.2)),
                          ),
                          child: Icon(o.$2, color: _primary, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(o.$3, style: const TextStyle(
                                color: _onSurf, fontSize: 17, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text(o.$4, style: const TextStyle(
                                color: _onSurfV, fontSize: 13, height: 1.4)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _RadioDot(selected: isSelected),
                      ],
                    ),
                  ),
                );
              }),
              // Coach hint for "not sure"
              if (widget.selected == 'not_sure') ...[
                const SizedBox(height: 4),
                _GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _priCont.withValues(alpha: 0.2),
                          border: Border.all(color: _priCont.withValues(alpha: 0.4)),
                        ),
                        child: const Icon(Icons.person_outline, color: _primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("COACH SARAH'S NOTE",
                              style: TextStyle(color: _primary, fontSize: 10,
                                fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                            SizedBox(height: 4),
                            Text(
                              '"Don\'t worry! We\'ll analyze your current activity and body metrics to determine the optimal approach for your body type."',
                              style: TextStyle(color: _onSurf, fontSize: 13,
                                fontStyle: FontStyle.italic, height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        _BottomBar(
          child: SizedBox(
            width: double.infinity,
            child: _GradientButton(
              label: 'Continue',
              icon: Icons.arrow_forward,
              enabled: widget.selected.isNotEmpty,
              onTap: widget.onContinue,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Step 6: Protein Confidence ────────────────────────────────────────────────
class _Step6Page extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _Step6Page({required this.selected, required this.onSelect,
    required this.onContinue, required this.onBack});

  static const _levels = [
    ('beginner',       'Beginner',       "I'm new to tracking macros and need guidance on high-protein sources."),
    ('some_knowledge', 'Some Knowledge', 'I know the basics but struggle with consistency and variety in my diet.'),
    ('advanced',       'Advanced',       'I track accurately and understand how to adjust intake based on my training load.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _IntakeStepBar(step: 17, total: 24, onBack: onBack),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            children: [
              const Text('Protein Confidence',
                style: TextStyle(color: _onSurf, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('How confident are you with nutrition?',
                style: TextStyle(color: _onSurfV, fontSize: 15, height: 1.5)),
              const SizedBox(height: 16),
              // Always-visible coach card
              _GlassCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _priCont.withValues(alpha: 0.2),
                        border: Border.all(color: _priCont.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.person_outline, color: _primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '"This helps Coach Sarah know how much education to provide."',
                        style: TextStyle(color: _onSurfV, fontSize: 13,
                          fontStyle: FontStyle.italic, height: 1.5)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ..._levels.map((l) {
                final isSelected = selected == l.$1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _GlassCard(
                    selected: isSelected,
                    onTap: () => onSelect(l.$1),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    radius: BorderRadius.circular(20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.$2, style: const TextStyle(
                                color: _onSurf, fontSize: 18, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              Text(l.$3, style: const TextStyle(
                                color: _onSurfV, fontSize: 14, height: 1.5)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _RadioDot(selected: isSelected),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        _BottomBar(
          child: SizedBox(
            width: double.infinity,
            child: _GradientButton(
              label: 'Continue',
              icon: Icons.arrow_forward,
              enabled: selected.isNotEmpty,
              onTap: onContinue,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Step 7: Biggest Challenge ─────────────────────────────────────────────────
class _Step7Page extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _Step7Page({required this.selected, required this.onToggle,
    required this.onContinue, required this.onBack});

  static const _items = [
    ('consistency',    Icons.sync_outlined,           'Consistency'),
    ('motivation',     Icons.bolt_outlined,            'Motivation'),
    ('nutrition',      Icons.restaurant_outlined,      'Nutrition'),
    ('time',           Icons.schedule_outlined,        'Time'),
    ('accountability', Icons.groups_outlined,          'Accountability'),
    ('stress',         Icons.psychology_alt_outlined,  'Stress'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _IntakeStepBar(step: 18, total: 24, onBack: onBack),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Biggest Challenge',
                  style: TextStyle(color: _onSurf, fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text(
                  "This is gold for coaching. Understanding your friction points helps us build a plan you'll actually stick to.",
                  style: TextStyle(color: _onSurfV, fontSize: 15, height: 1.5)),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.1,
                  children: _items.map((item) {
                    final isSelected = selected.contains(item.$1);
                    return GestureDetector(
                      onTap: () => onToggle(item.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _priCont.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? _priCont.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1),
                            width: isSelected ? 1.5 : 1,
                          ),
                          boxShadow: isSelected ? [
                            BoxShadow(color: _priCont.withValues(alpha: 0.2), blurRadius: 16)
                          ] : [],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 48, height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? _priCont.withValues(alpha: 0.25)
                                    : _surfC,
                              ),
                              child: Icon(item.$2,
                                color: _primary,
                                size: 24),
                            ),
                            const SizedBox(height: 10),
                            Text(item.$3,
                              style: const TextStyle(color: _onSurf, fontSize: 14,
                                fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        _BottomBar(
          child: SizedBox(
            width: double.infinity,
            child: _GradientButton(
              label: 'Continue',
              enabled: selected.isNotEmpty,
              onTap: onContinue,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Step 8: Progress Photo (Optional) ─────────────────────────────────────────
class _Step8Page extends StatefulWidget {
  final VoidCallback onContinue;
  final VoidCallback onSkip;
  final VoidCallback onBack;
  const _Step8Page({required this.onContinue, required this.onSkip, required this.onBack});

  @override
  State<_Step8Page> createState() => _Step8PageState();
}

class _Step8PageState extends State<_Step8Page> {
  // Newly picked local files (this session)
  XFile? _front, _side, _back;
  // Signed URLs for photos already uploaded in a previous session
  String? _frontUrl, _sideUrl, _backUrl;
  bool _uploading = false;
  bool _loadingExisting = true;

  @override
  void initState() {
    super.initState();
    _loadExistingPhotos();
  }

  // Counts slots with a NEW local file selected this session
  int get _newPickCount =>
      [_front, _side, _back].where((f) => f != null).length;

  // Counts all slots that have either an existing upload OR a new pick
  int get _totalPhotoCount {
    int n = 0;
    if (_front != null || _frontUrl != null) n++;
    if (_side  != null || _sideUrl  != null) n++;
    if (_back  != null || _backUrl  != null) n++;
    return n;
  }

  Future<void> _loadExistingPhotos() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loadingExisting = false);
      return;
    }
    // Do NOT use storage.list() — it requires a SELECT bucket policy that
    // many setups don't grant. Instead probe each side directly with
    // createSignedUrl; it throws when the file doesn't exist, so the first
    // successful call tells us exactly which extension was uploaded.
    const sides = ['front', 'side', 'back'];
    const exts  = ['jpg', 'jpeg', 'png', 'heic', 'webp'];
    for (final side in sides) {
      for (final ext in exts) {
        try {
          final url = await Supabase.instance.client.storage
              .from('progress-photos')
              .createSignedUrl('$uid/$side.$ext', 3600);
          if (mounted) {
            setState(() {
              if (side == 'front') _frontUrl = url;
              else if (side == 'side') _sideUrl  = url;
              else                    _backUrl   = url;
            });
          }
          break; // found this side — stop trying extensions
        } catch (_) {
          // file doesn't exist at this extension, try next
        }
      }
    }
    if (mounted) setState(() => _loadingExisting = false);
  }

  // Picks a normalized extension from the file name or mime type. Falls back to
  // jpg so the stored path always matches one the reload probes.
  String _photoExt(XFile f) {
    const known = ['jpg', 'jpeg', 'png', 'heic', 'webp'];
    final name = f.name.toLowerCase();
    if (name.contains('.')) {
      final e = name.split('.').last;
      if (known.contains(e)) return e;
    }
    final m = (f.mimeType ?? '').toLowerCase();
    if (m.contains('png')) return 'png';
    if (m.contains('webp')) return 'webp';
    if (m.contains('heic')) return 'heic';
    return 'jpg';
  }

  Future<void> _uploadAndContinue() async {
    // Nothing new to upload — just proceed
    if (_newPickCount == 0) { widget.onContinue(); return; }
    setState(() => _uploading = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        final entries = <String, XFile?>{
          'front': _front, 'side': _side, 'back': _back,
        };
        for (final e in entries.entries) {
          final file = e.value;
          if (file == null) continue; // skip slots with no new pick
          final bytes = await file.readAsBytes();
          // On web file.path is a blob: URL with no extension — derive from the
          // file name / mime instead so the stored path matches the reload probe.
          final ext = _photoExt(file);
          final mime = ext == 'heic' ? 'image/heic'
              : ext == 'png' ? 'image/png'
              : ext == 'webp' ? 'image/webp'
              : 'image/jpeg';
          await Supabase.instance.client.storage
              .from('progress-photos')
              .uploadBinary(
                '$uid/${e.key}.$ext',
                bytes,
                fileOptions: FileOptions(contentType: mime, upsert: true),
              );
        }
      }
    } catch (_) {
      // Upload errors don't block onboarding — photos can be added later
    }
    if (mounted) {
      setState(() => _uploading = false);
      widget.onContinue();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _IntakeStepBar(step: 19, total: 24, onBack: widget.onBack, onSkip: widget.onSkip),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 130),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _onSurf),
                    children: [
                      TextSpan(text: 'Progress Photos '),
                      TextSpan(text: '(Optional)',
                        style: TextStyle(color: _onSurfV, fontWeight: FontWeight.w400, fontSize: 22)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Visual data helps our AI and your coach refine your plan. Photos are kept in your secure, private vault.',
                  style: TextStyle(color: _onSurfV, fontSize: 15, height: 1.5)),
                const SizedBox(height: 20),
                _PhotoUploadCard(
                  icon: Icons.photo_camera_outlined,
                  label: 'Front Photo',
                  hint: 'Face forward, arms at sides',
                  image: _front,
                  existingUrl: _frontUrl,
                  onPicked: (f) => setState(() => _front = f),
                ),
                const SizedBox(height: 12),
                _PhotoUploadCard(
                  icon: Icons.accessibility_new_outlined,
                  label: 'Side Photo',
                  hint: 'Profile view, 90° turn',
                  image: _side,
                  existingUrl: _sideUrl,
                  onPicked: (f) => setState(() => _side = f),
                ),
                const SizedBox(height: 12),
                _PhotoUploadCard(
                  icon: Icons.person_outlined,
                  label: 'Back Photo',
                  hint: 'Straight posture, rear view',
                  image: _back,
                  existingUrl: _backUrl,
                  onPicked: (f) => setState(() => _back = f),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _tertiary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _tertiary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline, color: _tertiary, size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Pro Tip', style: TextStyle(
                              color: _tertiary, fontSize: 15, fontWeight: FontWeight.w700)),
                            SizedBox(height: 4),
                            Text(
                              'Use consistent lighting and a plain background. Wear the same clothing each time for accurate visual comparisons.',
                              style: TextStyle(color: _onSurfV, fontSize: 13, height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          color: _bg,
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: _GradientButton(
                  label: _uploading
                      ? 'Uploading...'
                      : _loadingExisting
                          ? 'Loading...'
                          : _totalPhotoCount > 0
                              ? 'Continue ($_totalPhotoCount/3)'
                              : 'Continue',
                  enabled: !_uploading && !_loadingExisting,
                  onTap: _uploadAndContinue,
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: widget.onSkip,
                child: const Text('Skip for now',
                  style: TextStyle(color: _onSurfV, fontSize: 14)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Photo upload card ─────────────────────────────────────────────────────────
class _PhotoUploadCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String hint;
  final XFile? image;
  final String? existingUrl;
  final ValueChanged<XFile?> onPicked;
  const _PhotoUploadCard({
    required this.icon, required this.label,
    required this.hint, required this.image,
    this.existingUrl,
    required this.onPicked,
  });

  @override
  State<_PhotoUploadCard> createState() => _PhotoUploadCardState();
}

class _PhotoUploadCardState extends State<_PhotoUploadCard> {
  Uint8List? _previewBytes;

  @override
  void didUpdateWidget(_PhotoUploadCard old) {
    super.didUpdateWidget(old);
    if (widget.image != old.image && widget.image != null) {
      widget.image!.readAsBytes().then((b) {
        if (mounted) setState(() => _previewBytes = b);
      });
    }
    if (widget.image == null) _previewBytes = null;
  }

  Future<void> _applyPicked(XFile? file) async {
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() => _previewBytes = bytes);
    widget.onPicked(file);
  }

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final picker = ImagePicker();
    try {
      final file = await picker.pickImage(
          source: source, imageQuality: 85, maxWidth: 1920);
      // Desktop web can't open a camera — fall back to the file picker so the
      // user can still add a photo instead of the button doing nothing.
      if (file == null && kIsWeb && source == ImageSource.camera) {
        await _applyPicked(await picker.pickImage(
            source: ImageSource.gallery, imageQuality: 85, maxWidth: 1920));
        return;
      }
      await _applyPicked(file);
    } catch (_) {
      if (kIsWeb && source == ImageSource.camera) {
        try {
          await _applyPicked(await picker.pickImage(
              source: ImageSource.gallery, imageQuality: 85, maxWidth: 1920));
        } catch (_) {}
      }
    }
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surfC,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: _outlineV, borderRadius: BorderRadius.circular(2))),
              Text('Add ${widget.label}',
                style: const TextStyle(color: _onSurf, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              _PickerRow(
                icon: Icons.camera_alt_outlined,
                label: 'Take Photo',
                onTap: () { Navigator.pop(ctx); _pick(context, ImageSource.camera); },
              ),
              const SizedBox(height: 10),
              _PickerRow(
                icon: Icons.photo_library_outlined,
                label: 'Choose from Library',
                onTap: () { Navigator.pop(ctx); _pick(context, ImageSource.gallery); },
              ),
              if (widget.image != null) ...[
                const SizedBox(height: 10),
                _PickerRow(
                  icon: Icons.delete_outline,
                  label: 'Remove Photo',
                  color: const Color(0xFFCF6679),
                  onTap: () { Navigator.pop(ctx); widget.onPicked(null); },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLocalPreview = widget.image != null && _previewBytes != null;
    final hasNetworkPhoto = !hasLocalPreview && widget.existingUrl != null;
    final hasAnyPhoto     = hasLocalPreview || hasNetworkPhoto;

    Widget photoWidget;
    if (hasLocalPreview) {
      photoWidget = Image.memory(_previewBytes!, fit: BoxFit.cover);
    } else if (hasNetworkPhoto) {
      photoWidget = Image.network(
        widget.existingUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: _surfCH),
      );
    } else {
      photoWidget = const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () => _showOptions(context),
      child: Container(
        height: 140,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: hasAnyPhoto ? Colors.transparent : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasAnyPhoto ? _priCont.withValues(alpha: 0.7) : _priCont.withValues(alpha: 0.3),
            width: 1.5),
        ),
        child: hasAnyPhoto
          ? Stack(fit: StackFit.expand, children: [
              photoWidget,
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                      begin: Alignment.bottomCenter, end: Alignment.topCenter),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        hasNetworkPhoto
                          ? Icons.cloud_done_outlined
                          : Icons.check_circle,
                        color: _tertiary, size: 16),
                      const SizedBox(width: 6),
                      Text(widget.label, style: const TextStyle(
                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Text(
                        hasNetworkPhoto ? 'Saved · tap to replace' : 'Tap to change',
                        style: const TextStyle(color: Colors.white60, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ])
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _priCont.withValues(alpha: 0.1)),
                  child: Icon(widget.icon, color: _primary, size: 24),
                ),
                const SizedBox(height: 10),
                Text(widget.label, style: const TextStyle(
                  color: _onSurf, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(widget.hint, style: const TextStyle(color: _onSurfV, fontSize: 12)),
                const SizedBox(height: 6),
                const Text('Tap to add',
                  style: TextStyle(color: _priCont, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _PickerRow({required this.icon, required this.label, required this.onTap,
    this.color = _onSurf});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _surfCH, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 14),
        Text(label, style: TextStyle(
          color: color, fontSize: 16, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

// ── Coaching Mode Selection ───────────────────────────────────────────────────
class _CoachingModePage extends StatefulWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onContinue;   // coach_guided → proceed to coach marketplace
  final VoidCallback onSkipCoach;  // self/ai guided → skip to building plan
  final VoidCallback onBack;
  const _CoachingModePage({
    required this.selected,
    required this.onSelect,
    required this.onContinue,
    required this.onSkipCoach,
    required this.onBack,
  });
  @override
  State<_CoachingModePage> createState() => _CoachingModePageState();
}

class _CoachingModePageState extends State<_CoachingModePage> {
  late String _selected;

  static const _modes = [
    (
      value: 'self_guided',
      label: 'Self Guided',
      icon: Icons.self_improvement_outlined,
      tagline: 'I want structure without a coach',
      description:
          'Get workout programs, nutrition targets, habit tracking, challenges, '
          'and progress tools — all driven by your goals.',
    ),
    (
      value: 'ai_guided',
      label: 'AI Guided',
      icon: Icons.auto_awesome_outlined,
      tagline: 'I want smart guidance without a human coach',
      description:
          'AI generates your plan, reviews progress, provides accountability '
          'reminders, and delivers personalised coaching insights.',
    ),
    (
      value: 'coach_guided',
      label: 'Coach Guided',
      icon: Icons.emoji_people_outlined,
      tagline: 'I want a real coach in my corner',
      description:
          'Choose a coach who manages your programming, nutrition, messaging, '
          'check-in reviews, and ongoing accountability.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.selected.isEmpty ? '' : widget.selected;
  }

  void _handleContinue() {
    if (_selected.isEmpty) return;
    widget.onSelect(_selected);
    if (_selected == 'coach_guided') {
      widget.onContinue();
    } else {
      widget.onSkipCoach();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _selected.isNotEmpty;
    return SafeArea(
      child: Column(children: [
        _IntakeStepBar(step: 20, total: 24, onBack: widget.onBack),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('How would you like\nto reach your goals?',
                  style: TextStyle(
                    color: _onSurf, fontSize: 28,
                    fontWeight: FontWeight.w800, height: 1.15)),
                const SizedBox(height: 8),
                const Text('Choose your coaching experience.',
                  style: TextStyle(color: _outline, fontSize: 14, height: 1.5)),
                const SizedBox(height: 28),
                ..._modes.map((m) {
                  final active = _selected == m.value;
                  return GestureDetector(
                    onTap: () => setState(() => _selected = m.value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: active
                            ? _priCont.withValues(alpha: 0.12)
                            : _surfCH,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active ? _priCont : _outlineV,
                          width: active ? 1.5 : 1,
                        ),
                        boxShadow: active ? [
                          BoxShadow(
                            color: _priCont.withValues(alpha: 0.18),
                            blurRadius: 20, offset: const Offset(0, 6)),
                        ] : null,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: active
                                  ? _priCont.withValues(alpha: 0.2)
                                  : _surfCHH,
                            ),
                            child: Icon(m.icon,
                              color: active ? _primary : _outline, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text(m.label,
                                  style: TextStyle(
                                    color: active ? _primary : _onSurf,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700)),
                                const Spacer(),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 22, height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: active ? _priCont : Colors.transparent,
                                    border: Border.all(
                                      color: active ? _priCont : _outlineV,
                                      width: 1.5),
                                  ),
                                  child: active
                                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                                    : null,
                                ),
                              ]),
                              const SizedBox(height: 4),
                              Text(m.tagline,
                                style: const TextStyle(
                                  color: _outline, fontSize: 12,
                                  fontStyle: FontStyle.italic)),
                              const SizedBox(height: 8),
                              Text(m.description,
                                style: const TextStyle(
                                  color: _onSurfV, fontSize: 13, height: 1.5)),
                            ],
                          )),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _priCont.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _priCont.withValues(alpha: 0.18)),
                  ),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded, color: _priCont, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'You can change your coaching mode anytime — go to Profile → Settings → Coaching Mode.',
                        style: TextStyle(color: _onSurfV, fontSize: 12, height: 1.5),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: GestureDetector(
            onTap: canContinue ? _handleContinue : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: canContinue
                  ? const LinearGradient(
                      colors: [Color(0xFFB76DFF), Color(0xFF7C3AED)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight)
                  : null,
                color: canContinue ? null : _surfCH,
              ),
              alignment: Alignment.center,
              child: Text(
                _selected == 'coach_guided'
                  ? 'Choose My Coach'
                  : 'Build My Plan',
                style: TextStyle(
                  color: canContinue ? Colors.white : _outline,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Step 9: Choose & Meet Your Coach ─────────────────────────────────────────
class _Step9Page extends ConsumerStatefulWidget {
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _Step9Page({required this.onContinue, required this.onBack});

  @override
  ConsumerState<_Step9Page> createState() => _Step9PageState();
}

class _Step9PageState extends ConsumerState<_Step9Page> {
  Map<String, dynamic>? _selectedCoach;
  bool _selecting = false;

  Future<void> _selectCoach(Map<String, dynamic> coach) async {
    setState(() => _selecting = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        await Supabase.instance.client
            .from('coach_client_relationships')
            .upsert({
              'coach_id':      coach['id'],
              'client_id':     uid,
              'status':        'active',
              'initiated_by':  'client',
              'activated_at':  DateTime.now().toIso8601String(),
            }, onConflict: 'coach_id,client_id');
        // Intake yields a single coach: cancel any other active relationship
        // (e.g. a coach picked earlier then changed) so re-selecting replaces
        // rather than accumulates. Multi-coach is added later via marketplace.
        await Supabase.instance.client
            .from('coach_client_relationships')
            .update({
              'status':       'cancelled',
              'cancelled_by': 'client',
              'cancel_reason': 'switched_during_intake',
              'cancelled_at': DateTime.now().toIso8601String(),
            })
            .eq('client_id', uid)
            .eq('status', 'active')
            .neq('coach_id', coach['id'] as String);
        // Notify coach
        await Supabase.instance.client.from('notifications').insert({
          'recipient_id': coach['id'],
          'type': 'new_client',
          'title': 'New Client Added',
          'body': 'A new client has selected you as their coach.',
          'data': {'client_id': uid},
          'read': false,
        });
        ref.invalidate(assignedCoachProvider);
      }
    } catch (_) {}
    if (mounted) setState(() { _selectedCoach = coach; _selecting = false; });
  }

  Widget _avatar(String? url, {double size = 160}) {
    final placeholder = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2D1B4E), Color(0xFF1A0D2E)],
          begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: Center(child: Icon(Icons.person_rounded,
        size: size * 0.5, color: const Color(0xFFB76DFF))));
    if (url == null) return placeholder;
    return Image.network(url, fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder);
  }

  @override
  Widget build(BuildContext context) {
    final coachesAsync = ref.watch(availableCoachesProvider);

    return Column(children: [
      _IntakeStepBar(step: 21, total: 24, onBack: _selectedCoach != null
          ? () => setState(() => _selectedCoach = null)
          : widget.onBack),

      Expanded(child: _selectedCoach == null
        // ── Phase 1: Choose a coach ──────────────────────────────────────────
        ? SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Choose Your Coach',
                style: TextStyle(color: _onSurf, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Your coach will guide your journey and review your progress.',
                style: TextStyle(color: _onSurfV, fontSize: 14, height: 1.5)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _priCont.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _priCont.withValues(alpha: 0.2))),
                child: const Row(children: [
                  Icon(Icons.info_outline_rounded, color: _primary, size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    "This isn't final — you can switch coaches or browse others in the "
                    "marketplace anytime. Pick whoever feels right to start.",
                    style: TextStyle(color: _onSurfV, fontSize: 12.5, height: 1.4))),
                ])),
              const SizedBox(height: 20),
              coachesAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: _primary)),
                error: (_, __) => const Center(
                  child: Text('Could not load coaches. Please try again.',
                    style: TextStyle(color: _onSurfV))),
                data: (coaches) => coaches.isEmpty
                  ? const Center(child: Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Text('No coaches available right now.\nCheck back soon.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _onSurfV, fontSize: 15, height: 1.6))))
                  : Column(
                      children: List.generate(coaches.length, (idx) {
                        final coach = coaches[idx];
                        final fn    = coach['first_name'] as String? ?? '';
                        final ln    = coach['last_name']  as String? ?? '';
                        final name  = 'Coach ${('$fn $ln').trim()}';
                        final title = coach['coach_title'] as String? ?? 'Personal Health Coach';
                        final bio   = coach['coach_bio']   as String? ?? '';
                        final isFull  = coach['is_full'] as bool? ?? false;
                        final count   = coach['active_clients'] as int? ?? 0;
                        final rating  = (coach['rating_avg'] as num?)?.toDouble() ?? 0.0;
                        final reviews = coach['review_count'] as int? ?? 0;
                        final pricing = (coach['pricing_monthly'] as num?)?.toDouble() ?? 0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: _surfC,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _priCont.withValues(alpha: 0.2))),
                          child: Column(children: [
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Container(
                                  width: 72, height: 72,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [_priCont, _tertiary],
                                      begin: Alignment.topLeft, end: Alignment.bottomRight)),
                                  padding: const EdgeInsets.all(2),
                                  child: ClipOval(child: _avatar(
                                    coach['avatar_url'] as String?, size: 72))),
                                const SizedBox(width: 14),
                                Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(color: _onSurf,
                                      fontSize: 17, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 2),
                                    Text(title, style: const TextStyle(color: _primary,
                                      fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                                    const SizedBox(height: 6),
                                    Row(children: [
                                      Icon(Icons.people_outline, color: _onSurfV, size: 14),
                                      const SizedBox(width: 4),
                                      Text('$count active clients',
                                        style: const TextStyle(color: _onSurfV, fontSize: 12)),
                                      if (isFull) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFB4AB).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4)),
                                          child: const Text('FULL', style: TextStyle(
                                            color: Color(0xFFFFB4AB), fontSize: 9,
                                            fontWeight: FontWeight.w700))),
                                      ],
                                    ]),
                                    const SizedBox(height: 5),
                                    Row(children: [
                                      ...List.generate(5, (i) {
                                        final filled = rating >= i + 1;
                                        final half = !filled && rating >= i + 0.5;
                                        return Icon(
                                          half
                                            ? Icons.star_half_rounded
                                            : filled
                                              ? Icons.star_rounded
                                              : Icons.star_outline_rounded,
                                          color: _primary, size: 14);
                                      }),
                                      const SizedBox(width: 5),
                                      Text(
                                        rating > 0
                                          ? '${rating.toStringAsFixed(1)} ($reviews ${reviews == 1 ? 'review' : 'reviews'})'
                                          : 'No reviews yet',
                                        style: const TextStyle(color: _onSurfV, fontSize: 12)),
                                    ]),
                                    const SizedBox(height: 5),
                                    Row(children: [
                                      Icon(Icons.payments_outlined, color: _tertiary, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        pricing > 0
                                          ? 'From \$${pricing.toStringAsFixed(0)}/mo'
                                          : 'Flexible pricing',
                                        style: const TextStyle(color: _tertiary,
                                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                                      if (pricing > 0) ...[
                                        const SizedBox(width: 5),
                                        const Text('· cancel anytime',
                                          style: TextStyle(color: _onSurfV, fontSize: 11)),
                                      ],
                                    ]),
                                  ])),
                              ])),
                            if (bio.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                                child: Text('"$bio"',
                                  style: const TextStyle(color: _onSurfV, fontSize: 13,
                                    height: 1.5, fontStyle: FontStyle.italic))),
                            GestureDetector(
                              onTap: isFull || _selecting ? null : () => _selectCoach(coach),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(20)),
                                  gradient: isFull ? null : const LinearGradient(
                                    colors: [_priCont, Color(0xFF6FFBBE)]),
                                  color: isFull ? _surfCHH : null),
                                alignment: Alignment.center,
                                child: _selecting
                                  ? const SizedBox(width: 20, height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                  : Text(isFull ? 'Coach Full' : 'Select Coach',
                                      style: TextStyle(
                                        color: isFull ? _onSurfV : Colors.white,
                                        fontSize: 15, fontWeight: FontWeight.w700)))),
                          ]));
                      })),
              ),
            ]))

        // ── Phase 2: Meet your selected coach ────────────────────────────────
        : SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [_priCont, _tertiary],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  boxShadow: [BoxShadow(color: _priCont.withValues(alpha: 0.5), blurRadius: 24)]),
                child: Container(
                  width: 160, height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: _surfCHH,
                    border: Border.all(color: _bg, width: 3)),
                  child: ClipOval(child: _avatar(
                    _selectedCoach!['avatar_url'] as String?)))),
              Transform.translate(
                offset: const Offset(56, -24),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: _surfC,
                    border: Border.all(color: _priCont.withValues(alpha: 0.5)),
                    boxShadow: [BoxShadow(color: _priCont.withValues(alpha: 0.3), blurRadius: 10)]),
                  child: const Icon(Icons.verified_rounded, color: _primary, size: 20))),
              const SizedBox(height: 4),
              Text('Meet Coach ${(('${_selectedCoach!['first_name'] ?? ''} ${_selectedCoach!['last_name'] ?? ''}').trim())}',
                style: const TextStyle(color: _onSurf, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text((_selectedCoach!['coach_title'] as String? ?? 'Personal Health Coach').toUpperCase(),
                style: const TextStyle(color: _primary, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 2)),
              const SizedBox(height: 20),
              _GlassCard(
                padding: const EdgeInsets.all(20),
                radius: BorderRadius.circular(20),
                child: Text(
                  '"${_selectedCoach!['coach_bio'] ?? 'I\'ll be guiding your journey, reviewing your check-ins, and keeping you accountable every step of the way.'}"',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _onSurf, fontSize: 16,
                    height: 1.6, fontStyle: FontStyle.italic))),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: _GlassCard(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  child: const Column(children: [
                    Icon(Icons.rate_review_outlined, color: _primary, size: 22),
                    SizedBox(height: 8),
                    Text('Daily Feedback', textAlign: TextAlign.center,
                      style: TextStyle(color: _onSurfV, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]))),
                const SizedBox(width: 12),
                Expanded(child: _GlassCard(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  child: const Column(children: [
                    Icon(Icons.event_available_outlined, color: _primary, size: 22),
                    SizedBox(height: 8),
                    Text('Weekly Sync', textAlign: TextAlign.center,
                      style: TextStyle(color: _onSurfV, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]))),
              ]),
            ]))),

      _BottomBar(child: SizedBox(
        width: double.infinity,
        child: _GradientButton(
          label: _selectedCoach == null
            ? 'Skip for now'
            : "Let's Go, ${_selectedCoach!['first_name'] ?? 'Coach'}!",
          onTap: widget.onContinue))),
    ]);
  }
}

// ── Step 10: Generating Plan (loading interstitial) ───────────────────────────
class _Step10Page extends StatefulWidget {
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _Step10Page({required this.onContinue, required this.onBack});

  @override
  State<_Step10Page> createState() => _Step10PageState();
}

class _Step10PageState extends State<_Step10Page> {
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _runProgress();
  }

  Future<void> _runProgress() async {
    final steps = [20, 45, 70, 90, 100];
    for (final s in steps) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      setState(() => _progress = s);
    }
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) widget.onContinue();
  }

  static const _phases = [
    (Icons.analytics_outlined,  'Analyzing your goals'),
    (Icons.restaurant_outlined, 'Calibrating nutrition targets'),
    (Icons.fitness_center_outlined, 'Building workout protocol'),
    (Icons.person_pin_outlined, 'Assigning your coach'),
  ];

  @override
  Widget build(BuildContext context) {
    final doneCount = (_progress / 25).floor().clamp(0, 4);
    return Column(
      children: [
        _IntakeStepBar(step: 22, total: 24, onBack: null),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated ring (building plan)
                SizedBox(
                  width: 120, height: 120,
                  child: CustomPaint(
                    painter: _ConicPainter(progress: _progress / 100),
                    child: Center(
                      child: Text('$_progress%',
                        style: const TextStyle(color: _primary, fontSize: 22,
                          fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text('Building Your Plan',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _onSurf, fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Our AI is crafting a protocol tailored to your physiology.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _onSurfV, fontSize: 15, height: 1.5)),
                const SizedBox(height: 40),
                ..._phases.asMap().entries.map((entry) {
                  final i = entry.key;
                  final phase = entry.value;
                  final done = i < doneCount;
                  final active = i == doneCount;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done ? _priCont.withValues(alpha: 0.9)
                                : active ? _priCont.withValues(alpha: 0.15)
                                : _surfCH,
                          ),
                          child: Icon(
                            done ? Icons.check_rounded : phase.$1,
                            color: done ? Colors.white
                                : active ? _primary
                                : _onSurfV.withValues(alpha: 0.4),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(phase.$2,
                          style: TextStyle(
                            color: done ? _onSurf : active ? _primary : _onSurfV.withValues(alpha: 0.4),
                            fontSize: 15,
                            fontWeight: active || done ? FontWeight.w600 : FontWeight.w400,
                          )),
                        if (active) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(
                              color: _primary, strokeWidth: 1.5),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Step 11: Your Plan Is Ready ───────────────────────────────────────────────
class _Step11Page extends StatelessWidget {
  final IntakeData data;
  final bool saving;
  final VoidCallback onEnter;
  const _Step11Page({required this.data, required this.saving, required this.onEnter});

  String get _goalLabel {
    const map = {
      'lose_fat': 'Lose Fat', 'build_muscle': 'Build Muscle',
      'body_recomp': 'Body Recomp', 'improve_health': 'Improve Health',
      'increase_energy': 'Increase Energy', 'performance': 'Athletic Perf.',
    };
    return map[data.primaryGoal] ?? 'Your Goal';
  }

  String get _nutritionLabel {
    const map = {
      'fat_loss': 'Fat Loss', 'muscle_gain': 'High Protein',
      'maintenance': 'Balanced', 'not_sure': 'AI Guided',
    };
    return map[data.nutritionGoal] ?? 'Optimized';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _IntakeStepBar(step: 24, total: 24, onBack: null),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            child: Column(
              children: [
                // Floating check circle
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [_priCont, _terCont],
                    ),
                    boxShadow: [
                      BoxShadow(color: _priCont.withValues(alpha: 0.4), blurRadius: 30)
                    ],
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 20),
                const Text('Your Plan Is Ready',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _onSurf, fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text("We've architected a protocol tailored to your physiology and goals.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _onSurfV, fontSize: 15, height: 1.5)),
                const SizedBox(height: 28),
                // Bento grid
                Row(
                  children: [
                    Expanded(
                      child: _BentoCard(
                        icon: Icons.fitness_center_outlined,
                        label: 'GOAL',
                        value: _goalLabel,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _BentoCard(
                        icon: Icons.calendar_today_outlined,
                        label: 'TRAINING',
                        value: data.trainingDays > 0 ? '${data.trainingDays} Days/Wk' : '4 Days/Wk',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Nutrition wide card
                _GlassCard(
                  selected: true,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56, height: 56,
                        child: CustomPaint(
                          painter: _ConicPainter(progress: 0.75),
                          child: const Center(
                            child: Icon(Icons.restaurant_outlined, color: _primary, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('NUTRITION', style: TextStyle(
                            color: _onSurfV, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                          Text(_nutritionLabel, style: const TextStyle(
                            color: _onSurf, fontSize: 18, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const Spacer(),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('2,450', style: TextStyle(
                            color: _primary, fontSize: 22, fontWeight: FontWeight.w800)),
                          Text('KCAL/DAY', style: TextStyle(
                            color: _onSurfV, fontSize: 10, letterSpacing: 1)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Starting score
                _GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('STARTING SCORE', style: TextStyle(
                            color: _onSurfV, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('0', style: TextStyle(
                            color: _onSurf, fontSize: 48, fontWeight: FontWeight.w800,
                            shadows: [Shadow(color: _primary.withValues(alpha: 0.4), blurRadius: 16)])),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _priCont.withValues(alpha: 0.2), width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Text('READY',
                          style: TextStyle(color: _primary, fontSize: 11,
                            fontWeight: FontWeight.w700, letterSpacing: 1)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _BottomBar(
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: _GradientButton(
                  label: saving ? 'Loading...' : 'Enter 12 Circle',
                  icon: saving ? null : Icons.arrow_forward,
                  onTap: saving ? null : onEnter,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Membership activation sequence complete.',
                style: TextStyle(color: _onSurfV, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

class _BentoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _BentoCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      selected: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _priCont.withValues(alpha: 0.15),
              border: Border.all(color: _priCont.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, color: _primary, size: 22),
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(
            color: _onSurfV, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, textAlign: TextAlign.center,
            style: const TextStyle(
              color: _onSurf, fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ── Shared bottom bar ─────────────────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  final Widget child;
  const _BottomBar({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: _bg.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: child,
    );
  }
}

// ── Profile Info Page ─────────────────────────────────────────────────────────
/// Public so F-9's whole-screen-node finding can be re-measured on the device.
/// It takes plain values and callbacks — no Supabase — so it mounts standalone.
class ProfileInfoPage extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String gender;
  final DateTime? dateOfBirth;
  final void Function(String, String, String, DateTime?) onChanged;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const ProfileInfoPage({
    super.key,
    required this.firstName, required this.lastName,
    required this.gender, required this.dateOfBirth,
    required this.onChanged, required this.onContinue, required this.onBack,
  });
  @override
  State<ProfileInfoPage> createState() => _ProfileInfoPageState();
}

class _ProfileInfoPageState extends State<ProfileInfoPage> {
  late final TextEditingController _fnCtrl;
  late final TextEditingController _lnCtrl;
  late String _gender;
  late DateTime? _dob;

  @override
  void initState() {
    super.initState();
    _fnCtrl  = TextEditingController(text: widget.firstName);
    _lnCtrl  = TextEditingController(text: widget.lastName);
    _gender  = widget.gender;
    _dob     = widget.dateOfBirth;
  }

  @override
  void dispose() {
    _fnCtrl.dispose();
    _lnCtrl.dispose();
    super.dispose();
  }

  void _notify() => widget.onChanged(_fnCtrl.text.trim(), _lnCtrl.text.trim(), _gender, _dob);

  bool get _canContinue =>
      _fnCtrl.text.trim().isNotEmpty &&
      _lnCtrl.text.trim().isNotEmpty &&
      _gender.isNotEmpty &&
      _dob != null;

  String _formatDob() {
    if (_dob == null) return 'Select date';
    return '${_dob!.day.toString().padLeft(2,'0')} / '
        '${_dob!.month.toString().padLeft(2,'0')} / '
        '${_dob!.year}';
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1995, 1, 1),
      firstDate: DateTime(1920),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 13)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: _primary, onPrimary: Colors.black,
            surface: _surfC, onSurface: _onSurf),
          dialogTheme: const DialogThemeData(backgroundColor: _surfC)),
        child: child!),
    );
    if (picked != null && mounted) {
      setState(() => _dob = picked);
      _notify();
    }
  }

  @override
  Widget build(BuildContext context) {
    final top    = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Column(children: [
      // Header
      Padding(
        padding: EdgeInsets.only(top: top + 16, left: 20, right: 20, bottom: 24),
        child: Column(children: [
          Row(children: [
            IntakeBackButton(
              onTap: widget.onBack,
              chip: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back_ios_new, color: _onSurf, size: 16))),
            const SizedBox(width: 12),
            // F-9: these two lines had no semantics boundary and were absorbed
            // into the only actionable node on the page — the back button —
            // whose rect then covered the whole screen. `header`/`container`
            // give each its own node, which is also what a screen reader needs
            // in order to offer the title as a heading.
            Expanded(child: Semantics(
              header: true,
              container: true,
              child: const Text('Your Profile',
                style: TextStyle(color: _onSurf, fontSize: 20, fontWeight: FontWeight.w800)))),
          ]),
          const SizedBox(height: 8),
          Semantics(
            container: true,
            child: const Text('Tell us a little about yourself.',
              style: TextStyle(color: _onSurfV, fontSize: 14))),
        ])),

      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // First Name
          _label('First Name'),
          _textField(
            controller: _fnCtrl,
            hint: 'John',
            onChanged: (_) => setState(_notify),
          ),
          const SizedBox(height: 20),

          // Last Name
          _label('Last Name'),
          _textField(
            controller: _lnCtrl,
            hint: 'Smith',
            onChanged: (_) => setState(_notify),
          ),
          const SizedBox(height: 20),

          // Gender
          _label('Gender'),
          const SizedBox(height: 8),
          Row(children: [
            _genderChip('Male',   Icons.male),
            const SizedBox(width: 12),
            _genderChip('Female', Icons.female),
          ]),
          const SizedBox(height: 20),

          // Date of Birth
          _label('Date of Birth'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickDob,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: _surfCH,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _dob != null
                      ? _primary.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.08))),
              child: Row(children: [
                Icon(Icons.cake_outlined,
                  color: _dob != null ? _primary : _outline, size: 20),
                const SizedBox(width: 12),
                Text(_formatDob(),
                  style: TextStyle(
                    color: _dob != null ? _onSurf : _outline,
                    fontSize: 15)),
              ]))),
          const SizedBox(height: 40),
        ])),
      ),

      // Bottom CTA
      _BottomBar(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _canContinue ? () { _notify(); widget.onContinue(); } : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _btnPurple,
              disabledBackgroundColor: _btnPurple.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Text('Continue',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)))),
        SizedBox(height: bottom > 0 ? 0 : 8),
      ])),
    ]);
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(
      color: _onSurfV, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5)));

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required void Function(String) onChanged,
  }) => TextField(
    controller: controller,
    onChanged: onChanged,
    style: const TextStyle(color: _onSurf, fontSize: 15),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _outline.withValues(alpha: 0.6)),
      filled: true,
      fillColor: _surfCH,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _primary.withValues(alpha: 0.5), width: 1.5))),
  );

  Widget _genderChip(String label, IconData icon) {
    final selected = _gender == label;
    return Expanded(
      child: GestureDetector(
        onTap: () { setState(() => _gender = label); _notify(); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? _primary.withValues(alpha: 0.15) : _surfCH,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _primary : Colors.white.withValues(alpha: 0.08),
              width: selected ? 1.5 : 1)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: selected ? _primary : _outline, size: 20),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(
              color: selected ? _primary : _onSurfV,
              fontSize: 15, fontWeight: FontWeight.w600)),
          ]))));
  }
}

// ── PAR-Q Health Screening ────────────────────────────────────────────────────
class _PARQPage extends StatefulWidget {
  final Map<int, bool> answers;
  final void Function(Map<int, bool>) onChanged;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _PARQPage({required this.answers, required this.onChanged,
    required this.onContinue, required this.onBack});
  @override
  State<_PARQPage> createState() => _PARQPageState();
}

class _PARQPageState extends State<_PARQPage> {
  late Map<int, bool> _ans;

  static const _qs = [
    'Has a doctor ever told you that you have a heart condition and should only perform physical activity recommended by a doctor?',
    'Do you experience chest pain during physical activity?',
    'Have you experienced chest pain while not exercising within the past month?',
    'Do you lose balance due to dizziness or have you lost consciousness in the past year?',
    'Do you have a bone, joint, or orthopedic condition that could be worsened by exercise?',
    'Are you currently taking medication for blood pressure or a heart condition?',
    'Has a doctor ever advised you against exercising without medical supervision?',
    'Do you know of any other reason why you should not participate in physical activity?',
  ];

  @override
  void initState() {
    super.initState();
    _ans = Map<int, bool>.from(widget.answers);
    for (int i = 1; i <= 8; i++) { _ans.putIfAbsent(i, () => false); }
  }

  void _toggle(int q, bool v) {
    setState(() => _ans[q] = v);
    widget.onChanged(Map.from(_ans));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final hasYes = _ans.values.any((v) => v);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _IntakeStepBar(step: 1, total: 24, onBack: widget.onBack),
      Expanded(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 12, 24, bottom + 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('HEALTH SCREENING', style: TextStyle(color: _onSurfV.withValues(alpha: 0.6),
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
          const SizedBox(height: 10),
          const Text('A few quick\nhealth questions', style: TextStyle(color: Colors.white,
            fontSize: 30, fontWeight: FontWeight.w900, height: 1.2)),
          const SizedBox(height: 8),
          Text('Your safety is our priority. These answers help us personalise your program.',
            style: TextStyle(color: _onSurfV.withValues(alpha: 0.7), fontSize: 14, height: 1.5)),
          if (hasYes) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3))),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'Please consult your physician before starting an exercise program.',
                  style: TextStyle(color: const Color(0xFFF59E0B).withValues(alpha: 0.9),
                    fontSize: 12, height: 1.4))),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          ...List.generate(8, (i) {
            final q = i + 1;
            final yes = _ans[q] ?? false;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _surfC,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: yes
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                    : _outlineV.withValues(alpha: 0.3))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 22, height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, color: _surfCHH,
                        border: Border.all(color: _outlineV)),
                      child: Text('$q', style: TextStyle(color: _onSurfV.withValues(alpha: 0.6),
                        fontSize: 10, fontWeight: FontWeight.w700))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_qs[i],
                      style: TextStyle(color: _onSurf.withValues(alpha: 0.85),
                        fontSize: 13, height: 1.45))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _YesNoBtn(label: 'No', selected: !yes,
                      positive: true, onTap: () => _toggle(q, false))),
                    const SizedBox(width: 8),
                    Expanded(child: _YesNoBtn(label: 'Yes', selected: yes,
                      positive: false, onTap: () => _toggle(q, true))),
                  ]),
                ]),
              ),
            );
          }),
        ]),
      )),
      Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, bottom + 24),
        child: _GradientButton(label: 'Continue', onTap: widget.onContinue)),
    ]);
  }
}

class _YesNoBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final bool positive;
  final VoidCallback onTap;
  const _YesNoBtn({required this.label, required this.selected,
    required this.positive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = positive ? const Color(0xFF34D399) : const Color(0xFFF59E0B);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 40,
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.14) : _surfCH,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? c : _outlineV.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1)),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(
          color: selected ? c : _onSurfV.withValues(alpha: 0.6), fontSize: 13,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500))));
  }
}

// ── Medical History ────────────────────────────────────────────────────────────
class _MedicalHistoryPage extends StatefulWidget {
  final List<String> selected;
  final void Function(List<String>) onChanged;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _MedicalHistoryPage({required this.selected, required this.onChanged,
    required this.onContinue, required this.onBack});
  @override
  State<_MedicalHistoryPage> createState() => _MedicalHistoryPageState();
}

class _MedicalHistoryPageState extends State<_MedicalHistoryPage> {
  late List<String> _selected;

  static const _conditions = [
    'High Blood Pressure', 'Low Blood Pressure', 'Heart Disease', 'Diabetes',
    'Thyroid Disorder', 'Asthma', 'Arthritis', 'Back Pain', 'Knee Pain',
    'Hip Pain', 'Shoulder Pain', 'Autoimmune Condition', 'Pregnancy',
    'Postpartum', 'None',
  ];

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.selected);
  }

  void _toggle(String c) {
    setState(() {
      if (c == 'None') {
        _selected = ['None'];
      } else {
        _selected.remove('None');
        _selected.contains(c) ? _selected.remove(c) : _selected.add(c);
      }
    });
    widget.onChanged(List.from(_selected));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _IntakeStepBar(step: 2, total: 24, onBack: widget.onBack),
      Expanded(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 12, 24, bottom + 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('MEDICAL HISTORY', style: TextStyle(color: _onSurfV.withValues(alpha: 0.6),
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
          const SizedBox(height: 10),
          const Text('Any existing\nconditions?', style: TextStyle(color: Colors.white,
            fontSize: 30, fontWeight: FontWeight.w900, height: 1.2)),
          const SizedBox(height: 8),
          Text('Select all that apply. This helps your coach adapt your plan safely.',
            style: TextStyle(color: _onSurfV.withValues(alpha: 0.7), fontSize: 14, height: 1.5)),
          const SizedBox(height: 24),
          Wrap(spacing: 8, runSpacing: 10, children: _conditions.map((c) {
            final sel = _selected.contains(c);
            final isNone = c == 'None';
            return GestureDetector(
              onTap: () => _toggle(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: sel
                    ? (isNone ? const Color(0xFF34D399).withValues(alpha: 0.15) : _priCont.withValues(alpha: 0.15))
                    : _surfC,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: sel
                      ? (isNone ? const Color(0xFF34D399) : _priCont)
                      : _outlineV.withValues(alpha: 0.4),
                    width: sel ? 1.5 : 1)),
                child: Text(c, style: TextStyle(
                  color: sel
                    ? (isNone ? const Color(0xFF34D399) : _priCont)
                    : _onSurfV.withValues(alpha: 0.7),
                  fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.w400))));
          }).toList()),
        ]),
      )),
      Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, bottom + 24),
        child: _GradientButton(
          label: _selected.isEmpty ? 'Skip' : 'Continue',
          onTap: widget.onContinue)),
    ]);
  }
}

// ── Injuries & Limitations ────────────────────────────────────────────────────
class _InjuriesPage extends StatefulWidget {
  final bool hasInjuries;
  final List<String> locations;
  final String description;
  final void Function(bool, List<String>, String) onChanged;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _InjuriesPage({required this.hasInjuries, required this.locations,
    required this.description, required this.onChanged,
    required this.onContinue, required this.onBack});
  @override
  State<_InjuriesPage> createState() => _InjuriesPageState();
}

class _InjuriesPageState extends State<_InjuriesPage> {
  late bool _hasInjuries;
  late List<String> _locations;
  late TextEditingController _descCtrl;

  static const _locs = [
    'Neck', 'Shoulder', 'Elbow', 'Wrist', 'Back', 'Hip', 'Knee', 'Ankle', 'Other',
  ];

  @override
  void initState() {
    super.initState();
    _hasInjuries = widget.hasInjuries;
    _locations   = List.from(widget.locations);
    _descCtrl    = TextEditingController(text: widget.description);
  }

  @override
  void dispose() { _descCtrl.dispose(); super.dispose(); }

  void _notify() =>
    widget.onChanged(_hasInjuries, List.from(_locations), _descCtrl.text);

  void _toggleLocation(String loc) {
    setState(() {
      _locations.contains(loc) ? _locations.remove(loc) : _locations.add(loc);
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _IntakeStepBar(step: 3, total: 24, onBack: widget.onBack),
      Expanded(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 12, 24, bottom + 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('INJURIES & LIMITATIONS', style: TextStyle(color: _onSurfV.withValues(alpha: 0.6),
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
          const SizedBox(height: 10),
          const Text('Any current\ninjuries?', style: TextStyle(color: Colors.white,
            fontSize: 30, fontWeight: FontWeight.w900, height: 1.2)),
          const SizedBox(height: 8),
          Text('Your coach will adjust exercises to work around any limitations.',
            style: TextStyle(color: _onSurfV.withValues(alpha: 0.7), fontSize: 14, height: 1.5)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _YesNoBtn(label: 'No', selected: !_hasInjuries,
              positive: true, onTap: () { setState(() => _hasInjuries = false); _notify(); })),
            const SizedBox(width: 12),
            Expanded(child: _YesNoBtn(label: 'Yes', selected: _hasInjuries,
              positive: false, onTap: () { setState(() => _hasInjuries = true); _notify(); })),
          ]),
          if (_hasInjuries) ...[
            const SizedBox(height: 24),
            Text('AFFECTED AREAS', style: TextStyle(color: _onSurfV.withValues(alpha: 0.6),
              fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: _locs.map((loc) {
              final sel = _locations.contains(loc);
              return GestureDetector(
                onTap: () => _toggleLocation(loc),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFFF59E0B).withValues(alpha: 0.15) : _surfC,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? const Color(0xFFF59E0B) : _outlineV.withValues(alpha: 0.4),
                      width: sel ? 1.5 : 1)),
                  child: Text(loc, style: TextStyle(
                    color: sel ? const Color(0xFFF59E0B) : _onSurfV.withValues(alpha: 0.7),
                    fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.w400))));
            }).toList()),
            const SizedBox(height: 20),
            Text('DESCRIBE THE INJURY (OPTIONAL)', style: TextStyle(color: _onSurfV.withValues(alpha: 0.6),
              fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2)),
            const SizedBox(height: 10),
            TextField(
              controller: _descCtrl,
              onChanged: (_) => _notify(),
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'e.g. Lower back pain from sitting, knee cartilage issue...',
                hintStyle: TextStyle(color: _onSurfV.withValues(alpha: 0.4), fontSize: 13),
                filled: true,
                fillColor: _surfC,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _outlineV.withValues(alpha: 0.3))),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _priCont.withValues(alpha: 0.5))),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _outlineV.withValues(alpha: 0.3)))),
            ),
          ],
        ]),
      )),
      Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, bottom + 24),
        child: _GradientButton(label: 'Continue', onTap: widget.onContinue)),
    ]);
  }
}

// ── Target Timeline ────────────────────────────────────────────────────────────
class _TargetTimelinePage extends StatelessWidget {
  final String selected;
  final void Function(String) onSelect;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _TargetTimelinePage({required this.selected, required this.onSelect,
    required this.onContinue, required this.onBack});

  static const _options = [
    ('30_days', '30 Days', 'Quick start — see early results fast', Icons.bolt_outlined),
    ('60_days', '60 Days', 'Balanced — build momentum steadily', Icons.trending_up_outlined),
    ('90_days', '90 Days', 'Classic — the gold standard transformation', Icons.star_outline),
    ('6_months', '6 Months', 'Deep change — lifestyle transformation', Icons.landscape_outlined),
    ('12_months', '12 Months', 'Long game — lasting, sustainable results', Icons.emoji_events_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _IntakeStepBar(step: 5, total: 24, onBack: onBack),
      Expanded(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 12, 24, bottom + 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('YOUR TIMELINE', style: TextStyle(color: _onSurfV.withValues(alpha: 0.6),
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
          const SizedBox(height: 10),
          const Text('When do you want\nto see results?', style: TextStyle(color: Colors.white,
            fontSize: 30, fontWeight: FontWeight.w900, height: 1.2)),
          const SizedBox(height: 8),
          Text('Your program will be built around your timeline.',
            style: TextStyle(color: _onSurfV.withValues(alpha: 0.7), fontSize: 14, height: 1.5)),
          const SizedBox(height: 24),
          ..._options.map((o) {
            final (val, label, sub, icon) = o;
            final sel = selected == val;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SelectionCard(
                icon: icon,
                title: label,
                subtitle: sub,
                selected: sel,
                onTap: () => onSelect(val),
              ));
          }),
        ]),
      )),
      Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, bottom + 24),
        child: _GradientButton(
          label: selected.isEmpty ? 'Skip' : 'Continue',
          onTap: onContinue)),
    ]);
  }
}

// ── Experience Level ───────────────────────────────────────────────────────────
class _ExperiencePage extends StatefulWidget {
  final String experienceLevel;
  final bool workedWithCoach;
  final void Function(String, bool) onChanged;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _ExperiencePage({required this.experienceLevel, required this.workedWithCoach,
    required this.onChanged, required this.onContinue, required this.onBack});
  @override
  State<_ExperiencePage> createState() => _ExperiencePageState();
}

class _ExperiencePageState extends State<_ExperiencePage> {
  late String _level;
  late bool _coached;

  static const _levels = [
    ('beginner', 'Beginner', 'Less than 1 year of consistent training', Icons.spa_outlined),
    ('intermediate', 'Intermediate', '1–3 years of consistent training', Icons.fitness_center_outlined),
    ('advanced', 'Advanced', '3+ years of consistent training', Icons.military_tech_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _level   = widget.experienceLevel;
    _coached = widget.workedWithCoach;
  }

  void _notify() => widget.onChanged(_level, _coached);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _IntakeStepBar(step: 6, total: 24, onBack: widget.onBack),
      Expanded(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 12, 24, bottom + 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('EXPERIENCE', style: TextStyle(color: _onSurfV.withValues(alpha: 0.6),
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
          const SizedBox(height: 10),
          const Text("What's your training\nbackground?", style: TextStyle(color: Colors.white,
            fontSize: 30, fontWeight: FontWeight.w900, height: 1.2)),
          const SizedBox(height: 24),
          ..._levels.map((l) {
            final (val, label, sub, icon) = l;
            final sel = _level == val;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SelectionCard(
                icon: icon, title: label, subtitle: sub, selected: sel,
                onTap: () { setState(() => _level = val); _notify(); }));
          }),
          const SizedBox(height: 28),
          Text('COACHING EXPERIENCE', style: TextStyle(color: _onSurfV.withValues(alpha: 0.6),
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
          const SizedBox(height: 10),
          Text('Have you worked with a personal coach before?',
            style: TextStyle(color: _onSurf.withValues(alpha: 0.85), fontSize: 15, height: 1.4)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _YesNoBtn(label: 'No', selected: !_coached,
              positive: true, onTap: () { setState(() => _coached = false); _notify(); })),
            const SizedBox(width: 12),
            Expanded(child: _YesNoBtn(label: 'Yes', selected: _coached,
              positive: true, onTap: () { setState(() => _coached = true); _notify(); })),
          ]),
        ]),
      )),
      Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, bottom + 24),
        child: _GradientButton(
          label: _level.isEmpty ? 'Skip' : 'Continue',
          onTap: widget.onContinue)),
    ]);
  }
}

// ── Lifestyle ──────────────────────────────────────────────────────────────────
class _LifestylePage extends StatefulWidget {
  final String sleepHours;
  final int stressLevel;
  final String occupation;
  final void Function(String, int, String) onChanged;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _LifestylePage({required this.sleepHours, required this.stressLevel,
    required this.occupation, required this.onChanged,
    required this.onContinue, required this.onBack});
  @override
  State<_LifestylePage> createState() => _LifestylePageState();
}

class _LifestylePageState extends State<_LifestylePage> {
  late String _sleep;
  late int _stress;
  late TextEditingController _occCtrl;

  static const _sleepOptions = [
    ('lt5',    '< 5 hrs'),
    ('5_6',    '5–6 hrs'),
    ('6_7',    '6–7 hrs'),
    ('7_8',    '7–8 hrs'),
    ('8_plus', '8+ hrs'),
  ];

  @override
  void initState() {
    super.initState();
    _sleep   = widget.sleepHours;
    _stress  = widget.stressLevel.clamp(0, 10);
    _occCtrl = TextEditingController(text: widget.occupation);
  }

  @override
  void dispose() { _occCtrl.dispose(); super.dispose(); }

  void _notify() => widget.onChanged(_sleep, _stress, _occCtrl.text);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _IntakeStepBar(step: 14, total: 24, onBack: widget.onBack),
      Expanded(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 12, 24, bottom + 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('LIFESTYLE', style: TextStyle(color: _onSurfV.withValues(alpha: 0.6),
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
          const SizedBox(height: 10),
          const Text('Tell us about\nyour daily life', style: TextStyle(color: Colors.white,
            fontSize: 30, fontWeight: FontWeight.w900, height: 1.2)),
          const SizedBox(height: 8),
          Text('Recovery and lifestyle factors are as important as training itself.',
            style: TextStyle(color: _onSurfV.withValues(alpha: 0.7), fontSize: 14, height: 1.5)),
          const SizedBox(height: 28),
          Text('AVERAGE SLEEP', style: TextStyle(color: _onSurfV.withValues(alpha: 0.6),
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: _sleepOptions.map((s) {
            final (val, label) = s;
            final sel = _sleep == val;
            return GestureDetector(
              onTap: () { setState(() => _sleep = val); _notify(); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? _priCont.withValues(alpha: 0.15) : _surfC,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: sel ? _priCont : _outlineV.withValues(alpha: 0.4),
                    width: sel ? 1.5 : 1)),
                child: Text(label, style: TextStyle(
                  color: sel ? _priCont : _onSurfV.withValues(alpha: 0.7),
                  fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.w400))));
          }).toList()),
          const SizedBox(height: 28),
          Text('STRESS LEVEL', style: TextStyle(color: _onSurfV.withValues(alpha: 0.6),
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2)),
          const SizedBox(height: 6),
          Row(children: [
            Text('Low', style: TextStyle(color: _onSurfV.withValues(alpha: 0.5), fontSize: 12)),
            Expanded(child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: _priCont,
                inactiveTrackColor: _surfCHH,
                thumbColor: _priCont,
                overlayColor: _priCont.withValues(alpha: 0.15),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                trackHeight: 4),
              child: Slider(
                value: _stress.toDouble(),
                min: 0, max: 10, divisions: 10,
                label: _stress == 0 ? 'Not set' : '$_stress/10',
                onChanged: (v) { setState(() => _stress = v.round()); _notify(); },
              ))),
            Text('High', style: TextStyle(color: _onSurfV.withValues(alpha: 0.5), fontSize: 12)),
          ]),
          if (_stress > 0)
            Center(child: Text('$_stress / 10',
              style: TextStyle(color: _priCont, fontSize: 16, fontWeight: FontWeight.w700))),
          const SizedBox(height: 28),
          Text('OCCUPATION', style: TextStyle(color: _onSurfV.withValues(alpha: 0.6),
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2)),
          const SizedBox(height: 10),
          TextField(
            controller: _occCtrl,
            onChanged: (_) => _notify(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. Software engineer, nurse, teacher...',
              hintStyle: TextStyle(color: _onSurfV.withValues(alpha: 0.4), fontSize: 13),
              filled: true, fillColor: _surfC,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _outlineV.withValues(alpha: 0.3))),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _priCont.withValues(alpha: 0.5))),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _outlineV.withValues(alpha: 0.3)))),
          ),
        ]),
      )),
      Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, bottom + 24),
        child: _GradientButton(label: 'Continue', onTap: widget.onContinue)),
    ]);
  }
}

// ── Dietary Restrictions ───────────────────────────────────────────────────────
class _DietaryRestrictionsPage extends StatefulWidget {
  final List<String> selected;
  final String allergies;
  final void Function(List<String>, String) onChanged;
  final VoidCallback onContinue;
  final VoidCallback onSkip;
  final VoidCallback onBack;
  const _DietaryRestrictionsPage({required this.selected, required this.allergies,
    required this.onChanged, required this.onContinue,
    required this.onSkip, required this.onBack});
  @override
  State<_DietaryRestrictionsPage> createState() => _DietaryRestrictionsPageState();
}

class _DietaryRestrictionsPageState extends State<_DietaryRestrictionsPage> {
  late List<String> _selected;
  late TextEditingController _allergyCtrl;

  static const _restrictions = [
    'Vegetarian', 'Vegan', 'Gluten Free', 'Dairy Free',
    'Keto', 'Paleo', 'Halal', 'Kosher', 'Other',
  ];

  @override
  void initState() {
    super.initState();
    _selected    = List.from(widget.selected);
    _allergyCtrl = TextEditingController(text: widget.allergies);
  }

  @override
  void dispose() { _allergyCtrl.dispose(); super.dispose(); }

  void _toggle(String r) {
    setState(() {
      _selected.contains(r) ? _selected.remove(r) : _selected.add(r);
    });
    widget.onChanged(List.from(_selected), _allergyCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _IntakeStepBar(step: 16, total: 24, onBack: widget.onBack, onSkip: widget.onSkip),
      Expanded(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 12, 24, bottom + 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DIETARY PREFERENCES', style: TextStyle(color: _onSurfV.withValues(alpha: 0.6),
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
          const SizedBox(height: 10),
          const Text('Any dietary\nrestrictions?', style: TextStyle(color: Colors.white,
            fontSize: 30, fontWeight: FontWeight.w900, height: 1.2)),
          const SizedBox(height: 8),
          Text('Your meal plans and nutrition advice will respect your dietary needs.',
            style: TextStyle(color: _onSurfV.withValues(alpha: 0.7), fontSize: 14, height: 1.5)),
          const SizedBox(height: 24),
          Wrap(spacing: 8, runSpacing: 8, children: _restrictions.map((r) {
            final sel = _selected.contains(r);
            return GestureDetector(
              onTap: () => _toggle(r),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? _priCont.withValues(alpha: 0.15) : _surfC,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: sel ? _priCont : _outlineV.withValues(alpha: 0.4),
                    width: sel ? 1.5 : 1)),
                child: Text(r, style: TextStyle(
                  color: sel ? _priCont : _onSurfV.withValues(alpha: 0.7),
                  fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.w400))));
          }).toList()),
          const SizedBox(height: 28),
          Text('FOOD ALLERGIES (OPTIONAL)', style: TextStyle(color: _onSurfV.withValues(alpha: 0.6),
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2)),
          const SizedBox(height: 10),
          TextField(
            controller: _allergyCtrl,
            onChanged: (v) => widget.onChanged(List.from(_selected), v),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. Peanuts, shellfish, eggs...',
              hintStyle: TextStyle(color: _onSurfV.withValues(alpha: 0.4), fontSize: 13),
              filled: true, fillColor: _surfC,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _outlineV.withValues(alpha: 0.3))),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _priCont.withValues(alpha: 0.5))),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _outlineV.withValues(alpha: 0.3)))),
          ),
        ]),
      )),
      Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, bottom + 24),
        child: _GradientButton(label: 'Continue', onTap: widget.onContinue)),
    ]);
  }
}

// ── Consent ───────────────────────────────────────────────────────────────────
class _ConsentPage extends StatefulWidget {
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _ConsentPage({required this.onContinue, required this.onBack});
  @override
  State<_ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<_ConsentPage> {
  bool _c1 = false;
  bool _c2 = false;
  bool _c3 = false;

  bool get _allChecked => _c1 && _c2 && _c3;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _IntakeStepBar(step: 23, total: 24, onBack: widget.onBack),
      Expanded(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 12, 24, bottom + 100),
        child: Column(children: [
          const SizedBox(height: 20),
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [_priCont.withValues(alpha: 0.8), _terCont.withValues(alpha: 0.8)],
                begin: Alignment.topLeft, end: Alignment.bottomRight)),
            child: const Icon(Icons.shield_outlined, color: Colors.white, size: 40)),
          const SizedBox(height: 24),
          const Text('Almost Done!', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('Please read and agree to the following before starting your program.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _onSurfV.withValues(alpha: 0.7), fontSize: 14, height: 1.5)),
          const SizedBox(height: 36),
          _ConsentItem(
            checked: _c1,
            text: 'I confirm that the information I have provided is accurate to the best of my knowledge.',
            onChanged: (v) => setState(() => _c1 = v!),
          ),
          const SizedBox(height: 12),
          _ConsentItem(
            checked: _c2,
            text: 'I understand that participation in exercise carries inherent risks and I take responsibility for my own safety.',
            onChanged: (v) => setState(() => _c2 = v!),
          ),
          const SizedBox(height: 12),
          _ConsentItem(
            checked: _c3,
            text: 'I agree to consult a physician if recommended based on my health screening responses.',
            onChanged: (v) => setState(() => _c3 = v!),
          ),
          const SizedBox(height: 32),
          Text('By proceeding you agree to the 12 Circle Fitness Terms of Service and Privacy Policy.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _onSurfV.withValues(alpha: 0.45), fontSize: 11, height: 1.5)),
        ]),
      )),
      Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, bottom + 24),
        child: Opacity(
          opacity: _allChecked ? 1.0 : 0.45,
          child: _GradientButton(
            label: 'I Agree — Start My Journey',
            onTap: _allChecked ? widget.onContinue : () {}))),
    ]);
  }
}

class _ConsentItem extends StatelessWidget {
  final bool checked;
  final String text;
  final void Function(bool?) onChanged;
  const _ConsentItem({required this.checked, required this.text, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!checked),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: checked ? _priCont.withValues(alpha: 0.08) : _surfC,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: checked ? _priCont.withValues(alpha: 0.4) : _outlineV.withValues(alpha: 0.3),
            width: checked ? 1.5 : 1)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 22, height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: checked ? _priCont : Colors.transparent,
              border: Border.all(
                color: checked ? _priCont : _outlineV.withValues(alpha: 0.5),
                width: 1.5)),
            child: checked
              ? const Icon(Icons.check, color: Colors.white, size: 14)
              : null),
          const SizedBox(width: 12),
          Expanded(child: Text(text,
            style: TextStyle(
              color: checked ? _onSurf : _onSurfV.withValues(alpha: 0.7),
              fontSize: 13, height: 1.5))),
        ]),
      ),
    );
  }
}
