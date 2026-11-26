import 'dart:async' show StreamSubscription;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, Supabase;

import '../../../../core/observability/app_failure.dart';

const _card     = Color(0xFF0E0B16);
const _brand    = Color(0xFFA855F7);
const _white    = Colors.white;
const _muted    = Color(0xFFCFC2D6);
const _tertiary = Color(0xFF6FFBBE);

class FoodAddedDialog extends StatelessWidget {
  final String foodName;
  final int protein, carbs, fat;

  const FoodAddedDialog({
    super.key,
    required this.foodName,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  /// P0-FL-59e · [owner]: the member whose meal it is. The dialog goes when
  /// anyone else is signed in (or nobody is), and is never drawn for them.
  /// Pushed after an await and a pop, it has no page or sheet left to do it.
  static Future<void> show(
    BuildContext context, {
    required ({String? uid})? owner,
    required String foodName,
    required int protein,
    required int carbs,
    required int fat,
  }) {
    final dialog = FoodAddedDialog(
      foodName: foodName,
      protein: protein,
      carbs: carbs,
      fat: fat,
    );
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => owner == null
          ? dialog
          : _ForMember(uid: owner.uid, child: dialog),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // ── Smoke background image ────────────────────────────────
            Positioned.fill(
              child: Image.asset(
                'assets/images/purple_energy_smoke.png',
                fit: BoxFit.cover,
              ),
            ),
            // ── Dark overlay so text stays readable ───────────────────
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _card.withValues(alpha: 0.55),
                      _card.withValues(alpha: 0.90),
                      _card.withValues(alpha: 0.97),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
            // ── Purple border ring ────────────────────────────────────
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: _brand.withValues(alpha: 0.25), width: 1.5),
                ),
              ),
            ),
            // ── Content ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Check circle
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _tertiary.withValues(alpha: 0.1),
                      border: Border.all(color: _tertiary.withValues(alpha: 0.5), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: _tertiary.withValues(alpha: 0.2),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.check_rounded, color: _tertiary, size: 36),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Food Added!',
                    style: TextStyle(
                      color: _white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$foodName has been added to your diet schedule.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _muted.withValues(alpha: 0.65),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Macro row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _MacroChip('Protein', protein, const Color(0xFFA855F7)),
                        _MacroChip('Carbs',   carbs,   const Color(0xFF6FFBBE)),
                        _MacroChip('Fat',     fat,     const Color(0xFFFFB4AB)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  // CTA button
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C3AED), Color(0xFFB44CF0)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: _brand.withValues(alpha: 0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Great, thanks!',
                        style: TextStyle(
                          color: _white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
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

/// [child], in a route of its own, while [uid] is the member signed in; the
/// route goes with them.
class _ForMember extends StatefulWidget {
  final String? uid;
  final Widget child;
  const _ForMember({required this.uid, required this.child});

  @override
  State<_ForMember> createState() => _ForMemberState();
}

class _ForMemberState extends State<_ForMember> {
  StreamSubscription<AuthState>? _authSub;

  bool get _theirs =>
      Supabase.instance.client.auth.currentUser?.id == widget.uid;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (!_theirs) _close();
    },
        onError: (Object e, StackTrace s) =>
            reportError('FoodAddedDialog.onAuthStateChange', e, s));
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isActive && !route.isFirst) {
      route.navigator?.removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_theirs) return widget.child;
    // Switched before it was first drawn: never drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    return const SizedBox.shrink();
  }
}

class _MacroChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _MacroChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            '${value}g',
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(color: _muted.withValues(alpha: 0.45), fontSize: 10),
          ),
        ],
      );
}
