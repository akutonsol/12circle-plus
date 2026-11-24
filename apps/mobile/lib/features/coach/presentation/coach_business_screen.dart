import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/observability/app_failure.dart';
import '../../../core/observability/network_failure.dart';
import '../../auth/domain/auth_provider.dart' show confirmedProfileRead;

// ── Palette ───────────────────────────────────────────────────────────────────
const _bg    = Color(0xFF030303);
const _card  = Color(0xFF0E0B16);
const _brd   = Color(0xFF1A1020);
const _brand = Color(0xFFA855F7);
const _wht   = Colors.white;
const _mut   = Color(0xFFCFC2D6);

// ── UC35 Coach Business Profile ───────────────────────────────────────────────
class CoachBusinessScreen extends StatefulWidget {
  const CoachBusinessScreen({super.key});
  @override
  State<CoachBusinessScreen> createState() => _CoachBusinessScreenState();
}

class _CoachBusinessScreenState extends State<CoachBusinessScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _db = Supabase.instance.client;

  // Profile fields
  final _bioCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _yearsCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();
  List<String> _specialties = [];
  List<String> _certifications = [];
  bool _saving = false;
  bool _loading = true;
  Map<String, dynamic>? _profile;

  // Team members
  List<Map<String, dynamic>> _team = [];
  List<Map<String, dynamic>> _reviews = [];

  static const _specialtyOptions = [
    'Fat Loss', 'Muscle Building', 'Women\'s Fitness', 'Bikini Prep',
    'Strength Training', 'Nutrition Coaching', 'Functional Fitness',
    'Online Only', 'Powerlifting', 'HIIT', 'Yoga', 'Mobility',
  ];

  /// P0-FL-54 · the coach this screen belongs to: the one whose read is in
  /// flight or whose profile, team and reviews are shown. Null when signed out.
  ///
  /// Everything above is State, so it outlived a sign-out/sign-in: coach A's
  /// bio, price, certifications and photos stayed on screen for coach B, a
  /// late A read could land after B signed in, and Save/certifications/photo
  /// wrote A's state with `.eq('id', <B's id>)` — A's data into B's row.
  String? _owner;

  /// The coach whose data is in the form, team and reviews ([_owner] once
  /// their read landed). Every write refuses unless the signed-in id is this.
  String? _loadedFor;

  /// Bumped by every load and by every account change: a read that answers
  /// after a newer one started (or after the account changed) is dropped.
  int _loadSeq = 0;
  StreamSubscription<AuthState>? _authSub;

  /// The coaches whose transformation photo is on its way. While the coach
  /// shown has one, a second tap would copy the same list and one of the two
  /// photos would be lost. Keyed per coach so another coach who signs in
  /// meanwhile is not shown "Adding…" for the previous coach's pick — and
  /// (r3) so that coach's own guard is still there when they come back.
  final _uploadingFor = <String>{};
  bool get _uploadingPhoto => _loadedFor != null && _uploadingFor.contains(_loadedFor);

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
    // Follow the session every write is filtered by. Same coach (token
    // refresh, the stream's replay of the current session) changes nothing.
    _authSub = _db.auth.onAuthStateChange.listen((_) => _followAccount(),
        onError: (Object e, StackTrace s) =>
            reportError('CoachBusinessScreen.onAuthStateChange', e, s));
  }

  void _followAccount() {
    if (!mounted) return;
    final uid = _db.auth.currentUser?.id;
    if (uid == _owner) return;
    _forget();
    if (uid == null) {
      _loadSeq++;
      setState(() {
        _loading = false;
        _loadError = _signedOutBody;
      });
      return;
    }
    _load();
  }

  /// Nothing of the previous coach's stays: form, lists, team, reviews.
  void _forget() {
    for (final c in [_bioCtrl, _priceCtrl, _yearsCtrl, _taglineCtrl]) {
      c.clear();
    }
    _specialties = [];
    _certifications = [];
    _profile = null;
    _team = [];
    _reviews = [];
    _owner = null;
    _loadedFor = null;
    _priceErrorText = null;
    _yearsErrorText = null;
  }

  /// The signed-in coach's id when the shown data is theirs; otherwise says
  /// why nothing is written and returns null.
  String? _requireShownCoach(String what) {
    final uid = _requireSignedIn();
    if (uid == null) return null;
    if (uid != _loadedFor) {
      _say(_otherAccount(what), error: true);
      return null;
    }
    return uid;
  }

  /// The shown data belongs to the coach signed in now.
  bool get _showsSignedInCoach =>
      _loadedFor != null && _loadedFor == _db.auth.currentUser?.id;

  @override
  void dispose() {
    _authSub?.cancel();
    _tab.dispose();
    _bioCtrl.dispose(); _priceCtrl.dispose();
    _yearsCtrl.dispose(); _taglineCtrl.dispose();
    _priceFocus.dispose(); _yearsFocus.dispose();
    super.dispose();
  }

  final _priceFocus = FocusNode(debugLabel: 'business price');
  final _yearsFocus = FocusNode(debugLabel: 'business years');

  /// True while a certification write is on its way: a second add/remove is
  /// ignored so two optimistic updates never race each other, and Save is
  /// disabled — Save writes the whole certifications list, so a Save sent
  /// during a cert write would carry the optimistic list, and if that cert
  /// write then failed and rolled back, the database would keep a list the
  /// screen no longer shows. The other direction: while Save is in flight,
  /// cert add/remove are ignored.
  bool _certWriteInFlight = false;

  // ── What happened, said plainly ───────────────────────────────────────────
  // A failed read is never an editable blank form (one Save would overwrite
  // the coach's real profile with blanks), and nothing says "updated/added"
  // unless the server returned the row it changed — RLS filters a refused
  // update to 0 rows without an error.
  static const _signedOutMsg = "You're signed out — sign in again to save.";
  static const _signedOutBody =
      "You're signed out — sign in again to see your business profile.";

  /// A write refused because the shown profile is no longer the signed-in
  /// coach's (another account signed in since it was read).
  static String _otherAccount(String what) =>
      "Couldn't $what — you're signed in to a different account now. "
      'Nothing was changed. Check the profile shown, then try again.';

  /// The invite started for [uid] may still go on: [uid] is still the coach
  /// signed in and the coach whose team was shown (the screen may be gone).
  bool _stillInvitingAs(String uid) =>
      _db.auth.currentUser?.id == uid && _loadedFor == uid;
  static const _priceError = 'Enter a monthly price in dollars, e.g. 150.';
  static const _yearsError = 'Enter years of experience as a whole number, e.g. 5.';
  static const _bothError =
      'Enter the monthly price in dollars (e.g. 150) and years of experience '
      'as a whole number (e.g. 5).';
  static const _checkConnection = 'Check your connection and try again.';
  static const _tryLater =
      'Try again in a moment. If it keeps happening, contact support.';
  static const _blankKept =
      'Profile updated. A blank price or years field keeps its saved value.';
  static const _inviteEmailNotSent =
      "Invite saved, but the email couldn't be sent — ask them to check back, "
      'or send the invite again later.';

  /// "Couldn't WHAT — NEXT STEP." for a thrown failure.
  static String _couldnt(String what, Object e) => isNetworkFailure(e)
      ? "Couldn't $what — check your connection and try again."
      : "Couldn't $what — try again in a moment. If it keeps happening, "
          'contact support.';

  /// "Couldn't WHAT — nothing was changed." for a 0-row write.
  static String _couldntNothingChanged(String what) =>
      "Couldn't $what — nothing was changed. $_tryLater";

  /// Whole numbers read back as "149", not "149.0".
  static String _numText(Object? v) =>
      v is num && v.isFinite && v == v.roundToDouble()
          ? v.toInt().toString()
          : (v ?? '').toString();

  /// Set when the last load did not produce the coach's profile. While set,
  /// the form and Save are not shown.
  String? _loadError;
  String? _priceErrorText;
  String? _yearsErrorText;

  /// The signed-in coach's id, or null after telling them they are signed out.
  String? _requireSignedIn() {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) _say(_signedOutMsg, error: true);
    return uid;
  }

  void _say(String msg, {bool error = false, SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(_snack(msg, error: error, action: action));
  }

  /// The one SnackBar style on this screen (also used where only a captured
  /// messenger is available, e.g. after a dialog closed). With an [action]
  /// it stays longer (time to reach it) but still goes by itself.
  static SnackBar _snack(String msg,
          {bool error = false, SnackBarAction? action}) =>
      SnackBar(
          content: Text(msg),
          action: action,
          persist: action == null ? null : false,
          duration: action == null
              ? const Duration(milliseconds: 4000)
              : const Duration(seconds: 10),
          backgroundColor:
              error ? const Color(0xFFFFB4AB) : const Color(0xFF6FFBBE));

  void _clearPriceError() {
    if (_priceErrorText != null) setState(() => _priceErrorText = null);
  }

  void _clearYearsError() {
    if (_yearsErrorText != null) setState(() => _yearsErrorText = null);
  }

  /// Brings the Profile tab back (if needed) and then focuses [node].
  void _focusOnProfileTab(FocusNode node) {
    if (_tab.index == 0 && !_tab.indexIsChanging) {
      node.requestFocus();
      return;
    }
    void onTab() {
      if (_tab.indexIsChanging || _tab.index != 0) return;
      _tab.removeListener(onTab);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) node.requestFocus();
      });
    }
    _tab.addListener(onTab);
    if (_tab.index != 0) _tab.animateTo(0);
  }

  /// True only when an update's `.select('id')` returned the changed row (RLS
  /// filters a refused update to 0 rows without an error). Each update keeps
  /// its column keys literal at the call site so the schema contract guard
  /// can read which `user_profiles` columns this screen writes.
  bool _changedRow(Object? rows) => (rows as List).isNotEmpty;

  /// True while the read numbered [seq] for [uid] is still the one to apply:
  /// no newer load started and [uid] is still the signed-in coach.
  bool _isCurrentLoad(int seq, String uid) =>
      mounted && seq == _loadSeq && _db.auth.currentUser?.id == uid;

  Future<void> _load() async {
    // r3 · a Retry SnackBar can outlive the screen: nothing to load into.
    if (!mounted) return;
    final uid = _db.auth.currentUser?.id;
    final seq = ++_loadSeq;
    if (uid == null) {
      _forget();
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = _signedOutBody;
        });
      }
      return;
    }
    // A refresh of the coach already shown keeps what is shown until the new
    // read lands (and if it fails). Anyone else starts from nothing.
    final refresh = _loadedFor == uid;
    if (!refresh) {
      _forget();
      _owner = uid;
      _loading = true;
      _loadError = null;
      if (mounted) setState(() {});
    }
    try {
      final profileData = await _db.from('user_profiles').select('*').eq('id', uid).maybeSingle();
      if (!_isCurrentLoad(seq, uid)) return;
      if (profileData == null) {
        // No row came back: the profile was not read, so there is nothing
        // the form may show or save over.
        throw StateError('user_profiles: no row for the signed-in coach');
      }
      // P0-FL-54: only this coach's own row fills the screen.
      if (confirmedProfileRead(AsyncData(profileData), _db.auth.currentUser) ==
          null) {
        throw StateError('user_profiles: the row read is not the signed-in coach');
      }
      // Wave 1 (migration 132): a team lead no longer reads `user_profiles`, so
      // the embedded resource above this line used to return nothing. D1(iii)
      // limits a lead to the minimum-necessary columns, which are served by
      // `team_member_profiles` — and a PostgREST embed cannot traverse a view,
      // so this is a two-step read. The rows are re-shaped under the same
      // `user_profiles` key the team tab already renders.
      final memberships = await _db.from('coach_team_members')
          .select()
          .eq('coach_id', uid);
      final memberIds = List<Map<String, dynamic>>.from(memberships as List)
          .map((m) => m['member_id'] as String?)
          .whereType<String>()
          .toList();
      final rosterProfiles = memberIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(await _db
              .from('team_member_profiles')
              .select('id, first_name, last_name, email, avatar_url')
              .inFilter('id', memberIds) as List);
      final profileById = {
        for (final r in rosterProfiles) r['id'] as String: r,
      };
      final teamData = [
        for (final m in List<Map<String, dynamic>>.from(memberships as List))
          {...m, 'user_profiles': profileById[m['member_id'] as String?] ?? const {}},
      ];
      final reviewData = await _db
          .from('coach_reviews')
          .select('*, public_profiles!client_id(first_name, last_name, avatar_url)')
          .eq('coach_id', uid)
          .order('created_at', ascending: false);
      // Every await above is a point where the account can change or a newer
      // load can start: only the current one is applied.
      if (!mounted || !_isCurrentLoad(seq, uid)) return;
      final team = teamData;
      final p = profileData;
      _bioCtrl.text = p['bio'] as String? ?? '';
      _priceCtrl.text = _numText(p['pricing_monthly']);
      _yearsCtrl.text = _numText(p['years_experience']);
      _taglineCtrl.text = p['tagline'] as String? ?? '';
      _specialties = List<String>.from(p['specialties'] as List? ?? []);
      _certifications = List<String>.from(p['certifications'] as List? ?? []);
      setState(() {
        _profile = p;
        _team = List<Map<String, dynamic>>.from(team as List);
        _reviews = List<Map<String, dynamic>>.from(reviewData as List);
        _owner = uid;
        _loadedFor = uid;
        _loading = false;
        _loadError = null;
      });
    } catch (e, s) {
      reportError('CoachBusinessScreen._load', e, s);
      if (!mounted || !_isCurrentLoad(seq, uid)) return;
      if (_loadedFor == uid) {
        // A failed refresh of the coach already shown: keep what is shown
        // (it is still this coach's last confirmed profile) and say so.
        _say(_couldnt('refresh your business profile', e),
            error: true,
            action: SnackBarAction(
                label: 'Retry', textColor: _bg, onPressed: _load));
        return;
      }
      setState(() {
        _loading = false;
        _loadError = isNetworkFailure(e) ? _checkConnection : _tryLater;
      });
    }
  }

  Future<void> _save() async {
    if (_loadError != null || _loading || _saving || _certWriteInFlight) return;
    // Validate before anything is written. An empty field is left out of the
    // update (the stored value stays); a non-empty one must be a number >= 0.
    // An explicit 0 price is still written as 0 (Decision 18 is open).
    final priceText = _priceCtrl.text.trim();
    final yearsText = _yearsCtrl.text.trim();
    final price = priceText.isEmpty ? null : double.tryParse(priceText);
    final years = yearsText.isEmpty ? null : int.tryParse(yearsText);
    final priceBad =
        priceText.isNotEmpty && (price == null || !price.isFinite || price < 0);
    final yearsBad = yearsText.isNotEmpty && (years == null || years < 0);
    setState(() {
      _priceErrorText = priceBad ? _priceError : null;
      _yearsErrorText = yearsBad ? _yearsError : null;
    });
    if (priceBad || yearsBad) {
      _focusOnProfileTab(priceBad ? _priceFocus : _yearsFocus);
      _say(
          priceBad && yearsBad
              ? '$_bothError Nothing was saved.'
              : priceBad
                  ? '$_priceError Nothing was saved.'
                  : '$_yearsError Nothing was saved.',
          error: true);
      return;
    }
    // P0-FL-54: the form must be the signed-in coach's (it is what is saved).
    final uid = _requireShownCoach('save your profile');
    if (uid == null) return;
    final bio = _bioCtrl.text.trim();
    final tagline = _taglineCtrl.text.trim();
    final specialties = List<String>.from(_specialties);
    final certifications = List<String>.from(_certifications);
    setState(() => _saving = true);
    try {
      final saved = _changedRow(await _db.from('user_profiles').update({
        'bio': bio,
        if (price != null) 'pricing_monthly': price,
        if (years != null) 'years_experience': years,
        'tagline': tagline,
        'specialties': specialties,
        'certifications': certifications,
      }).eq('id', uid).select('id'));
      // The account changed while this was in flight: what is shown now is
      // another coach's, so nothing here is updated or announced over it.
      if (_loadedFor != uid) return;
      if (!saved) {
        _say(_couldntNothingChanged('save your profile'), error: true);
        return;
      }
      // What the server now holds, so a later blank field puts back the value
      // that is actually saved (not the one read when the screen opened).
      _profile = {
        ...?_profile,
        'bio': bio,
        if (price != null) 'pricing_monthly': price,
        if (years != null) 'years_experience': years,
        'tagline': tagline,
        'specialties': specialties,
        'certifications': certifications,
      };
      // A blank price/years was left out of the update, so the stored value
      // stands. Show it again instead of a blank field under "updated" — and
      // explain only when a field was actually refilled: with nothing saved
      // the field stays blank and there is nothing to explain.
      var refilled = false;
      if (mounted) {
        setState(() {
          if (price == null && _priceCtrl.text.trim().isEmpty) {
            final kept = _numText(_profile?['pricing_monthly']);
            if (kept.isNotEmpty) {
              _priceCtrl.text = kept;
              refilled = true;
            }
          }
          if (years == null && _yearsCtrl.text.trim().isEmpty) {
            final kept = _numText(_profile?['years_experience']);
            if (kept.isNotEmpty) {
              _yearsCtrl.text = kept;
              refilled = true;
            }
          }
        });
      }
      _say(refilled ? _blankKept : 'Profile updated!');
    } catch (e, s) {
      reportError('CoachBusinessScreen._save', e, s);
      if (_loadedFor == uid) {
        _say(_couldnt('save your profile', e), error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadTransformationPhoto() async {
    // FL-55: one photo at a time — two uploads each copied the same list and
    // the second write dropped the first photo.
    if (_uploadingPhoto) return;
    // P0-FL-54: the list copied below must be the signed-in coach's.
    final uid = _requireShownCoach('add the photo');
    if (uid == null) return;
    setState(() => _uploadingFor.add(uid));
    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (img == null) return;
      // The picker can stay open a long time: still the same coach? If not,
      // nothing is written, and nothing is said to the coach shown now (they
      // did not tap Add Photo).
      if (!_showsSignedInCoach || _loadedFor != uid) return;
      // Use bytes + uploadBinary so this works on web as well as native.
      final bytes = await img.readAsBytes();
      final ext = (img.name.contains('.') ? img.name.split('.').last : 'jpg').toLowerCase();
      final path = 'coach-transformations/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _db.storage.from('coach-media').uploadBinary(path, bytes,
          fileOptions: FileOptions(contentType: 'image/$ext', upsert: true));
      final url = _db.storage.from('coach-media').getPublicUrl(path);
      // The list is copied from the profile shown, so it must still be this
      // coach's — otherwise another coach's photos would be written here.
      if (!_showsSignedInCoach || _loadedFor != uid) return;
      final current = List<String>.from(_profile?['transformation_photo_urls'] as List? ?? []);
      current.add(url);
      final saved = _changedRow(await _db
          .from('user_profiles')
          .update({'transformation_photo_urls': current})
          .eq('id', uid)
          .select('id'));
      if (!mounted || _loadedFor != uid) return; // another coach is shown now
      if (!saved) {
        _say(_couldntNothingChanged('add the photo'), error: true);
        return;
      }
      // What the server now holds, kept even if the refresh below fails.
      setState(() => _profile = {...?_profile, 'transformation_photo_urls': current});
      _say('Photo added');
      await _load();
    } catch (e, s) {
      reportError('CoachBusinessScreen._uploadTransformationPhoto', e, s);
      if (_loadedFor == uid) _say(_couldnt('add the photo', e), error: true);
    } finally {
      // Only this coach's own guard is cleared (another coach may have
      // started a photo of their own meanwhile).
      if (mounted) {
        setState(() => _uploadingFor.remove(uid));
      } else {
        _uploadingFor.remove(uid);
      }
    }
  }

  void _toggleSpecialty(String s) => setState(() =>
    _specialties.contains(s) ? _specialties.remove(s) : _specialties.add(s));

  // Certifications persist immediately (no dependence on the Save button, and
  // safe against a reload re-reading the list from the DB).
  Future<void> _persistCerts(List<String> next,
      {required String what, String? forCoach}) async {
    if (_certWriteInFlight || _saving) return;
    // P0-FL-54: [next] is built from the list shown, so it must be the
    // signed-in coach's — and, from the dialog, the coach it was opened for.
    final uid = _requireShownCoach(what);
    if (uid == null) return;
    if (forCoach != null && forCoach != uid) {
      _say(_otherAccount(what), error: true);
      return;
    }
    final prev = List<String>.from(_certifications);
    setState(() {
      _certWriteInFlight = true;
      _certifications = next;
    });
    String? failure;
    try {
      final saved = _changedRow(await _db
          .from('user_profiles')
          .update({'certifications': next})
          .eq('id', uid)
          .select('id'));
      if (!saved) failure = _couldntNothingChanged(what);
    } catch (e, s) {
      reportError('CoachBusinessScreen._persistCerts', e, s);
      failure = _couldnt(what, e);
    } finally {
      if (mounted) {
        setState(() => _certWriteInFlight = false);
      } else {
        _certWriteInFlight = false;
      }
    }
    // Rolled back only onto the same coach's list: after an account change
    // the list shown is another coach's (and `prev` is not theirs).
    if (failure != null && mounted && _loadedFor == uid) {
      setState(() => _certifications = prev);
      _say(failure, error: true);
    }
  }

  Future<void> _addCertification(String cert, {String? forCoach}) {
    final c = cert.trim();
    if (c.isEmpty || _certifications.contains(c)) return Future.value();
    return _persistCerts([..._certifications, c],
        what: 'add the certification', forCoach: forCoach);
  }

  Future<void> _removeCertification(String cert) =>
    _persistCerts(_certifications.where((c) => c != cert).toList(),
        what: 'remove the certification');

  @override
  Widget build(BuildContext context) {
    // P0-FL-54: between a sign-in and its auth event reaching this screen the
    // data may still be the previous coach's — it is not shown meanwhile.
    final loading = _loading ||
        (_loadError == null && _loadedFor != null && !_showsSignedInCoach);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _wht, size: 20),
        tooltip: 'Back',
          onPressed: () => Navigator.pop(context)),
        title: const Text('Business Profile', style: TextStyle(color: _wht, fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          if (!loading && _loadError == null) TextButton(
            onPressed: _saving || _certWriteInFlight ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: _brand, strokeWidth: 2))
                : const Text('Save', style: TextStyle(color: _brand, fontWeight: FontWeight.w700))),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: _brand, labelColor: _wht,
          unselectedLabelColor: _mut,
          tabs: const [Tab(text: 'Profile'), Tab(text: 'Specialties'), Tab(text: 'Team'), Tab(text: 'Reviews')],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(
              color: _brand, semanticsLabel: 'Loading your business profile'))
          : _loadError != null
          // Signed out is not a failed load, and retrying changes nothing.
          ? _loadError == _signedOutBody
              ? const _LoadFailed(
                  title: "You're signed out", message: _signedOutBody)
              : _LoadFailed(message: _loadError!, onRetry: _load)
          : TabBarView(controller: _tab, children: [
              _ProfileTab(
                bioCtrl: _bioCtrl, priceCtrl: _priceCtrl,
                yearsCtrl: _yearsCtrl, taglineCtrl: _taglineCtrl,
                priceError: _priceErrorText, yearsError: _yearsErrorText,
                priceFocus: _priceFocus, yearsFocus: _yearsFocus,
                onPriceChanged: _clearPriceError,
                onYearsChanged: _clearYearsError,
                certifications: _certifications,
                transformationUrls: List<String>.from(_profile?['transformation_photo_urls'] as List? ?? []),
                onAddCert: () => _showAddCert(),
                onRemoveCert: _removeCertification,
                onAddPhoto: _uploadTransformationPhoto,
                uploadingPhoto: _uploadingPhoto,
              ),
              _SpecialtiesTab(selected: _specialties, all: _specialtyOptions, onToggle: _toggleSpecialty),
              _TeamTab(team: _team, onInvite: _showInviteTeam),
              _ReviewsTab(reviews: _reviews, ratingAvg: (_profile?['rating_avg'] as num?)?.toDouble() ?? 0.0),
            ]),
    );
  }

  Future<void> _showAddCert() async {
    // The dialog owns its controller: disposing it here as soon as the route
    // popped left the closing animation rendering a disposed controller.
    // P0-FL-54: what is typed here is for the coach shown when it opened.
    final forCoach = _loadedFor;
    final text = await showDialog<String>(
        context: context,
        builder: (_) =>
            _AddCertDialog(existing: List<String>.unmodifiable(_certifications)));
    if (text != null && text.isNotEmpty) {
      await _addCertification(text, forCoach: forCoach);
    }
  }

  void _showInviteTeam() => showDialog(context: context, builder: (dctx) {
    final ctrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    // P0-FL-54: the invite joins the team of the coach shown when it opened.
    final forCoach = _loadedFor;
    return AlertDialog(
      backgroundColor: _card,
      title: const Text('Invite Team Member', style: TextStyle(color: _wht)),
      content: TextField(controller: ctrl, style: const TextStyle(color: _wht),
        decoration: const InputDecoration(hintText: 'Email address', hintStyle: TextStyle(color: _mut))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel', style: TextStyle(color: _mut))),
        TextButton(onPressed: () async {
          final email = ctrl.text.trim();
          Navigator.pop(dctx);
          if (email.isEmpty) return;
          final uid = _db.auth.currentUser?.id;
          if (uid == null) {
            messenger.showSnackBar(_snack(_signedOutMsg, error: true));
            return;
          }
          if (uid != forCoach || uid != _loadedFor) {
            messenger.showSnackBar(
                _snack(_otherAccount('save the invite'), error: true));
            return;
          }
          try {
            await _db.from('coach_team_invites')
                .insert({'coach_id': uid, 'email': email, 'role': 'assistant_coach'});
          } catch (e, s) {
            // The invite was not saved, so no email goes out claiming one.
            reportError('CoachBusinessScreen._showInviteTeam', e, s);
            if (_stillInvitingAs(uid)) {
              messenger.showSnackBar(
                  _snack(_couldnt('save the invite', e), error: true));
            }
            return;
          }
          // P0-FL-54 · the account may have changed while the insert was in
          // flight. The email goes out under the login of whoever is signed
          // in (it names them), so it is sent — and announced — only while
          // the inviting coach is still the one signed in and shown.
          if (!_stillInvitingAs(uid)) return;
          var ok = true;
          try {
            final res = await _db.functions.invoke('send-invite-email',
                body: {'email': email, 'type': 'team'});
            ok = (res.data is Map) && res.data['sent'] == true;
          } catch (_) { ok = false; }
          if (!_stillInvitingAs(uid)) return;
          messenger.showSnackBar(ok
              ? SnackBar(content: Text('Invite email sent to $email'))
              : _snack(_inviteEmailNotSent, error: true));
        }, child: const Text('Invite', style: TextStyle(color: _brand))),
      ],
    );
  });
}

