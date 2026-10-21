import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

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

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    _bioCtrl.dispose(); _priceCtrl.dispose();
    _yearsCtrl.dispose(); _taglineCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final profileData = await _db.from('user_profiles').select('*').eq('id', uid).maybeSingle();
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
      final team = teamData;
      final p = profileData;
      if (p != null) {
        _bioCtrl.text = p['bio'] as String? ?? '';
        _priceCtrl.text = (p['pricing_monthly'] ?? '').toString();
        _yearsCtrl.text = (p['years_experience'] ?? '').toString();
        _taglineCtrl.text = p['tagline'] as String? ?? '';
        _specialties = List<String>.from(p['specialties'] as List? ?? []);
        _certifications = List<String>.from(p['certifications'] as List? ?? []);
      }
      if (!mounted) return;
      setState(() {
        _profile = p;
        _team = List<Map<String, dynamic>>.from(team as List);
        _reviews = List<Map<String, dynamic>>.from(reviewData as List);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await _db.from('user_profiles').update({
        'bio': _bioCtrl.text.trim(),
        'pricing_monthly': double.tryParse(_priceCtrl.text) ?? 0,
        'years_experience': int.tryParse(_yearsCtrl.text) ?? 0,
        'tagline': _taglineCtrl.text.trim(),
        'specialties': _specialties,
        'certifications': _certifications,
      }).eq('id', uid);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Profile updated!'), backgroundColor: Color(0xFF6FFBBE)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save profile.'),
        backgroundColor: const Color(0xFFFFB4AB)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadTransformationPhoto() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img == null) return;
    try {
      // Use bytes + uploadBinary so this works on web as well as native.
      final bytes = await img.readAsBytes();
      final ext = (img.name.contains('.') ? img.name.split('.').last : 'jpg').toLowerCase();
      final path = 'coach-transformations/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _db.storage.from('coach-media').uploadBinary(path, bytes,
          fileOptions: FileOptions(contentType: 'image/$ext', upsert: true));
      final url = _db.storage.from('coach-media').getPublicUrl(path);
      final current = List<String>.from(_profile?['transformation_photo_urls'] as List? ?? []);
      current.add(url);
      await _db.from('user_profiles').update({'transformation_photo_urls': current}).eq('id', uid);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Photo added'), backgroundColor: Color(0xFF6FFBBE)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not upload photo.'),
        backgroundColor: const Color(0xFFFFB4AB)));
    }
  }

  void _toggleSpecialty(String s) => setState(() =>
    _specialties.contains(s) ? _specialties.remove(s) : _specialties.add(s));

  // Certifications persist immediately (no dependence on the Save button, and
  // safe against a reload re-reading the list from the DB).
  Future<void> _persistCerts(List<String> next, {required String failMsg}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    final prev = List<String>.from(_certifications);
    setState(() => _certifications = next);
    try {
      await _db.from('user_profiles').update({'certifications': next}).eq('id', uid);
    } catch (e) {
      if (mounted) {
        setState(() => _certifications = prev);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failMsg), backgroundColor: const Color(0xFFFFB4AB)));
      }
    }
  }

  Future<void> _addCertification(String cert) {
    final c = cert.trim();
    if (c.isEmpty || _certifications.contains(c)) return Future.value();
    return _persistCerts([..._certifications, c], failMsg: 'Could not add certification');
  }

  Future<void> _removeCertification(String cert) =>
    _persistCerts(_certifications.where((c) => c != cert).toList(),
        failMsg: 'Could not remove certification');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _wht, size: 20),
        tooltip: 'Back',
          onPressed: () => Navigator.pop(context)),
        title: const Text('Business Profile', style: TextStyle(color: _wht, fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          if (!_loading) TextButton(
            onPressed: _save,
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : TabBarView(controller: _tab, children: [
              _ProfileTab(
                bioCtrl: _bioCtrl, priceCtrl: _priceCtrl,
                yearsCtrl: _yearsCtrl, taglineCtrl: _taglineCtrl,
                certifications: _certifications,
                transformationUrls: List<String>.from(_profile?['transformation_photo_urls'] as List? ?? []),
                onAddCert: () => _showAddCert(),
                onRemoveCert: _removeCertification,
                onAddPhoto: _uploadTransformationPhoto,
              ),
              _SpecialtiesTab(selected: _specialties, all: _specialtyOptions, onToggle: _toggleSpecialty),
              _TeamTab(team: _team, onInvite: _showInviteTeam),
              _ReviewsTab(reviews: _reviews, ratingAvg: (_profile?['rating_avg'] as num?)?.toDouble() ?? 0.0),
            ]),
    );
  }

  void _showAddCert() {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (dctx) => AlertDialog(
      backgroundColor: _card,
      title: const Text('Add Certification', style: TextStyle(color: _wht)),
      content: TextField(controller: ctrl, autofocus: true, style: const TextStyle(color: _wht),
        decoration: const InputDecoration(hintText: 'e.g. NASM-CPT', hintStyle: TextStyle(color: _mut))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx),
          child: const Text('Cancel', style: TextStyle(color: _mut))),
        TextButton(onPressed: () {
          final text = ctrl.text.trim();
          Navigator.pop(dctx);
          if (text.isNotEmpty) _addCertification(text);
        }, child: const Text('Add', style: TextStyle(color: _brand))),
      ],
    )).then((_) => ctrl.dispose());
  }

  void _showInviteTeam() => showDialog(context: context, builder: (dctx) {
    final ctrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
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
          await _db.from('coach_team_invites')
              .insert({'coach_id': uid, 'email': email, 'role': 'assistant_coach'})
              .catchError((_) {});
          var ok = true;
          try {
            final res = await _db.functions.invoke('send-invite-email',
                body: {'email': email, 'type': 'team'});
            ok = (res.data is Map) && res.data['sent'] == true;
          } catch (_) { ok = false; }
          messenger.showSnackBar(SnackBar(
              content: Text(ok ? 'Invite email sent to $email' : 'Invite saved, but email could not be sent.')));
        }, child: const Text('Invite', style: TextStyle(color: _brand))),
      ],
    );
  });
}

