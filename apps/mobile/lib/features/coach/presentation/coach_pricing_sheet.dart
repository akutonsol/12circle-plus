import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';
import '../../../core/observability/network_failure.dart';
import '../data/coach_relationship_service.dart';

const _bg     = Color(0xFF030303);
const _card   = Color(0xFF0E0B16);
const _border = Color(0xFF1A1020);
const _brand  = Color(0xFFA855F7);
const _white  = Colors.white;
const _muted  = Color(0xFFCFC2D6);
const _errRed = Color(0xFFFFB4AB);

/// Coach sets their global monthly coaching price (applies to all clients
/// unless a per-client custom price is set from that client's profile).
void showCoachPricingSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CoachPricingSheet(),
  );
}

class _CoachPricingSheet extends StatefulWidget {
  const _CoachPricingSheet();
  @override
  State<_CoachPricingSheet> createState() => _CoachPricingSheetState();
}

class _CoachPricingSheetState extends State<_CoachPricingSheet> {
  final _price = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  /// Why the last save did not happen, shown inside the sheet. A SnackBar
  /// went to the page's messenger, under this modal, so the coach saw only
  /// the spinner stop.
  String? _error;

  /// P0-FL-59d · the coach whose price this is. It stayed open over a switch
  /// on this device, and Save wrote the price one coach had loaded (or typed)
  /// onto the next coach.
  String? _owner;
  StreamSubscription<AuthState>? _authSub;

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
    // Same coach (a token refresh, the stream's replay) changes nothing.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
        (_) => _followAccount(),
        onError: (Object e, StackTrace s) =>
            reportError('CoachPricingSheet.onAuthStateChange', e, s));
  }

  /// The sheet goes, with what was typed, with the coach it was opened for.
  void _followAccount() {
    if (!mounted || _uid == _owner) return;
    if (_owner == null) {
      _retry(); // opened signed out: nobody's price was shown
      return;
    }
    _price.clear();
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  /// Why the opening read did not produce the coach's current price. While
  /// set, the failure stands IN PLACE of the price field and Save (P0-FL-6):
  /// an empty field reads as "no price set", and the coach could save over a
  /// price they never saw. A disabled empty field would still say that.
  String? _loadError;

  /// Signed out there is no price to read or write; say so, not an empty field.
  bool _signedOut = false;

  static const _signedOutMsg =
      "You're signed out — sign in again to set your price.";
  static const _checkConnection = 'Check your connection and try again.';
  static const _tryLater =
      'Try again in a moment. If it keeps happening, contact support.';
  static const _saveFailedMsg =
      "Couldn't confirm your price was saved — it may still have saved. "
      'Reopen this to check, or try again in a moment. If it keeps happening, '
      'contact support.';

  /// Try again: back to the opening spinner (so a second tap cannot start a
  /// second read), then the same read.
  void _retry() {
    setState(() {
      _loading = true;
      _loadError = null;
      _signedOut = false;
    });
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    _owner = uid;
    if (uid == null) {
      setState(() {
        _signedOut = true;
        _loading = false;
      });
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('user_profiles')
          .select('pricing_monthly')
          .eq('id', uid)
          .maybeSingle();
      // Closed while reading: the field is disposed, and writing to it was
      // recorded as a failed read.
      if (!mounted || _uid != uid) return;
      final p = (row?['pricing_monthly'] as num?)?.toDouble();
      if (p != null && p > 0) _price.text = p.toStringAsFixed(0);
    } catch (e, s) {
      reportError('CoachPricingSheet._load', e, s);
      if (!mounted || _uid != uid) return;
      setState(() {
        _loadError = isNetworkFailure(e) ? _checkConnection : _tryLater;
        _loading = false;
      });
      return;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final owner = _owner;
    if (owner == null || _uid != owner) {
      reportError('CoachPricingSheet._save',
          StateError('Coaching price: the signed-in account changed'));
      _followAccount();
      return;
    }
    final value = double.tryParse(_price.text.trim());
    if (value == null || value <= 0) {
      // Same rule as before (whether $0 is valid is undecided) — but say it.
      setState(() => _error = r'Enter a monthly price above $0.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await CoachRelationshipService().setGlobalPrice(value, expectedUid: owner);
    } catch (e, s) {
      reportError('CoachPricingSheet._save', e, s); // P0-FL-56b: was unrecorded
      // A failed or 0-row save said "Pricing updated." or, thrown, left the
      // spinner running with nothing said (P0-FL-3). Keep the sheet open and
      // say why inside it. A generic failure (e.g. a timeout) may still have
      // committed, so it does not claim nothing changed.
      // Like _load: the connection hint only for a failure to reach the
      // server; any other failure gets the try-later step — never the
      // server's own text.
      if (!mounted || _uid != owner) return;
      setState(() {
        _saving = false;
        _error = e is StateError
            ? e.message
            : isNetworkFailure(e)
                ? "Couldn't save your price — check your connection and try again."
                : _saveFailedMsg;
      });
      return;
    }
    if (!mounted || _uid != owner) return;
    setState(() => _saving = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pricing updated. Clients will see your new rate.')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      // Scrolls rather than overflows at large text on a short screen.
      child: SingleChildScrollView(child: Container(
        decoration: const BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: _border)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: _border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Coaching Price',
                style: TextStyle(color: _white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
                'Your standard monthly rate. This applies to all clients — you can '
                'still set a custom price for an individual client from their profile.',
                style: TextStyle(color: _muted, fontSize: 13, height: 1.4)),
            const SizedBox(height: 18),
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                    color: _brand, semanticsLabel: 'Loading your price'))),
            if (!_loading && _signedOut)
              Semantics(
                liveRegion: true,
                child: Text(_signedOutMsg,
                    style: const TextStyle(color: _errRed, fontSize: 13, height: 1.4)),
              ),
            if (!_loading && _loadError != null)
              Semantics(
                liveRegion: true,
                container: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Couldn't load your current price",
                        style: TextStyle(color: _white, fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(_loadError!,
                        style: const TextStyle(color: _errRed, fontSize: 13, height: 1.4)),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded, color: _brand, size: 18),
                      label: const Text('Try again',
                          style: TextStyle(color: _brand, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            if (!_loading && !_signedOut && _loadError == null) ...[
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                style: const TextStyle(color: _white, fontSize: 18, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  prefixStyle: const TextStyle(color: _white, fontSize: 18, fontWeight: FontWeight.w700),
                  suffixText: '/month',
                  suffixStyle: const TextStyle(color: _muted),
                  filled: true,
                  fillColor: _bg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _brand)),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(_error!,
                        style: const TextStyle(color: _errRed, fontSize: 13, height: 1.4)),
                  ),
                ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: _white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _white))
                      : const Text('Save price', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ],
        ),
      )),
    );
  }
}