class _AddCertDialog extends StatefulWidget {
  /// Certifications already on the profile: adding one again is refused here,
  /// out loud, rather than silently ignored after the dialog closes.
  final List<String> existing;
  const _AddCertDialog({required this.existing});
  @override
  State<_AddCertDialog> createState() => _AddCertDialogState();
}

class _AddCertDialogState extends State<_AddCertDialog> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _ctrl.removeListener(_rebuild);
    _ctrl.dispose();
    super.dispose();
  }

  String get _text => _ctrl.text.trim();
  bool get _duplicate => widget.existing.contains(_text);
  bool get _canAdd => _text.isNotEmpty && !_duplicate;

  void _submit() {
    if (_canAdd) Navigator.pop(context, _text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: _card,
    title: const Text('Add Certification', style: TextStyle(color: _wht)),
    content: TextField(controller: _ctrl, autofocus: true, style: const TextStyle(color: _wht),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(hintText: 'e.g. NASM-CPT',
        hintStyle: const TextStyle(color: _mut),
        errorText: _duplicate ? 'Already added' : null)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
        child: const Text('Cancel', style: TextStyle(color: _mut))),
      TextButton(onPressed: _canAdd ? _submit : null,
        child: Text('Add', style: TextStyle(color: _canAdd ? _brand : _mut))),
    ],
  );
}

