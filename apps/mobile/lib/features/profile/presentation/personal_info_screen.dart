import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/domain/auth_provider.dart';
import '../../coach/presentation/coach_business_screen.dart';

const _bg    = Color(0xFF0E0E0F);
const _surf  = Color(0xFF201F20);
const _pri   = Color(0xFFDDB7FF);
const _priC  = Color(0xFFB76DFF);
const _tert  = Color(0xFF6FFBBE);
const _onS   = Color(0xFFE5E2E3);
const _onSV  = Color(0xFFCDC3D0);
const _out   = Color(0xFF968E99);
const _outV  = Color(0xFF4B444F);
const _err   = Color(0xFFFFB4AB);

/// The `user_profiles` update the Personal Info screen sends (extracted so the
/// correction contract is testable without a backend — QAX-COR-01).
@visibleForTesting
Map<String, dynamic> buildPersonalInfoPayload({
  required String firstName,
  required String lastName,
  required String? gender,
  required DateTime? dateOfBirth,
  required String phone,
  required bool isCoach,
  required String height,
  required String weight,
  required String goalWeight,
  required String? fitnessGoal,
  required String? activityLevel,
  required int trainingDays,
  required String? trainingLocation,
  required String? nutritionGoal,
}) {
  // A cleared field is sent as null so the stored value is actually removed;
  // omitting it would keep the old value while the screen reports success.
  String? orNull(String v) => v.trim().isEmpty ? null : v.trim();
  double? number(String v, String label) {
    final t = v.trim();
    if (t.isEmpty) return null;
    final n = double.tryParse(t);
    // Never coerce unreadable input to 0 — that writes a false measurement.
    if (n == null) throw FormatException('Enter a valid number for $label.');
    return n;
  }

  final payload = <String, dynamic>{
    'first_name': firstName.trim(),
    'last_name':  lastName.trim(),
    'gender':     gender,
    'phone':      orNull(phone),
  };
  // The date picker cannot produce "no date", so an unset DOB stays untouched.
  if (dateOfBirth != null) payload['date_of_birth'] = dateOfBirth.toIso8601String().split('T')[0];
  // Client-only fitness fields — not written for coaches.
  if (!isCoach) {
    payload['height_cm']      = number(height, 'height');
    payload['weight_kg']      = number(weight, 'weight');
    payload['weight_goal_kg'] = number(goalWeight, 'goal weight');
    if (fitnessGoal != null)      payload['fitness_goal']            = fitnessGoal;
    if (activityLevel != null)    payload['activity_level']          = activityLevel;
    payload['training_days_per_week'] = trainingDays;
    if (trainingLocation != null) payload['training_location']       = trainingLocation;
    if (nutritionGoal != null)    payload['nutrition_goal']          = nutritionGoal;
  }
  return payload;
}

