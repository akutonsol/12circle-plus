import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// `/checkin-form` — a redirect, not a screen.
///
/// It used to render a near-empty page titled "Check-In Form" with a single
/// button reading "Go to Daily Check-In". A client tapping a **pending**
/// check-in card (`checkin_card.dart:25`) landed here and had to press again to
/// reach the form they had already asked for.
///
/// `/daily-checkin` is the form. Two sibling routes — `/log-meal` and
/// `/food-search` — already resolve this way, so this follows the pattern the
/// router established rather than adding a third shape.
class CheckinFormScreen extends ConsumerStatefulWidget {
  const CheckinFormScreen({super.key});
  @override
  ConsumerState<CheckinFormScreen> createState() => _CheckinFormScreenState();
}

class _CheckinFormScreenState extends ConsumerState<CheckinFormScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/daily-checkin');
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Color(0xFF030303),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFA855F7))),
      );
}