// A failed load is not an empty profile: no form, no Save, a way to retry.
class _LoadFailed extends StatelessWidget {
  final String title;
  final String message;
  /// Null: no Try again (nothing a retry could change, e.g. signed out).
  final VoidCallback? onRetry;
  const _LoadFailed({
    this.title = "Couldn't load your business profile",
    required this.message,
    this.onRetry,
  });

  @override
  // Scrolls so large text on a small phone never overflows; announced as a
  // live region so a screen reader hears that the load failed and why.
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded, color: _mut, size: 40),
        const SizedBox(height: 12),
        Text(title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _wht, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center,
          style: const TextStyle(color: _mut, fontSize: 13)),
        if (onRetry != null) ...[
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: onRetry,
          style: OutlinedButton.styleFrom(
            foregroundColor: _brand, side: const BorderSide(color: _brand)),
          child: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w700))),
        ],
        ]),
      ),
    ),
  );
}

class _ProfileTab extends StatelessWidget {
  final TextEditingController bioCtrl, priceCtrl, yearsCtrl, taglineCtrl;
  final String? priceError, yearsError;
  final FocusNode priceFocus, yearsFocus;
  final VoidCallback onPriceChanged, onYearsChanged;
  final List<String> certifications, transformationUrls;
  final VoidCallback onAddCert, onAddPhoto;
  final void Function(String) onRemoveCert;
  final bool uploadingPhoto;
  const _ProfileTab({
    required this.bioCtrl, required this.priceCtrl, required this.yearsCtrl,
    required this.taglineCtrl, required this.certifications,
    required this.transformationUrls, required this.onAddCert,
    required this.onRemoveCert, required this.onAddPhoto,
    required this.uploadingPhoto,
    required this.priceFocus, required this.yearsFocus,
    required this.onPriceChanged, required this.onYearsChanged,
    this.priceError, this.yearsError,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Field('Tagline', taglineCtrl, 'Your one-line pitch to clients'),
      _Field('Bio', bioCtrl, 'Tell clients about your coaching style and background', maxLines: 5),
      _Field('Monthly Price (\$)', priceCtrl, '149', inputType: TextInputType.number,
        errorText: priceError, focusNode: priceFocus, onChanged: onPriceChanged),
      _Field('Years Experience', yearsCtrl, '5', inputType: TextInputType.number,
        errorText: yearsError, focusNode: yearsFocus, onChanged: onYearsChanged),
      const SizedBox(height: 20),
      _SectionHeader('Certifications', onAdd: onAddCert,
          addLabel: 'Add certification'),
      const SizedBox(height: 8),
      if (certifications.isEmpty)
        const Text('No certifications yet — tap “+ Add”.',
          style: TextStyle(color: _mut, fontSize: 12)),
      Wrap(spacing: 8, runSpacing: 8, children: certifications.map((c) =>
        Chip(label: Text(c, style: const TextStyle(color: _wht, fontSize: 12)),
          backgroundColor: _brand.withValues(alpha: 0.2),
          side: const BorderSide(color: _brand),
          deleteIcon: const Icon(Icons.close, size: 14, color: _mut),
          onDeleted: () => onRemoveCert(c))).toList()),
      const SizedBox(height: 24),
      _SectionHeader('Transformation Photos', onAdd: onAddPhoto,
          addLabel: 'Add transformation photo', busy: uploadingPhoto),
      const SizedBox(height: 8),
      SizedBox(height: 120, child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...transformationUrls.map((url) => Container(
            width: 100, height: 120, margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)),
          )),
          // FL-55: a labelled button, disabled and announced while a photo is
          // on its way (a second tap used to start a second upload).
          Semantics(
            button: true,
            enabled: !uploadingPhoto,
            liveRegion: uploadingPhoto,
            // The visible words come first, so "tap Add Photo" (Voice
            // Control) finds it.
            label: uploadingPhoto
                ? 'Adding… transformation photo'
                : 'Add Photo, transformation photo',
            excludeSemantics: true,
            onTap: uploadingPhoto ? null : onAddPhoto,
            child: GestureDetector(
              onTap: uploadingPhoto ? null : onAddPhoto,
              child: Container(
                width: 100, height: 120,
                decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _brd, style: BorderStyle.solid)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  uploadingPhoto
                      ? const SizedBox(width: 28, height: 28,
                          child: CircularProgressIndicator(color: _brand, strokeWidth: 2))
                      : const Icon(Icons.add_photo_alternate_rounded, color: _mut, size: 28),
                  const SizedBox(height: 4),
                  Text(uploadingPhoto ? 'Adding…' : 'Add Photo',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _mut, fontSize: 11)),
                ]),
              ),
            ),
          ),
        ],
      )),
    ]),
  );
}