class PersonalInfoScreen extends ConsumerStatefulWidget {
  const PersonalInfoScreen({super.key});
  @override
  ConsumerState<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends ConsumerState<PersonalInfoScreen> {
  final _fnCtrl     = TextEditingController();
  final _lnCtrl     = TextEditingController();
  final _phoneCtrl  = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _goalCtrl   = TextEditingController();

  String? _gender;
  DateTime? _dob;
  String? _fitnessGoal;
  String? _activityLevel;
  int _trainingDays = 3;
  String? _trainingLocation;
  String? _nutritionGoal;
  String? _avatarUrl;
  bool _loadingAvatar = false;
  bool _saving = false;
  bool _loaded = false;
  bool _isCoach = false;

  static const _goalOptions = [
    ('lose_fat',           'Lose Fat'),
    ('build_muscle',       'Build Muscle'),
    ('maintain_weight',    'Maintain Weight'),
    ('improve_health',     'Improve Health'),
    ('performance',        'Athletic Performance'),
    // legacy values — kept so old data displays correctly
    ('lose_weight',        'Lose Weight'),
    ('improve_fitness',    'Improve Fitness'),
    ('sport_performance',  'Sport Performance'),
  ];
  static const _activityOptions = [
    ('sedentary',          'Sedentary',          'Little or no exercise'),
    ('lightly_active',     'Lightly Active',     '1–3 days / week'),
    ('moderately_active',  'Moderately Active',  '3–5 days / week'),
    ('very_active',        'Very Active',        '6–7 days / week'),
    ('extremely_active',   'Extremely Active',   'Physical job or 2× / day'),
  ];
  static const _locationOptions = [
    ('gym',     'Gym'),
    ('home',    'Home'),
    ('outdoor', 'Outdoor'),
    ('mixed',   'Mixed'),
  ];
  static const _nutritionOptions = [
    ('cut',      'Cutting (calorie deficit)'),
    ('bulk',     'Bulking (calorie surplus)'),
    ('maintain', 'Maintenance'),
    ('flexible', 'Flexible / Intuitive'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  void _loadData() {
    final p = ref.read(currentUserProfileProvider).valueOrNull
        ?? ref.read(currentUserProfileProvider).asData?.value;
    if (p == null) return;
    _fnCtrl.text     = p['first_name'] as String? ?? '';
    _lnCtrl.text     = p['last_name']  as String? ?? '';
    _phoneCtrl.text  = p['phone']      as String? ?? '';
    final h = (p['height_cm']      as num?)?.toDouble();
    final w = (p['weight_kg']      as num?)?.toDouble();
    final g = (p['weight_goal_kg'] as num?)?.toDouble();
    if (h != null) _heightCtrl.text = h.toStringAsFixed(0);
    if (w != null) _weightCtrl.text = w.toStringAsFixed(1);
    if (g != null) _goalCtrl.text   = g.toStringAsFixed(1);
    _fitnessGoal      = p['fitness_goal']          as String?;
    _activityLevel    = p['activity_level']         as String?;
    _trainingDays     = (p['training_days_per_week'] as num?)?.toInt() ?? 3;
    _trainingLocation = p['training_location']       as String?;
    _nutritionGoal    = p['nutrition_goal']          as String?;
    _avatarUrl        = p['avatar_url']              as String?;
    _gender           = p['gender']                  as String?;
    _isCoach          = (p['role'] as String?) == 'coach';
    final dobStr      = p['date_of_birth']            as String?;
    if (dobStr != null) _dob = DateTime.tryParse(dobStr);
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _fnCtrl.dispose(); _lnCtrl.dispose(); _phoneCtrl.dispose();
    _heightCtrl.dispose(); _weightCtrl.dispose(); _goalCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null || !mounted) return;
    setState(() => _loadingAvatar = true);
    try {
      final uid   = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw Exception('Not logged in');
      final bytes = await file.readAsBytes();
      final ext   = (file.name.contains('.') ? file.name.split('.').last : 'jpg').toLowerCase();
      final path  = '$uid/avatar.$ext';
      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(path, bytes,
              fileOptions: FileOptions(contentType: 'image/$ext', upsert: true));
      // Same path is reused (upsert), so the public URL never changes — append
      // a cache-buster so the new image actually shows instead of the cached one.
      final base = Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
      final url = '$base?t=${DateTime.now().millisecondsSinceEpoch}';
      await Supabase.instance.client
          .from('user_profiles')
          .update({'avatar_url': url})
          .eq('id', uid);
      ref.invalidate(currentUserProfileProvider);
      if (mounted) setState(() => _avatarUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not upload photo.'),
          backgroundColor: _err, behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _loadingAvatar = false);
    }
  }

  Future<void> _save() async {
    if (_fnCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('First name is required'),
        backgroundColor: _err, behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _saving = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw Exception('Not logged in');
      final payload = buildPersonalInfoPayload(
        firstName: _fnCtrl.text, lastName: _lnCtrl.text,
        gender: _gender, dateOfBirth: _dob, phone: _phoneCtrl.text,
        isCoach: _isCoach,
        height: _heightCtrl.text, weight: _weightCtrl.text, goalWeight: _goalCtrl.text,
        fitnessGoal: _fitnessGoal, activityLevel: _activityLevel,
        trainingDays: _trainingDays, trainingLocation: _trainingLocation,
        nutritionGoal: _nutritionGoal,
      );

      await Supabase.instance.client
          .from('user_profiles')
          .update(payload)
          .eq('id', uid);
      ref.invalidate(currentUserProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: _tert, behavior: SnackBarBehavior.floating));
        Navigator.of(context).pop();
      }
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          backgroundColor: _err, behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          // ERR-2: this screen edits name, gender and DATE OF BIRTH. A raw
          // database error rendered here is the SEC-PHI-2 shape on a screen
          // holding personal data.
          content: const Text('Failed to save. Please try again.'),
          backgroundColor: _err, behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Populate fields as soon as profile data arrives (handles async load)
    ref.listen<AsyncValue<Map<String, dynamic>?>>(
      currentUserProfileProvider,
      (_, next) { if (next.hasValue && !_loaded) _loadData(); },
    );

    final top    = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // Header
        Container(
          padding: EdgeInsets.only(left: 8, right: 20, top: top),
          decoration: const BoxDecoration(
            color: Color(0x99201F20),
            border: Border(bottom: BorderSide(color: Color(0x1A4B444F)))),
          child: SizedBox(height: 56, child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: _pri, size: 20),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).pop()),
            const Expanded(child: Center(child: Text('PERSONAL INFO',
              style: TextStyle(color: _pri, fontSize: 16,
                fontWeight: FontWeight.w800, letterSpacing: 2)))),
            GestureDetector(
              onTap: _saving ? null : _save,
              child: _saving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: _pri, strokeWidth: 2))
                : const Text('Save',
                    style: TextStyle(color: _pri, fontSize: 15,
                      fontWeight: FontWeight.w700))),
          ])),
        ),

        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 24, 20, bottom + 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Avatar ──
            Center(child: GestureDetector(
              onTap: _pickAndUploadAvatar,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 96, height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [_pri, _priC], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: const [BoxShadow(color: Color(0x4DDDB7FF), blurRadius: 16)]),
                  padding: const EdgeInsets.all(2.5),
                  child: ClipOval(child: _loadingAvatar
                    ? Container(color: _surf,
                        child: const Center(child: CircularProgressIndicator(color: _pri, strokeWidth: 2)))
                    : _avatarUrl != null
                      ? Image.network(_avatarUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _avatarPlaceholder())
                      : _avatarPlaceholder())),
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, color: _priC,
                      border: Border.all(color: _bg, width: 2)),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 14))),
              ]),
            )),
            const SizedBox(height: 8),
            const Center(child: Text('Tap to change photo',
              style: TextStyle(color: _out, fontSize: 12))),
            const SizedBox(height: 32),

            // ── Personal Details ──
            _sectionLabel('PERSONAL DETAILS'),
            const SizedBox(height: 12),
            _card(Column(children: [
              _field('First Name', _fnCtrl, required: true),
              _divider(),
              _field('Last Name', _lnCtrl),
              _divider(),
              _field('Phone', _phoneCtrl, keyboard: TextInputType.phone),
              _divider(),
              _genderRow(),
              _divider(),
              _dobRow(),
            ])),
            const SizedBox(height: 24),

            // ── Coach: professional profile shortcut ──
            if (_isCoach) ...[
              _sectionLabel('COACHING PROFILE'),
              const SizedBox(height: 12),
              _card(GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CoachBusinessScreen())),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(children: [
                    const Icon(Icons.work_outline_rounded, color: _pri, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Business Profile',
                        style: TextStyle(color: _onS, fontSize: 14, fontWeight: FontWeight.w600)),
                      SizedBox(height: 2),
                      Text('Title, bio, rates, specialties & certifications',
                        style: TextStyle(color: _out, fontSize: 12)),
                    ])),
                    const Icon(Icons.chevron_right, color: _outV, size: 18),
                  ]))),
              ),
              const SizedBox(height: 32),
            ],

            // ── Client-only: body metrics, training & nutrition ──
            if (!_isCoach) ...[
              // ── Body Metrics ──
              _sectionLabel('BODY METRICS'),
              const SizedBox(height: 12),
              _card(Column(children: [
                _field('Height (cm)', _heightCtrl, keyboard: TextInputType.number,
                  hint: 'e.g. 175'),
                _divider(),
                _field('Current Weight (kg)', _weightCtrl, keyboard: TextInputType.number,
                  hint: 'e.g. 80.5'),
                _divider(),
                _field('Goal Weight (kg)', _goalCtrl, keyboard: TextInputType.number,
                  hint: 'e.g. 75.0'),
              ])),
              const SizedBox(height: 24),

              // ── Training Goals ──
              _sectionLabel('TRAINING GOALS'),
              const SizedBox(height: 12),
              _card(Column(children: [
                _dropRow('Fitness Goal', _goalOptions.map((o) => o.$1).toList(),
                  _goalOptions.map((o) => o.$2).toList(), _fitnessGoal,
                  (v) => setState(() => _fitnessGoal = v)),
                _divider(),
                _activityRow(),
                _divider(),
                _trainingDaysRow(),
                _divider(),
                _dropRow('Training Location', _locationOptions.map((o) => o.$1).toList(),
                  _locationOptions.map((o) => o.$2).toList(), _trainingLocation,
                  (v) => setState(() => _trainingLocation = v)),
              ])),
              const SizedBox(height: 24),

              // ── Nutrition ──
              _sectionLabel('NUTRITION'),
              const SizedBox(height: 12),
              _card(_dropRow('Nutrition Goal', _nutritionOptions.map((o) => o.$1).toList(),
                _nutritionOptions.map((o) => o.$2).toList(), _nutritionGoal,
                (v) => setState(() => _nutritionGoal = v))),
              const SizedBox(height: 32),
            ],

            // Save button
            GestureDetector(
              onTap: _saving ? null : _save,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFB76DFF), Color(0xFF7C3AED)],
                    begin: Alignment.centerLeft, end: Alignment.centerRight),
                  boxShadow: const [BoxShadow(color: Color(0x557C3AED), blurRadius: 16)]),
                alignment: Alignment.center,
                child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save Changes',
                      style: TextStyle(color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.w700, letterSpacing: 0.3)))),
          ]),
        )),
      ]),
    );
  }

  Widget _avatarPlaceholder() => Container(
    color: _surf,
    child: const Icon(Icons.person, color: _pri, size: 48));

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(label, style: const TextStyle(
      color: _onSV, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2)));

  Widget _card(Widget child) => Container(
    decoration: BoxDecoration(
      color: const Color(0x99201F20),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0x0DFFFFFF))),
    clipBehavior: Clip.antiAlias,
    child: child);

  Widget _divider() => const Divider(height: 1, color: Color(0x1A4B444F));

  Widget _field(String label, TextEditingController ctrl,
      {bool required = false, TextInputType? keyboard, String? hint}) =>
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        SizedBox(width: 140,
          child: Text(label, style: const TextStyle(color: _onSV, fontSize: 14))),
        Expanded(child: TextField(
          controller: ctrl,
          keyboardType: keyboard,
          inputFormatters: keyboard == TextInputType.number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
            : null,
          style: const TextStyle(color: _onS, fontSize: 14),
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: hint ?? (required ? 'Required' : 'Optional'),
            hintStyle: const TextStyle(color: _outV, fontSize: 13)),
        )),
      ]));

  Widget _dropRow(String label, List<String> values, List<String> labels,
      String? current, ValueChanged<String?> onChanged) =>
    GestureDetector(
      onTap: () => _showPicker(label, values, labels, current, onChanged),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(children: [
          Expanded(child: Text(label,
            style: const TextStyle(color: _onSV, fontSize: 14))),
          Text(current != null
            ? (values.contains(current)
                ? labels[values.indexOf(current)]
                : current)
            : 'Not set',
            style: TextStyle(
              color: current != null ? _onS : _outV, fontSize: 14)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, color: _outV, size: 18),
        ])));

  Widget _activityRow() =>
    GestureDetector(
      onTap: () => _showActivityPicker(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Activity Level',
              style: TextStyle(color: _onSV, fontSize: 14)),
            if (_activityLevel != null) ...[
              const SizedBox(height: 2),
              Text(_activityOptions
                .firstWhere((o) => o.$1 == _activityLevel,
                    orElse: () => (_activityLevel!, _activityLevel!, '')).$3,
                style: const TextStyle(color: _out, fontSize: 11)),
            ],
          ])),
          Text(_activityLevel != null
            ? _activityOptions
                .firstWhere((o) => o.$1 == _activityLevel,
                    orElse: () => (_activityLevel!, _activityLevel!, '')).$2
            : 'Not set',
            style: TextStyle(
              color: _activityLevel != null ? _onS : _outV, fontSize: 14)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, color: _outV, size: 18),
        ])));

  Widget _trainingDaysRow() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('Training Days / Week',
          style: TextStyle(color: _onSV, fontSize: 14))),
        Text('$_trainingDays days',
          style: const TextStyle(color: _onS, fontSize: 14, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 8),
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor: _priC,
          inactiveTrackColor: _outV,
          thumbColor: _pri,
          overlayColor: _priC.withValues(alpha: 0.2),
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8)),
        child: Slider(
          value: _trainingDays.toDouble(),
          min: 1, max: 7, divisions: 6,
          onChanged: (v) => setState(() => _trainingDays = v.round()))),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(7, (i) => Text('${i + 1}',
          style: TextStyle(
            color: i + 1 == _trainingDays ? _pri : _outV,
            fontSize: 10, fontWeight: FontWeight.w600)))),
    ]));

  Widget _genderRow() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      const Expanded(child: Text('Gender',
        style: TextStyle(color: _onSV, fontSize: 14))),
      GestureDetector(
        onTap: () => setState(() => _gender = _gender == 'Male' ? null : 'Male'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _gender == 'Male' ? _priC.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _gender == 'Male' ? _priC : _outV, width: 1)),
          child: Text('Male',
            style: TextStyle(
              color: _gender == 'Male' ? _pri : _outV, fontSize: 13,
              fontWeight: FontWeight.w600)))),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => setState(() => _gender = _gender == 'Female' ? null : 'Female'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _gender == 'Female' ? _priC.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _gender == 'Female' ? _priC : _outV, width: 1)),
          child: Text('Female',
            style: TextStyle(
              color: _gender == 'Female' ? _pri : _outV, fontSize: 13,
              fontWeight: FontWeight.w600)))),
    ]));

  Widget _dobRow() {
    final label = _dob == null
        ? 'Not set'
        : '${_dob!.day.toString().padLeft(2,'0')}/${_dob!.month.toString().padLeft(2,'0')}/${_dob!.year}';
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _dob ?? DateTime(1990, 1, 1),
          firstDate: DateTime(1920),
          lastDate: DateTime.now().subtract(const Duration(days: 365 * 13)),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: ColorScheme.dark(
                primary: _priC, onPrimary: Colors.black,
                surface: _surf, onSurface: _onS),
              dialogTheme: const DialogThemeData(backgroundColor: _surf)),
            child: child!),
        );
        if (picked != null && mounted) setState(() => _dob = picked);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(children: [
          const Expanded(child: Text('Date of Birth',
            style: TextStyle(color: _onSV, fontSize: 14))),
          Text(label,
            style: TextStyle(
              color: _dob != null ? _onS : _outV, fontSize: 14)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, color: _outV, size: 18),
        ])));
  }

  void _showPicker(String title, List<String> values, List<String> labels,
      String? current, ValueChanged<String?> onChanged) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(20, 0, 20,
          MediaQuery.of(context).padding.bottom + 20),
        decoration: const BoxDecoration(
          color: Color(0xFF1C1B1C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 14),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: _outV, borderRadius: BorderRadius.circular(2))),
          Text(title, style: const TextStyle(
            color: _onS, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          ...List.generate(values.length, (i) => GestureDetector(
            onTap: () { onChanged(values[i]); Navigator.pop(context); },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: current == values[i]
                  ? _priC.withValues(alpha: 0.12) : _surf,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: current == values[i]
                    ? _priC.withValues(alpha: 0.4) : Colors.transparent)),
              child: Row(children: [
                Expanded(child: Text(labels[i],
                  style: TextStyle(
                    color: current == values[i] ? _pri : _onS,
                    fontSize: 15, fontWeight: FontWeight.w500))),
                if (current == values[i])
                  const Icon(Icons.check_circle, color: _pri, size: 18),
              ])))),
        ])));
  }

  void _showActivityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(20, 0, 20,
          MediaQuery.of(context).padding.bottom + 20),
        decoration: const BoxDecoration(
          color: Color(0xFF1C1B1C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 14),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: _outV, borderRadius: BorderRadius.circular(2))),
          const Text('Activity Level', style: TextStyle(
            color: _onS, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          ..._activityOptions.map((o) => GestureDetector(
            onTap: () {
              setState(() => _activityLevel = o.$1);
              Navigator.pop(context);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _activityLevel == o.$1
                  ? _priC.withValues(alpha: 0.12) : _surf,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _activityLevel == o.$1
                    ? _priC.withValues(alpha: 0.4) : Colors.transparent)),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.$2, style: TextStyle(
                    color: _activityLevel == o.$1 ? _pri : _onS,
                    fontSize: 15, fontWeight: FontWeight.w500)),
                  Text(o.$3, style: const TextStyle(
                    color: _out, fontSize: 12, height: 1.3)),
                ])),
                if (_activityLevel == o.$1)
                  const Icon(Icons.check_circle, color: _pri, size: 18),
              ])))),
        ])));
  }
}
