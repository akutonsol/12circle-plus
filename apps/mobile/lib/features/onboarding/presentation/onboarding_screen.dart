import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ── Brand ─────────────────────────────────────────────────────────────────────
const _purple      = Color(0xFF7C3AED);
const _purpleLight = Color(0xFFB06BFF);
const _pink        = Color(0xFFFF4FB0);
const _muted       = Color(0xFFB9B2C7);

/// Onboarding screen 2 — the welcome. Hero athlete, "TRAIN LIKE YOU MEAN IT",
/// and a slide-to-start control that confirms into the create-account flow.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050409),
      body: Stack(children: [
        // ── Hero athlete (top), fading to black ──
        Positioned(
          top: 0, left: 0, right: 0,
          height: MediaQuery.of(context).size.height * 0.62,
          child: ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0.0, 0.55, 1.0]).createShader(r),
            blendMode: BlendMode.dstIn,
            child: Image.asset('assets/images/splash_hero1.jpg',
              fit: BoxFit.cover, alignment: const Alignment(0.55, -0.2)),
          ),
        ),
        const DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0x33050409), Color(0x00050409), Color(0xCC050409), Color(0xFF050409)],
            stops: [0.0, 0.35, 0.7, 1.0]))),

        // ── Top brand bar ──
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Row(children: [
              SizedBox(width: 34, height: 34,
                child: Image.asset('assets/images/12circle-fab.png', fit: BoxFit.contain)),
              const SizedBox(width: 10),
              const Text('12Circle Fitness', style: TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            ]),
          ),
        ),

        // ── Bottom content ──
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('WELCOME TO YOUR JOURNEY', style: TextStyle(
                  color: _purpleLight, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 3)),
                const SizedBox(height: 14),
                const Text('TRAIN LIKE\nYOU MEAN IT', style: TextStyle(
                  color: Colors.white, fontSize: 42, height: 1.02,
                  fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 16),
                const Text(
                  'Coaching, workouts, and progress tracking built\nto push you through all 12 weeks.',
                  style: TextStyle(color: _muted, fontSize: 15, height: 1.5)),
                const SizedBox(height: 28),
                _SlideToStart(onConfirm: () => context.go('/signup')),
                const SizedBox(height: 18),
                // FIT-006 declares "I already have one". The visible text is
                // what changed — an accessible name has to contain the visible
                // label (WCAG 2.5.3), so announcing the design's phrase over
                // "Already a member? Sign In" would have been a violation
                // dressed up as coverage. The destination is unchanged.
                Center(child: Semantics(
                  button: true,
                  child: GestureDetector(
                    onTap: () => context.go('/login'),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      alignment: Alignment.center,
                      child: const Text('I already have one', style: TextStyle(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ),
                )),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Slide-to-start control ────────────────────────────────────────────────────
class _SlideToStart extends StatefulWidget {
  final VoidCallback onConfirm;
  const _SlideToStart({required this.onConfirm});
  @override
  State<_SlideToStart> createState() => _SlideToStartState();
}

class _SlideToStartState extends State<_SlideToStart>
    with SingleTickerProviderStateMixin {
  static const _h = 64.0;
  double _dx = 0;
  bool _done = false;
  late final AnimationController _hint;

  @override
  void initState() {
    super.initState();
    _hint = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _hint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final maxDx = c.maxWidth - _h;
      void end() {
        if (_dx > maxDx * 0.62) {
          setState(() { _dx = maxDx; _done = true; });
          widget.onConfirm();
        } else {
          setState(() => _dx = 0);
        }
      }
      final knob = _h - 8;
      return Semantics(
        // ── F-26 ────────────────────────────────────────────────────────────
        // This is the app's FRONT DOOR and it was drag-only:
        // `onHorizontalDragUpdate` / `onHorizontalDragEnd`, no tap, no
        // semantics. A screen-reader user, or anyone who cannot perform a
        // precise horizontal drag — switch access, tremor, limited dexterity —
        // **could not create an account at all.**
        //
        // The slide stays: it is what the design draws, and the friction is
        // deliberate. What is added is a single activatable node for the
        // accessibility APIs, which is the standard remedy and changes nothing
        // on screen. FIT-006's own words name it.
        button: true,
        label: 'Create your account',
        excludeSemantics: true,
        onTap: widget.onConfirm,
        child: Container(
        height: _h,
        decoration: BoxDecoration(
          color: const Color(0xFF14101F),
          borderRadius: BorderRadius.circular(_h),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_h),
          child: Stack(children: [
            // Gradient fill that grows from the left as you slide.
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(
                width: (4 + _dx + knob).clamp(knob, c.maxWidth),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [_pink, _purple])))),
            // Label sits to the right of the knob, fading as it nears.
            Positioned(
              left: _h + 10, top: 0, right: 16, bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Opacity(
                  opacity: (1 - (_dx / maxDx) * 1.7).clamp(0.0, 1.0),
                  // FIT-006's wording for this control.
                  child: const Text('Create your account', style: TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))))),
            // Draggable knob with arrow.
            Positioned(
              left: 4 + _dx, top: 4,
              child: AnimatedBuilder(
                animation: _hint,
                builder: (_, child) => Transform.translate(
                  offset: Offset(_dx == 0 && !_done ? _hint.value * 6 : 0, 0), child: child),
                child: GestureDetector(
                  onHorizontalDragUpdate: (d) {
                    if (_done) return;
                    setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, maxDx));
                  },
                  onHorizontalDragEnd: (_) => end(),
                  onTap: () { setState(() { _dx = maxDx; _done = true; }); widget.onConfirm(); },
                  child: Container(
                    width: knob, height: knob,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [_purpleLight, _purple],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: [BoxShadow(color: _purple.withValues(alpha: 0.5), blurRadius: 16)]),
                    child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 24)),
                ),
              ),
            ),
          ]),
        ),
      ),
      );
    });
  }
}