class _SpecialtiesTab extends StatelessWidget {
  final List<String> selected, all;
  final void Function(String) onToggle;
  const _SpecialtiesTab({required this.selected, required this.all, required this.onToggle});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Wrap(spacing: 10, runSpacing: 10, children: all.map((s) {
      final isOn = selected.contains(s);
      return GestureDetector(
        onTap: () => onToggle(s),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isOn ? _brand : _card,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: isOn ? _brand : _brd)),
          child: Text(s, style: TextStyle(color: isOn ? _wht : _mut, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      );
    }).toList()),
  );
}

// ── UC36: Team Coaching tab ───────────────────────────────────────────────────
class _TeamTab extends StatelessWidget {
  final List<Map<String, dynamic>> team;
  final VoidCallback onInvite;
  const _TeamTab({required this.team, required this.onInvite});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Your Coaching Team', style: TextStyle(color: _wht, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Add assistant coaches who can manage your clients.',
        style: TextStyle(color: _mut, fontSize: 13)),
      const SizedBox(height: 16),
      if (team.isEmpty)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _brd)),
          child: const Center(child: Column(children: [
            Text('👥', style: TextStyle(fontSize: 32)),
            SizedBox(height: 8),
            Text('No team members yet', style: TextStyle(color: _wht, fontSize: 15, fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text('Invite assistant coaches to help manage your clients', style: TextStyle(color: _mut, fontSize: 13), textAlign: TextAlign.center),
          ])),
        )
      else
        ...team.map((m) {
          final p = m['user_profiles'] as Map<String, dynamic>? ?? {};
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _brd)),
            child: Row(children: [
              CircleAvatar(
                radius: 22, backgroundColor: _brand.withValues(alpha: 0.2),
                child: Text('${p['first_name']?[0] ?? '?'}', style: const TextStyle(color: _brand, fontWeight: FontWeight.w700))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim(),
                  style: const TextStyle(color: _wht, fontSize: 14, fontWeight: FontWeight.w600)),
                Text(p['email'] as String? ?? '', style: const TextStyle(color: _mut, fontSize: 12)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: _brand.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(m['role'] as String? ?? 'assistant', style: const TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w600))),
            ]),
          );
        }),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: onInvite,
        style: OutlinedButton.styleFrom(
          foregroundColor: _brand, side: const BorderSide(color: _brand),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Invite Assistant Coach', style: TextStyle(fontWeight: FontWeight.w700)),
      )),
    ]),
  );
}