class _ProfileTab extends StatelessWidget {
  final TextEditingController bioCtrl, priceCtrl, yearsCtrl, taglineCtrl;
  final List<String> certifications, transformationUrls;
  final VoidCallback onAddCert, onAddPhoto;
  final void Function(String) onRemoveCert;
  const _ProfileTab({
    required this.bioCtrl, required this.priceCtrl, required this.yearsCtrl,
    required this.taglineCtrl, required this.certifications,
    required this.transformationUrls, required this.onAddCert,
    required this.onRemoveCert, required this.onAddPhoto,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Field('Tagline', taglineCtrl, 'Your one-line pitch to clients'),
      _Field('Bio', bioCtrl, 'Tell clients about your coaching style and background', maxLines: 5),
      _Field('Monthly Price (\$)', priceCtrl, '149', inputType: TextInputType.number),
      _Field('Years Experience', yearsCtrl, '5', inputType: TextInputType.number),
      const SizedBox(height: 20),
      _SectionHeader('Certifications', onAdd: onAddCert),
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
      _SectionHeader('Transformation Photos', onAdd: onAddPhoto),
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
          GestureDetector(
            onTap: onAddPhoto,
            child: Container(
              width: 100, height: 120,
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _brd, style: BorderStyle.solid)),
              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_photo_alternate_rounded, color: _mut, size: 28),
                SizedBox(height: 4),
                Text('Add Photo', style: TextStyle(color: _mut, fontSize: 11)),
              ]),
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
  const _Field(this.label, this.ctrl, this.hint, {this.maxLines = 1, this.inputType = TextInputType.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl, maxLines: maxLines, keyboardType: inputType,
        style: const TextStyle(color: _wht, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint, hintStyle: const TextStyle(color: _mut),
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
  const _SectionHeader(this.title, {required this.onAdd});
  @override
  Widget build(BuildContext context) => Row(children: [
    Text(title, style: const TextStyle(color: _wht, fontSize: 14, fontWeight: FontWeight.w700)),
    const Spacer(),
    GestureDetector(
      onTap: onAdd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: _brand.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: const Text('+ Add', style: TextStyle(color: _brand, fontSize: 12, fontWeight: FontWeight.w600))),
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