// ── Shared widgets ────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  final int maxLines;
  final TextInputType inputType;
  final String? errorText;
  final FocusNode? focusNode;
  final VoidCallback? onChanged;
  const _Field(this.label, this.ctrl, this.hint, {this.maxLines = 1,
      this.inputType = TextInputType.text, this.errorText, this.focusNode,
      this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl, maxLines: maxLines, keyboardType: inputType,
        focusNode: focusNode,
        onChanged: onChanged == null ? null : (_) => onChanged!(),
        style: const TextStyle(color: _wht, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint, hintStyle: const TextStyle(color: _mut),
          errorText: errorText,
          filled: true, fillColor: _card,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _brd)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _brd)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _brand))),
      ),
    ]),
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onAdd;
  /// What "+ Add" adds, for screen readers and Voice Control ("Add …").
  final String addLabel;
  /// True while what it adds is on its way: disabled (and announced so).
  final bool busy;
  const _SectionHeader(this.title,
      {required this.onAdd, required this.addLabel, this.busy = false});
  @override
  Widget build(BuildContext context) => Row(children: [
    Text(title, style: const TextStyle(color: _wht, fontSize: 14, fontWeight: FontWeight.w700)),
    const Spacer(),
    // A >= 44 px target around the same pill (the pill itself is unchanged).
    Semantics(
      button: true,
      enabled: !busy,
      label: addLabel,
      excludeSemantics: true,
      onTap: busy ? null : onAdd,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: busy ? null : onAdd,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Align(
            alignment: Alignment.centerRight,
            widthFactor: 1,
            heightFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _brand.withValues(alpha: busy ? 0.05 : 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text('+ Add', style: TextStyle(color: busy ? _mut : _brand, fontSize: 12, fontWeight: FontWeight.w600))),
          ),
        ),
      ),
    ),
  ]);
}

// ── Reviews Tab ───────────────────────────────────────────────────────────────
class _ReviewsTab extends StatelessWidget {
  final List<Map<String, dynamic>> reviews;
  final double ratingAvg;
  const _ReviewsTab({required this.reviews, required this.ratingAvg});

  @override
  Widget build(BuildContext context) {
    final reviewCount = reviews.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _brd),
            ),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ratingAvg > 0 ? ratingAvg.toStringAsFixed(1) : '--',
                  style: const TextStyle(color: _wht, fontSize: 48,
                    fontWeight: FontWeight.w800, height: 1, letterSpacing: -2)),
                const SizedBox(height: 4),
                Row(children: List.generate(5, (i) => Icon(
                  i < ratingAvg.floor() ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: _brand, size: 18))),
                const SizedBox(height: 4),
                Text('$reviewCount ${reviewCount == 1 ? 'review' : 'reviews'}',
                  style: const TextStyle(color: _mut, fontSize: 12)),
              ]),
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final stars in [5, 4, 3, 2, 1])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('$stars', style: const TextStyle(color: _mut, fontSize: 11)),
                      const SizedBox(width: 4),
                      Icon(Icons.star_rounded, color: _brand, size: 12),
                      const SizedBox(width: 6),
                      Container(
                        width: 80, height: 5,
                        decoration: BoxDecoration(
                          color: _brd, borderRadius: BorderRadius.circular(3)),
                        child: FractionallySizedBox(
                          widthFactor: reviewCount > 0
                            ? reviews.where((r) => (r['rating'] as int? ?? 0) == stars).length / reviewCount
                            : 0,
                          alignment: Alignment.centerLeft,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _brand, borderRadius: BorderRadius.circular(3)))),
                      ),
                    ]),
                  ),
              ]),
            ]),
          ),
          const SizedBox(height: 20),

          if (reviews.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star_outline_rounded, color: _mut, size: 40),
                const SizedBox(height: 12),
                const Text('No reviews yet', style: TextStyle(color: _mut, fontSize: 14)),
                const SizedBox(height: 4),
                const Text('Reviews from your clients will appear here',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _mut, fontSize: 12)),
              ]),
            )
          else
            ...reviews.map((r) {
              final profile = r['public_profiles'] as Map<String, dynamic>? ?? {};
              final name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
              final rating = r['rating'] as int? ?? 0;
              final text = r['review_text'] as String?;
              final raw = r['created_at'] as String?;
              final dt = raw != null ? DateTime.tryParse(raw)?.toLocal() : null;
              final months = ['', 'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
              final dateStr = dt != null ? '${months[dt.month]} ${dt.year}' : '';
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _brd)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _brand.withValues(alpha: 0.15)),
                      alignment: Alignment.center,
                      child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'C',
                        style: const TextStyle(color: _brand, fontSize: 14, fontWeight: FontWeight.w700))),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name.isEmpty ? 'Client' : name,
                        style: const TextStyle(color: _wht, fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(dateStr, style: const TextStyle(color: _mut, fontSize: 11)),
                    ])),
                    Row(children: List.generate(5, (i) => Icon(
                      i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: _brand, size: 14))),
                  ]),
                  if (text != null && text.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(text, style: const TextStyle(color: _mut, fontSize: 13, height: 1.4)),
                  ],
                ]),
              );
            }),
        ],
      ),
    );
  }
}
